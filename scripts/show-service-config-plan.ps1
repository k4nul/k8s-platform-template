param(
    [string]$RepoRoot,
    [string[]]$ServiceNames = @(),
    [ValidateSet("text", "markdown", "json")]
    [string]$Format = "text",
    [string]$OutputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Expand-RequestedServiceNames {
    param(
        [string[]]$Values
    )

    $expandedValues = New-Object System.Collections.Generic.List[string]
    foreach ($value in @($Values)) {
        if (-not $value) {
            continue
        }

        foreach ($item in ($value -split ",")) {
            $trimmedItem = $item.Trim()
            if ($trimmedItem) {
                $expandedValues.Add($trimmedItem) | Out-Null
            }
        }
    }

    return @($expandedValues | Sort-Object -Unique)
}

function Get-ServiceNamesText {
    param(
        [object[]]$Services
    )

    if (@($Services).Count -gt 0) {
        return (@($Services | ForEach-Object { $_.Name }) -join ", ")
    }

    return "none selected"
}

if (-not $PSBoundParameters.ContainsKey("RepoRoot") -or -not $RepoRoot) {
    $RepoRoot = Join-Path $PSScriptRoot ".."
}

$root = (Resolve-Path -Path $RepoRoot).Path
$catalogPath = Join-Path $root "config\service-config-artifacts.psd1"
$catalog = Import-PowerShellDataFile -Path $catalogPath
$allServices = @($catalog.Services | Sort-Object { $_.Name })
$availableServiceNames = @($allServices | ForEach-Object { $_.Name })

$selectedServices = @()
if ($PSBoundParameters.ContainsKey("ServiceNames")) {
    $requestedServiceNames = Expand-RequestedServiceNames -Values $ServiceNames
    $unknownServices = @($requestedServiceNames | Where-Object { $availableServiceNames -notcontains $_ })
    if ($unknownServices.Count -gt 0) {
        throw "Unknown service config selection: $($unknownServices -join ', '). Available services: $($availableServiceNames -join ', ')"
    }

    foreach ($service in $allServices) {
        if ($requestedServiceNames -contains $service.Name) {
            $selectedServices += $service
        }
    }
}
else {
    $selectedServices = @($allServices)
}

$selectedServiceNamesText = Get-ServiceNamesText -Services $selectedServices
$artifactCount = 0
foreach ($service in $selectedServices) {
    $artifactCount += @($service.ConfigArtifacts).Count
}

switch ($Format) {
    "json" {
        $document = ([ordered]@{
            SelectedServices = @($selectedServices | ForEach-Object { $_.Name })
            Services = @($selectedServices)
        } | ConvertTo-Json -Depth 10)
    }
    "markdown" {
        $lines = @(
            "# Service Config Plan",
            "",
            "## Summary",
            "",
            ("- Selected services: " + $selectedServiceNamesText),
            ("- Repository-managed config artifacts: " + [string]$artifactCount),
            ""
        )

        if ($selectedServices.Count -gt 0) {
            $lines += "## Service Config Details"
            $lines += ""
            foreach ($service in $selectedServices) {
                $artifactEntries = @($service.ConfigArtifacts)
                $lines += ("### " + $service.Name)
                $lines += ""
                $lines += ("- Notes: " + $service.Notes)
                if ($artifactEntries.Count -eq 0) {
                    $lines += "- Config artifacts: none"
                    $lines += ""
                    continue
                }

                $lines += ("- Config artifacts: " + [string]$artifactEntries.Count)
                foreach ($artifact in $artifactEntries) {
                    $placeholdersText = if (@($artifact.PlaceholderTokens).Count -gt 0) { @($artifact.PlaceholderTokens) -join ", " } else { "none" }
                    $lines += ("- " + $artifact.SourceFile + " [" + $artifact.Mode + ", " + $artifact.Format + "] -> " + $artifact.RenderedFileName)
                    $lines += ("  Placeholders: " + $placeholdersText)
                    $lines += ("  Notes: " + $artifact.Notes)
                }
                $lines += ""
            }
        }

        $document = $lines -join [Environment]::NewLine
    }
    default {
        $lines = @(
            "Service Config Plan",
            "===================",
            ("Selected services: " + $selectedServiceNamesText),
            ("Repository-managed config artifacts: " + [string]$artifactCount),
            ""
        )

        foreach ($service in $selectedServices) {
            $artifactEntries = @($service.ConfigArtifacts)
            $lines += ($service.Name)
            $lines += ("  Notes: " + $service.Notes)
            if ($artifactEntries.Count -eq 0) {
                $lines += "  Config artifacts: none"
                $lines += ""
                continue
            }

            foreach ($artifact in $artifactEntries) {
                $placeholdersText = if (@($artifact.PlaceholderTokens).Count -gt 0) { @($artifact.PlaceholderTokens) -join ", " } else { "none" }
                $lines += ("  - " + $artifact.SourceFile + " [" + $artifact.Mode + ", " + $artifact.Format + "] -> " + $artifact.RenderedFileName)
                $lines += ("    Placeholders: " + $placeholdersText)
                $lines += ("    Notes: " + $artifact.Notes)
            }
            $lines += ""
        }

        if ($selectedServices.Count -eq 0) {
            $lines += "No services selected."
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
    Write-Host ("Wrote service config plan to {0}" -f $resolvedOutputPath)
}
else {
    Write-Output $document
}
