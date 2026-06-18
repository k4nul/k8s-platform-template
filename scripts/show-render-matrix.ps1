param(
    [string]$RepoRoot,
    [string]$ValuesFile,
    [string]$DefaultValuesFile = "config\platform-values.env.example",
    [ValidateSet("text", "markdown", "json")]
    [string]$Format = "text",
    [string]$OutputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "render-matrix-catalog.ps1")

function ConvertTo-RenderMatrixReportEntry {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Root,

        [Parameter(Mandatory = $true)]
        [object]$Entry
    )

    $resolvedValuesFile = Resolve-RenderMatrixRepoPath -Root $Root -Path $Entry.ValuesFile

    return [PSCustomObject]@{
        Scope = $Entry.Scope
        Name = $Entry.Name
        ValuesFile = $Entry.ValuesFile
        ValuesFileResolved = $resolvedValuesFile
        ValuesFileExists = (Test-Path -Path $resolvedValuesFile -PathType Leaf)
        Version = $Entry.Version
        Profile = $Entry.Profile
        Applications = @($Entry.Applications)
        DataServices = @($Entry.DataServices)
        IncludeJenkins = [bool]$Entry.IncludeJenkins
    }
}

if (-not $PSBoundParameters.ContainsKey("RepoRoot") -or -not $RepoRoot) {
    $RepoRoot = Join-Path $PSScriptRoot ".."
}

$root = (Resolve-Path -Path $RepoRoot).Path
$matrixEntries = @(
    Get-RenderValidationMatrix `
        -Root $root `
        -DefaultValuesFile $DefaultValuesFile `
        -ValuesFile $ValuesFile
)
$reportEntries = @(
    $matrixEntries |
        ForEach-Object {
            ConvertTo-RenderMatrixReportEntry -Root $root -Entry $_
        }
)
$environmentCount = @($reportEntries | Where-Object { $_.Scope -eq "environment" }).Count
$profileCount = @($reportEntries | Where-Object { $_.Scope -eq "profile" }).Count

switch ($Format) {
    "json" {
        $document = ([ordered]@{
            GeneratedAt = (Get-Date).ToString("s")
            RepoRoot = $root
            DefaultValuesFile = $DefaultValuesFile
            OverrideValuesFile = if ($ValuesFile) { $ValuesFile } else { $null }
            EntryCount = $reportEntries.Count
            EnvironmentEntryCount = $environmentCount
            ProfileEntryCount = $profileCount
            Entries = @($reportEntries)
        } | ConvertTo-Json -Depth 10)
    }
    "markdown" {
        $lines = @(
            "# Render Validation Matrix",
            "",
            "## Summary",
            "",
            ("- Repository root: " + $root),
            ("- Matrix entries: " + [string]$reportEntries.Count),
            ("- Environment entries: " + [string]$environmentCount),
            ("- Profile entries: " + [string]$profileCount),
            ("- Default values file: " + $DefaultValuesFile),
            ("- Override values file: " + $(if ($ValuesFile) { $ValuesFile } else { "none" })),
            "",
            "## Entries",
            "",
            "| Scope | Name | Profile | Values File | Values File Exists | Applications | Data Services | Include Jenkins |",
            "| --- | --- | --- | --- | --- | --- | --- | --- |"
        )

        foreach ($entry in $reportEntries) {
            $lines += ("| {0} | {1} | {2} | {3} | {4} | {5} | {6} | {7} |" -f `
                $entry.Scope,
                $entry.Name,
                $entry.Profile,
                $entry.ValuesFile,
                [string]([bool]$entry.ValuesFileExists),
                (Get-RenderMatrixListText -Values @($entry.Applications)),
                (Get-RenderMatrixListText -Values @($entry.DataServices)),
                [string]([bool]$entry.IncludeJenkins))
        }

        $document = $lines -join [Environment]::NewLine
    }
    default {
        $lines = @(
            "Render Validation Matrix",
            "========================",
            ("Repository root: " + $root),
            ("Matrix entries: " + [string]$reportEntries.Count),
            ("Environment entries: " + [string]$environmentCount),
            ("Profile entries: " + [string]$profileCount),
            ("Default values file: " + $DefaultValuesFile),
            ("Override values file: " + $(if ($ValuesFile) { $ValuesFile } else { "none" })),
            ""
        )

        foreach ($entry in $reportEntries) {
            $lines += ("== {0}: {1} ==" -f $entry.Scope, $entry.Name)
            $lines += ("Profile: " + $entry.Profile)
            $lines += ("Values file: " + $entry.ValuesFile)
            $lines += ("Values file exists: " + [string]([bool]$entry.ValuesFileExists))
            $lines += ("Applications: " + (Get-RenderMatrixListText -Values @($entry.Applications)))
            $lines += ("Data services: " + (Get-RenderMatrixListText -Values @($entry.DataServices)))
            $lines += ("Include Jenkins: " + [string]([bool]$entry.IncludeJenkins))
            $lines += ""
        }

        $document = $lines -join [Environment]::NewLine
    }
}

if ($OutputPath) {
    $outputDirectory = Split-Path -Path $OutputPath -Parent
    if ($outputDirectory) {
        New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
    }

    Set-Content -Path $OutputPath -Value $document -NoNewline
}
else {
    Write-Output $document
}
