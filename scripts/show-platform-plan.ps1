param(
    [string]$RepoRoot,
    [string]$HelmConfigFile,
    [string]$Profile = "full",
    [string[]]$Applications = @(),
    [string[]]$DataServices = @(),
    [switch]$IncludeJenkins,
    [ValidateSet("text", "markdown", "mermaid", "json")]
    [string]$Format = "text",
    [string]$OutputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "platform-catalog.ps1")

function Get-PlanDocument {
    param(
        [pscustomobject]$Selection,
        [object[]]$AllComponents,
        [object[]]$RawPhases,
        [object[]]$HelmReleases,
        [object[]]$OptionalManifests,
        [string]$Format,
        [bool]$IncludeJenkins
    )

    $applicationsText = if ($Selection.Applications.Count -gt 0) {
        $Selection.Applications -join ", "
    }
    else {
        "none selected"
    }

    $dataServicesText = if ($Selection.DataServices.Count -gt 0) {
        $Selection.DataServices -join ", "
    }
    else {
        "none selected"
    }

    $includeJenkinsText = [string]$IncludeJenkins

    switch ($Format) {
        "json" {
            return ([ordered]@{
                Profile = $Selection.Profile
                Description = $Selection.Description
                Applications = @($Selection.Applications)
                DataServices = @($Selection.DataServices)
                IncludeJenkins = [bool]$IncludeJenkins
                K8sDirectories = @($Selection.K8sDirectories)
                ServiceDirectories = @($Selection.ServiceDirectories)
                Components = @($AllComponents)
                RawPhases = @($RawPhases)
                HelmReleases = @($HelmReleases)
                OptionalManifests = @($OptionalManifests)
            } | ConvertTo-Json -Depth 10)
        }
        "markdown" {
            $lines = @(
                "# Platform Plan",
                "",
                "## Summary",
                "",
                ("- Profile: " + $Selection.Profile),
                ("- Description: " + $Selection.Description),
                ("- Applications: " + $applicationsText),
                ("- Data services: " + $dataServicesText),
                ("- Include Jenkins: " + $includeJenkinsText),
                ""
            )

            if ($AllComponents.Count -gt 0) {
                $lines += "## Kubernetes Components"
                $lines += ""
                foreach ($component in $AllComponents) {
                    $description = if ($component.Description) { $component.Description } else { "No catalog description available." }
                    $delivery = if ($component.Delivery) { $component.Delivery } else { "uncatalogued" }
                    $lines += ("- " + $component.Directory + ": " + $description + " (" + $delivery + ")")
                }
                $lines += ""
            }

            if ($RawPhases.Count -gt 0) {
                $lines += "## Raw Manifest Phases"
                $lines += ""
                foreach ($phase in $RawPhases) {
                    $lines += ("### " + $phase.Name)
                    $lines += ""
                    foreach ($component in @($phase.Components)) {
                        $lines += ("- " + $component.Directory + ": " + $component.Description)
                    }
                    $lines += ""
                }
            }

            if ($HelmReleases.Count -gt 0) {
                $lines += "## Helm Components"
                $lines += ""
                foreach ($release in $HelmReleases) {
                    $chart = if ($release.Chart) { $release.Chart } else { "not configured" }
                    $lines += ("- " + $release.Name + ": " + $chart + " in namespace " + $release.Namespace)
                }
                $lines += ""
            }

            if ($Selection.ServiceDirectories.Count -gt 0) {
                $lines += "## Service Configurations"
                $lines += ""
                foreach ($directory in $Selection.ServiceDirectories) {
                    $lines += ("- " + $directory)
                }
                $lines += ""
            }

            if ($OptionalManifests.Count -gt 0) {
                $lines += "## Optional Follow-up Manifests"
                $lines += ""
                foreach ($item in $OptionalManifests) {
                    $lines += ("- " + $item.RelativePath + ": " + $item.Notes)
                }
                $lines += ""
            }

            return ($lines -join [Environment]::NewLine)
        }
        "mermaid" {
            function Get-MermaidLabel {
                param([string]$Value)

                if (-not $Value) {
                    return ""
                }

                return ($Value.Replace('"', "'"))
            }

            $lines = @("flowchart TD")
            $rootId = "plan"
            $summaryId = "summary"
            $servicesId = "services"
            $helmId = "helm"
            $optionalId = "optional"
            $counter = 0

            $lines += ('    ' + $rootId + '["Profile: ' + (Get-MermaidLabel -Value $Selection.Profile) + '"]')
            $lines += ('    ' + $summaryId + '["Applications: ' + (Get-MermaidLabel -Value $applicationsText) + '<br/>Data services: ' + (Get-MermaidLabel -Value $dataServicesText) + '"]')
            $lines += ('    ' + $rootId + ' --> ' + $summaryId)

            foreach ($phase in $RawPhases) {
                $counter += 1
                $phaseId = "phase" + $counter
                $lines += ('    ' + $phaseId + '["' + (Get-MermaidLabel -Value $phase.Name) + '"]')
                $lines += ('    ' + $rootId + ' --> ' + $phaseId)

                foreach ($component in @($phase.Components)) {
                    $counter += 1
                    $componentId = "node" + $counter
                    $lines += ('    ' + $componentId + '["' + (Get-MermaidLabel -Value $component.Directory) + '"]')
                    $lines += ('    ' + $phaseId + ' --> ' + $componentId)
                }
            }

            if ($HelmReleases.Count -gt 0) {
                $lines += ('    ' + $helmId + '["Helm Components"]')
                $lines += ('    ' + $rootId + ' --> ' + $helmId)
                foreach ($release in $HelmReleases) {
                    $counter += 1
                    $releaseId = "node" + $counter
                    $lines += ('    ' + $releaseId + '["' + (Get-MermaidLabel -Value $release.Name) + '"]')
                    $lines += ('    ' + $helmId + ' --> ' + $releaseId)
                }
            }

            if ($Selection.ServiceDirectories.Count -gt 0) {
                $lines += ('    ' + $servicesId + '["Service Configurations"]')
                $lines += ('    ' + $rootId + ' --> ' + $servicesId)
                foreach ($directory in $Selection.ServiceDirectories) {
                    $counter += 1
                    $serviceId = "node" + $counter
                    $lines += ('    ' + $serviceId + '["' + (Get-MermaidLabel -Value $directory) + '"]')
                    $lines += ('    ' + $servicesId + ' --> ' + $serviceId)
                }
            }

            if ($OptionalManifests.Count -gt 0) {
                $lines += ('    ' + $optionalId + '["Optional Follow-up"]')
                $lines += ('    ' + $rootId + ' --> ' + $optionalId)
                foreach ($item in $OptionalManifests) {
                    $counter += 1
                    $optionalNodeId = "node" + $counter
                    $lines += ('    ' + $optionalNodeId + '["' + (Get-MermaidLabel -Value $item.RelativePath) + '"]')
                    $lines += ('    ' + $optionalId + ' --> ' + $optionalNodeId)
                }
            }

            return ($lines -join [Environment]::NewLine)
        }
        default {
            $lines = @(
                "Platform Plan",
                "=============",
                ("Profile: " + $Selection.Profile),
                ("Description: " + $Selection.Description),
                ("Applications: " + $applicationsText),
                ("Data services: " + $dataServicesText),
                ("Include Jenkins: " + $includeJenkinsText),
                ""
            )

            if ($AllComponents.Count -gt 0) {
                $lines += "Kubernetes components"
                $lines += "---------------------"
                foreach ($component in $AllComponents) {
                    $description = if ($component.Description) { $component.Description } else { "No catalog description available." }
                    $delivery = if ($component.Delivery) { $component.Delivery } else { "uncatalogued" }
                    $lines += ("- " + $component.Directory + " [" + $delivery + "]: " + $description)
                }
                $lines += ""
            }

            if ($RawPhases.Count -gt 0) {
                $lines += "Raw manifest phases"
                $lines += "-------------------"
                foreach ($phase in $RawPhases) {
                    $lines += ("* " + $phase.Name)
                    foreach ($component in @($phase.Components)) {
                        $lines += ("  - " + $component.Directory + ": " + $component.Description)
                    }
                }
                $lines += ""
            }

            if ($HelmReleases.Count -gt 0) {
                $lines += "Helm components"
                $lines += "---------------"
                foreach ($release in $HelmReleases) {
                    $chart = if ($release.Chart) { $release.Chart } else { "not configured" }
                    $lines += ("- " + $release.Name + ": " + $chart + " in namespace " + $release.Namespace)
                }
                $lines += ""
            }

            if ($Selection.ServiceDirectories.Count -gt 0) {
                $lines += "Service configurations"
                $lines += "----------------------"
                foreach ($directory in $Selection.ServiceDirectories) {
                    $lines += ("- " + $directory)
                }
                $lines += ""
            }

            if ($OptionalManifests.Count -gt 0) {
                $lines += "Optional follow-up manifests"
                $lines += "----------------------------"
                foreach ($item in $OptionalManifests) {
                    $lines += ("- " + $item.RelativePath + ": " + $item.Notes)
                }
                $lines += ""
            }

            return ($lines -join [Environment]::NewLine)
        }
    }
}

if (-not $PSBoundParameters.ContainsKey("RepoRoot") -or -not $RepoRoot) {
    $RepoRoot = Join-Path $PSScriptRoot ".."
}

if (-not $PSBoundParameters.ContainsKey("HelmConfigFile") -or -not $HelmConfigFile) {
    $HelmConfigFile = Join-Path $PSScriptRoot "..\config\helm-releases.psd1"
}

$root = (Resolve-Path -Path $RepoRoot).Path
$resolvedHelmConfig = (Resolve-Path -Path $HelmConfigFile).Path
$selection = Resolve-PlatformSelection -Profile $Profile -Applications $Applications -DataServices $DataServices -IncludeJenkins:$IncludeJenkins
$componentCatalog = Get-PlatformK8sComponentCatalog
$optionalManifestCatalog = Get-PlatformOptionalManifestCatalog
$helmConfig = Import-PowerShellDataFile -Path $resolvedHelmConfig

$allComponents = @()
$phaseMap = [ordered]@{}
$phaseOrder = @("phase-a", "phase-b", "phase-c", "phase-d", "phase-e")

foreach ($directory in $selection.K8sDirectories) {
    if ($componentCatalog.Contains($directory)) {
        $component = $componentCatalog[$directory]
        $allComponents += [PSCustomObject]@{
            Directory = $directory
            Delivery = $component.Delivery
            PhaseId = $component.PhaseId
            PhaseName = $component.PhaseName
            Description = $component.Description
            Notes = $component.Notes
        }

        if ($component.Delivery -ne "helm") {
            if (-not $phaseMap.Contains($component.PhaseId)) {
                $phaseMap[$component.PhaseId] = [ordered]@{
                    Id = $component.PhaseId
                    Name = $component.PhaseName
                    Components = @()
                }
            }

            $phaseMap[$component.PhaseId].Components += [PSCustomObject]@{
                Directory = $directory
                Description = $component.Description
                Delivery = $component.Delivery
                Notes = $component.Notes
            }
        }
    }
    else {
        $allComponents += [PSCustomObject]@{
            Directory = $directory
            Delivery = ""
            PhaseId = ""
            PhaseName = ""
            Description = ""
            Notes = "This directory is not catalogued yet."
        }
    }
}

$rawPhases = @()
$orderedPhaseIds = @($phaseOrder + @($phaseMap.Keys | Where-Object { $_ -notin $phaseOrder }))
foreach ($phaseId in $orderedPhaseIds) {
    if (-not $phaseMap.Contains($phaseId)) {
        continue
    }

    $phase = $phaseMap[$phaseId]
    $rawPhases += [PSCustomObject]@{
        Id = $phase.Id
        Name = $phase.Name
        Components = @($phase.Components)
    }
}

$helmReleases = @()
foreach ($release in @($helmConfig.Releases)) {
    if ($selection.K8sDirectories -contains $release.K8sDirectory) {
        $releaseNotes = if ($release.ContainsKey("Notes")) { $release.Notes } else { "" }
        $helmReleases += [PSCustomObject]@{
            Name = $release.Name
            Namespace = $release.Namespace
            Chart = $release.Chart
            RepoName = $release.RepoName
            RepoUrl = $release.RepoUrl
            K8sDirectory = $release.K8sDirectory
            Enabled = [bool]$release.Enabled
            Notes = $releaseNotes
        }
    }
}

$optionalManifests = @()
foreach ($relativePath in $optionalManifestCatalog.Keys) {
    $directoryName = ($relativePath -split "[\\/]", 2)[0]
    if ($selection.K8sDirectories -contains $directoryName) {
        $optionalManifests += [PSCustomObject]@{
            RelativePath = ("k8s\" + $relativePath)
            Notes = $optionalManifestCatalog[$relativePath]
        }
    }
}

$document = Get-PlanDocument `
    -Selection $selection `
    -AllComponents $allComponents `
    -RawPhases $rawPhases `
    -HelmReleases $helmReleases `
    -OptionalManifests $optionalManifests `
    -Format $Format `
    -IncludeJenkins ([bool]$IncludeJenkins)

if ($PSBoundParameters.ContainsKey("OutputPath") -and $OutputPath) {
    $resolvedOutputPath = [System.IO.Path]::GetFullPath($OutputPath)
    $outputDirectory = Split-Path -Path $resolvedOutputPath -Parent
    if ($outputDirectory) {
        New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
    }

    Set-Content -Path $resolvedOutputPath -Value $document -NoNewline
    Write-Host ("Wrote platform plan to {0}" -f $resolvedOutputPath)
}
else {
    Write-Output $document
}
