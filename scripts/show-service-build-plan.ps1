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
$catalogPath = Join-Path $root "config\service-builds.psd1"
$catalog = Import-PowerShellDataFile -Path $catalogPath
$allServices = @($catalog.Services | Sort-Object { $_.Name })
$availableServiceNames = @($allServices | ForEach-Object { $_.Name })

$selectedServices = @()
if ($PSBoundParameters.ContainsKey("ServiceNames")) {
    $requestedServiceNames = Expand-RequestedServiceNames -Values $ServiceNames
    $unknownServices = @($requestedServiceNames | Where-Object { $availableServiceNames -notcontains $_ })
    if ($unknownServices.Count -gt 0) {
        throw "Unknown service build selection: $($unknownServices -join ', '). Available services: $($availableServiceNames -join ', ')"
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
$buildProfiles = @($selectedServices | Group-Object { $_.BuildProfile } | Sort-Object Name)

switch ($Format) {
    "json" {
        $document = ([ordered]@{
            SelectedServices = @($selectedServices | ForEach-Object { $_.Name })
            Services = @($selectedServices)
        } | ConvertTo-Json -Depth 10)
    }
    "markdown" {
        $lines = @(
            "# Service Build Plan",
            "",
            "## Summary",
            "",
            ("- Selected services: " + $selectedServiceNamesText),
            ("- Build profiles: " + [string]$buildProfiles.Count),
            ""
        )

        if ($buildProfiles.Count -gt 0) {
            $lines += "## Build Profiles"
            $lines += ""
            foreach ($profile in $buildProfiles) {
                $profileServices = @($profile.Group | ForEach-Object { $_.Name }) -join ", "
                $lines += ("- " + $profile.Name + ": " + $profileServices)
            }
            $lines += ""
        }

        if ($selectedServices.Count -gt 0) {
            $lines += "## Service Build Details"
            $lines += ""
            foreach ($service in $selectedServices) {
                $lines += ("### " + $service.Name)
                $lines += ""
                $lines += ("- Source type: " + $service.SourceType)
                $lines += ("- Build profile: " + $service.BuildProfile)
                $lines += ("- Public image: " + $service.PublicImage)
                $lines += ("- Notes: " + $service.Notes)
                $lines += ""
            }
        }

        $document = $lines -join [Environment]::NewLine
    }
    default {
        $lines = @(
            "Service Build Plan",
            "==================",
            ("Selected services: " + $selectedServiceNamesText),
            ""
        )

        if ($buildProfiles.Count -gt 0) {
            $lines += "Build profiles"
            foreach ($profile in $buildProfiles) {
                $profileServices = @($profile.Group | ForEach-Object { $_.Name }) -join ", "
                $lines += ("- " + $profile.Name + ": " + $profileServices)
            }
            $lines += ""
        }

        foreach ($service in $selectedServices) {
            $lines += ($service.Name + " [" + $service.BuildProfile + "]")
            $lines += ("  Source type: " + $service.SourceType)
            $lines += ("  Public image: " + $service.PublicImage)
            $lines += ("  Notes: " + $service.Notes)
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
    Write-Host ("Wrote service build plan to {0}" -f $resolvedOutputPath)
}
else {
    Write-Output $document
}
