param(
    [string]$RepoRoot,
    [ValidateSet("text", "markdown", "json")]
    [string]$Format = "text",
    [string]$OutputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if (-not $PSBoundParameters.ContainsKey("RepoRoot") -or -not $RepoRoot) {
    $RepoRoot = Join-Path $PSScriptRoot ".."
}

$root = (Resolve-Path -Path $RepoRoot).Path
$catalogPath = Join-Path $root "config\service-pipelines.psd1"
$catalog = Import-PowerShellDataFile -Path $catalogPath
$services = @($catalog.Services | Sort-Object { $_.Name })

$commonEnvVars = @(
    $services |
        ForEach-Object { @($_.OptionalEnvVars) } |
        Sort-Object -Unique
)

switch ($Format) {
    "json" {
        $document = ([ordered]@{
            CommonEnvironmentVariables = @($commonEnvVars)
            Services = @($services)
        } | ConvertTo-Json -Depth 10)
    }
    "markdown" {
        $lines = @(
            "# Service Pipeline Plan",
            "",
            "## Summary",
            "",
            ("- Services: " + [string]$services.Count),
            ("- Shared Jenkins variables: " + $(if ($commonEnvVars.Count -gt 0) { $commonEnvVars -join ", " } else { "none" })),
            ""
        )

        $lines += "## Service Matrix"
        $lines += ""
        $lines += "| Service | Category | Image | Build Tag | Jenkinsfile | Notes |"
        $lines += "| --- | --- | --- | --- | --- | --- |"
        foreach ($service in $services) {
            $jenkinsfileState = if ([bool]$service.HasJenkinsfile) { "yes" } else { "no" }
            $lines += ("| {0} | {1} | {2} | {3} | {4} | {5} |" -f $service.Name, $service.Category, $service.ImageName, $service.BuildTagStrategy, $jenkinsfileState, $service.Notes)
        }

        $lines += ""
        $lines += "## Service Details"
        $lines += ""

        foreach ($service in $services) {
            $lines += ("### " + $service.Name)
            $lines += ""
            $lines += ("- Category: " + $service.Category)
            $lines += ("- Public image: " + $service.ImageName)
            $lines += ("- Build tag strategy: " + $service.BuildTagStrategy)
            $lines += ("- Compose update: " + $service.ComposeUpdate)
            $lines += ("- Jenkinsfile present: " + [string]([bool]$service.HasJenkinsfile))
            $lines += ("- Required files: " + (@($service.RequiredFiles) -join ", "))
            $lines += ("- Notes: " + $service.Notes)
            $lines += ""
        }

        $document = $lines -join [Environment]::NewLine
    }
    default {
        $lines = @(
            "Service Pipeline Plan",
            "=====================",
            ("Services: " + [string]$services.Count),
            ""
        )

        foreach ($service in $services) {
            $lines += ($service.Name + " [" + $service.Category + "]")
            $lines += ("  Public image: " + $service.ImageName)
            $lines += ("  Build tag strategy: " + $service.BuildTagStrategy)
            $lines += ("  Compose update: " + $service.ComposeUpdate)
            $lines += ("  Jenkinsfile present: " + [string]([bool]$service.HasJenkinsfile))
            $lines += ("  Required files: " + (@($service.RequiredFiles) -join ", "))
            $lines += ("  Notes: " + $service.Notes)
            $lines += ""
        }

        $document = $lines -join [Environment]::NewLine
    }
}

if ($PSBoundParameters.ContainsKey("OutputPath") -and $OutputPath) {
    $resolvedOutputPath = [System.IO.Path]::GetFullPath($OutputPath)
    $outputDirectory = Split-Path -Path $resolvedOutputPath -Parent
    if ($outputDirectory) {
        New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
    }

    Set-Content -Path $resolvedOutputPath -Value $document -NoNewline
    Write-Host ("Wrote service pipeline plan to {0}" -f $resolvedOutputPath)
}
else {
    Write-Output $document
}
