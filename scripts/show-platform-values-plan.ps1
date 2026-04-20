param(
    [string]$RepoRoot,
    [string]$Profile = "full",
    [string[]]$Applications = @(),
    [string[]]$DataServices = @(),
    [switch]$IncludeJenkins,
    [string]$ValuesFile,
    [ValidateSet("text", "markdown", "json", "env")]
    [string]$Format = "text",
    [string]$OutputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "platform-values-catalog.ps1")

function Get-TextList {
    param(
        [object[]]$Values
    )

    if (@($Values).Count -gt 0) {
        return (@($Values) -join ", ")
    }

    return "none"
}

function Get-CategoryHeading {
    param(
        [string]$Category
    )

    $parts = @($Category -split "-")
    return (@($parts | Where-Object { $_ } | ForEach-Object {
        if ($_.Length -gt 1) {
            $_.Substring(0, 1).ToUpperInvariant() + $_.Substring(1)
        }
        else {
            $_.ToUpperInvariant()
        }
    }) -join " ")
}

if (-not $PSBoundParameters.ContainsKey("RepoRoot") -or -not $RepoRoot) {
    $RepoRoot = Join-Path $PSScriptRoot ".."
}

if (-not $PSBoundParameters.ContainsKey("ValuesFile") -or -not $ValuesFile) {
    $ValuesFile = Join-Path $PSScriptRoot "..\config\platform-values.env.example"
}

$planData = Get-PlatformValuePlanData `
    -RepoRoot $RepoRoot `
    -Profile $Profile `
    -Applications $Applications `
    -DataServices $DataServices `
    -IncludeJenkins:$IncludeJenkins `
    -ValuesFile $ValuesFile

$entries = @($planData.Entries)
$sensitiveEntries = @($entries | Where-Object { [bool]$_.Sensitive })
$nonSensitiveEntries = @($entries | Where-Object { -not [bool]$_.Sensitive })
$applicationsText = Get-TextList -Values $planData.Selection.Applications
$explicitDataServicesText = Get-TextList -Values $planData.Selection.DataServices
$effectiveDataServicesText = Get-TextList -Values $planData.EffectiveDataServices
$selectedServicesText = Get-TextList -Values $planData.ServiceDirectories
$selectedK8sText = Get-TextList -Values $planData.K8sDirectories

switch ($Format) {
    "json" {
        $document = ([ordered]@{
            Profile = $planData.Selection.Profile
            Description = $planData.Selection.Description
            Applications = @($planData.Selection.Applications)
            ExplicitDataServices = @($planData.Selection.DataServices)
            EffectiveDataServices = @($planData.EffectiveDataServices)
            IncludeJenkins = [bool]$IncludeJenkins
            ValuesFile = $planData.ValuesFilePath
            K8sDirectories = @($planData.K8sDirectories)
            ServiceDirectories = @($planData.ServiceDirectories)
            MissingCatalogKeys = @($planData.MissingCatalogKeys)
            MissingValuesFileKeys = @($planData.MissingValuesFileKeys)
            Entries = @($entries | Select-Object Name, Category, Sensitive, Description, PresentInValuesFile, SourcePaths, K8sDirectories, ServiceNames)
        } | ConvertTo-Json -Depth 10)
    }
    "env" {
        $lines = @(
            "# Platform values for the selected deployment bundle",
            ("# Profile: " + $planData.Selection.Profile),
            ("# Applications: " + $applicationsText),
            ("# Explicit data services: " + $explicitDataServicesText),
            ("# Effective in-cluster data services: " + $effectiveDataServicesText),
            ("# Selected services: " + $selectedServicesText),
            "# Sensitive keys should be replaced with real secrets before deployment."
        )

        $categoryGroups = @($entries | Group-Object Category | Sort-Object Name)
        foreach ($group in $categoryGroups) {
            $lines += ""
            $lines += ("# " + (Get-CategoryHeading -Category $group.Name))

            foreach ($entry in @($group.Group | Sort-Object Name)) {
                $sensitiveText = if ([bool]$entry.Sensitive) { "sensitive" } else { "non-sensitive" }
                $lines += ("# " + $entry.Name + " [" + $sensitiveText + "]: " + $entry.Description)
                $lines += ("# Used by: " + (Get-TextList -Values $entry.SourcePaths))
                $lines += ($entry.Name + "=" + $entry.ExampleValue)
            }
        }

        if ($entries.Count -eq 0) {
            $lines += ""
            $lines += "# No platform values are required because no templated components were selected."
        }

        $document = $lines -join [Environment]::NewLine
    }
    "markdown" {
        $lines = @(
            "# Platform Values Plan",
            "",
            "## Summary",
            "",
            ("- Profile: " + $planData.Selection.Profile),
            ("- Description: " + $planData.Selection.Description),
            ("- Applications: " + $applicationsText),
            ("- Explicit data services: " + $explicitDataServicesText),
            ("- Effective in-cluster data services: " + $effectiveDataServicesText),
            ("- Kubernetes directories: " + $selectedK8sText),
            ("- Service directories: " + $selectedServicesText),
            ("- Required values: " + [string]$entries.Count),
            ("- Sensitive values: " + [string]$sensitiveEntries.Count),
            ("- Non-sensitive values: " + [string]$nonSensitiveEntries.Count),
            ("- Values file checked: " + $planData.ValuesFilePath),
            ("- Missing catalog keys: " + (Get-TextList -Values $planData.MissingCatalogKeys)),
            ("- Missing values file keys: " + (Get-TextList -Values $planData.MissingValuesFileKeys)),
            ""
        )

        if ($entries.Count -gt 0) {
            $lines += "## Required Values By Category"
            $lines += ""
            foreach ($group in @($entries | Group-Object Category | Sort-Object Name)) {
                $lines += ("### " + (Get-CategoryHeading -Category $group.Name))
                $lines += ""
                foreach ($entry in @($group.Group | Sort-Object Name)) {
                    $sensitiveText = if ([bool]$entry.Sensitive) { "yes" } else { "no" }
                    $lines += ("- " + $entry.Name + ": " + $entry.Description)
                    $lines += ("  Sensitive: " + $sensitiveText)
                    $lines += ("  Present in values file: " + [string]([bool]$entry.PresentInValuesFile))
                    $lines += ("  Used by: " + (Get-TextList -Values $entry.SourcePaths))
                }
                $lines += ""
            }
        }

        $document = $lines -join [Environment]::NewLine
    }
    default {
        $lines = @(
            "Platform Values Plan",
            "====================",
            ("Profile: " + $planData.Selection.Profile),
            ("Description: " + $planData.Selection.Description),
            ("Applications: " + $applicationsText),
            ("Explicit data services: " + $explicitDataServicesText),
            ("Effective in-cluster data services: " + $effectiveDataServicesText),
            ("Kubernetes directories: " + $selectedK8sText),
            ("Service directories: " + $selectedServicesText),
            ("Required values: " + [string]$entries.Count),
            ("Sensitive values: " + [string]$sensitiveEntries.Count),
            ("Values file checked: " + $planData.ValuesFilePath),
            ("Missing catalog keys: " + (Get-TextList -Values $planData.MissingCatalogKeys)),
            ("Missing values file keys: " + (Get-TextList -Values $planData.MissingValuesFileKeys)),
            ""
        )

        foreach ($group in @($entries | Group-Object Category | Sort-Object Name)) {
            $lines += (Get-CategoryHeading -Category $group.Name)
            foreach ($entry in @($group.Group | Sort-Object Name)) {
                $sensitiveText = if ([bool]$entry.Sensitive) { "yes" } else { "no" }
                $lines += ("- " + $entry.Name + ": " + $entry.Description)
                $lines += ("  Sensitive: " + $sensitiveText)
                $lines += ("  Present in values file: " + [string]([bool]$entry.PresentInValuesFile))
                $lines += ("  Used by: " + (Get-TextList -Values $entry.SourcePaths))
            }
            $lines += ""
        }

        if ($entries.Count -eq 0) {
            $lines += "No platform values are required because no templated components were selected."
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
    Write-Host ("Wrote platform values plan to {0}" -f $resolvedOutputPath)
}
else {
    Write-Output $document
}
