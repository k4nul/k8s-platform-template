param(
    [string]$RepoRoot,
    [string]$HelmConfigFile,
    [ValidateSet("text", "markdown", "json")]
    [string]$Format = "text",
    [string]$OutputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "platform-catalog.ps1")

function Get-ProfileMetadataArray {
    param(
        [System.Collections.IDictionary]$Definition,
        [string]$Key
    )

    if (-not $Definition.Contains($Key)) {
        return @()
    }

    return @(
        @($Definition[$Key]) |
            ForEach-Object { [string]$_ } |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ } |
            Sort-Object -Unique
    )
}

function Get-ProfileMetadataString {
    param(
        [System.Collections.IDictionary]$Definition,
        [string]$Key,
        [string]$Default = ""
    )

    if (-not $Definition.Contains($Key)) {
        return $Default
    }

    return ([string]$Definition[$Key]).Trim()
}

function Get-TextList {
    param(
        [object[]]$Values,
        [string]$Empty = "none"
    )

    if (@($Values).Count -gt 0) {
        return (@($Values) -join ", ")
    }

    return $Empty
}

function Get-EffectiveK8sDirectories {
    param(
        [string]$Root,
        [pscustomobject]$Selection
    )

    if ($Selection.IncludeAllK8s) {
        return @(
            Get-ChildItem -Path (Join-Path $Root "k8s") -Directory |
                Sort-Object Name |
                Select-Object -ExpandProperty Name
        )
    }

    return @($Selection.K8sDirectories | Sort-Object -Unique)
}

function Get-EffectiveServiceDirectories {
    param(
        [string]$Root,
        [pscustomobject]$Selection
    )

    if ($Selection.IncludeAllServices) {
        return @(
            Get-ChildItem -Path (Join-Path $Root "services") -Directory |
                Sort-Object Name |
                Select-Object -ExpandProperty Name
        )
    }

    return @($Selection.ServiceDirectories | Sort-Object -Unique)
}

function Get-OrderedProfileNames {
    param(
        [System.Collections.IDictionary]$Profiles
    )

    $preferredOrder = @(
        "minimal-application",
        "developer-sandbox",
        "data-services",
        "reverse-proxy-platform",
        "web-platform",
        "shared-services",
        "full"
    )

    $orderedNames = New-Object System.Collections.Generic.List[string]

    foreach ($profileName in $preferredOrder) {
        if ($Profiles.Contains($profileName)) {
            $orderedNames.Add($profileName) | Out-Null
        }
    }

    foreach ($profileName in @($Profiles.Keys | Where-Object { $_ -notin $preferredOrder } | Sort-Object)) {
        $orderedNames.Add($profileName) | Out-Null
    }

    return @($orderedNames)
}

function Get-ScopeText {
    param(
        [bool]$IncludesAll,
        [int]$Count
    )

    if ($IncludesAll) {
        return ("all ({0})" -f $Count)
    }

    return [string]$Count
}

function Get-PreviewCommand {
    param(
        [string]$ProfileName,
        [string[]]$ExampleApplications,
        [string[]]$ExampleDataServices
    )

    $parts = New-Object System.Collections.Generic.List[string]
    $parts.Add(".\scripts\show-platform-plan.ps1") | Out-Null
    $parts.Add("-Profile") | Out-Null
    $parts.Add($ProfileName) | Out-Null

    if (@($ExampleApplications).Count -gt 0) {
        $parts.Add("-Applications") | Out-Null
        $parts.Add(($ExampleApplications -join ",")) | Out-Null
    }

    if (@($ExampleDataServices).Count -gt 0) {
        $parts.Add("-DataServices") | Out-Null
        $parts.Add(($ExampleDataServices -join ",")) | Out-Null
    }

    $parts.Add("-Format") | Out-Null
    $parts.Add("markdown") | Out-Null

    return ($parts -join " ")
}

if (-not $PSBoundParameters.ContainsKey("RepoRoot") -or -not $RepoRoot) {
    $RepoRoot = Join-Path $PSScriptRoot ".."
}

if (-not $PSBoundParameters.ContainsKey("HelmConfigFile") -or -not $HelmConfigFile) {
    $HelmConfigFile = Join-Path $PSScriptRoot "..\config\helm-releases.psd1"
}

$root = (Resolve-Path -Path $RepoRoot).Path
$resolvedHelmConfig = (Resolve-Path -Path $HelmConfigFile).Path
$profiles = Get-PlatformProfileDefinitions
$componentCatalog = Get-PlatformK8sComponentCatalog
$applicationCatalog = Get-PlatformApplicationCatalog
$dataServiceCatalog = Get-PlatformDataServiceCatalog
$helmConfig = Import-PowerShellDataFile -Path $resolvedHelmConfig
$helmReleaseMap = [ordered]@{}

foreach ($release in @($helmConfig.Releases)) {
    $helmReleaseMap[$release.K8sDirectory] = $release
}

$profileCatalog = @()

foreach ($profileName in (Get-OrderedProfileNames -Profiles $profiles)) {
    $definition = $profiles[$profileName]
    $selection = Resolve-PlatformSelection -Profile $profileName
    $effectiveK8sDirectories = @(Get-EffectiveK8sDirectories -Root $root -Selection $selection)
    $effectiveServiceDirectories = @(Get-EffectiveServiceDirectories -Root $root -Selection $selection)
    $recommendedFor = @(Get-ProfileMetadataArray -Definition $definition -Key "RecommendedFor")
    $avoidWhen = @(Get-ProfileMetadataArray -Definition $definition -Key "AvoidWhen")
    $exampleApplications = @(Get-ProfileMetadataArray -Definition $definition -Key "ExampleApplications")
    $exampleDataServices = @(Get-ProfileMetadataArray -Definition $definition -Key "ExampleDataServices")

    foreach ($applicationName in $exampleApplications) {
        if (-not $applicationCatalog.Contains($applicationName)) {
            throw "Profile '$profileName' references an unknown example application: $applicationName"
        }
    }

    foreach ($dataServiceName in $exampleDataServices) {
        if (-not $dataServiceCatalog.Contains($dataServiceName)) {
            throw "Profile '$profileName' references an unknown example data service: $dataServiceName"
        }
    }

    $components = @()
    foreach ($directory in $effectiveK8sDirectories) {
        $componentEntry = if ($componentCatalog.Contains($directory)) { $componentCatalog[$directory] } else { $null }
        $helmRelease = if ($helmReleaseMap.Contains($directory)) { $helmReleaseMap[$directory] } else { $null }

        $components += [PSCustomObject]@{
            Directory = $directory
            Delivery = if ($null -ne $componentEntry) { $componentEntry.Delivery } else { "uncatalogued" }
            PhaseId = if ($null -ne $componentEntry) { $componentEntry.PhaseId } else { "" }
            PhaseName = if ($null -ne $componentEntry) { $componentEntry.PhaseName } else { "" }
            Description = if ($null -ne $componentEntry) { $componentEntry.Description } else { "No component catalog description is defined for this directory yet." }
            Notes = if ($null -ne $componentEntry) { $componentEntry.Notes } else { "" }
            HelmReleaseName = if ($null -ne $helmRelease) { $helmRelease.Name } else { "" }
            HelmChart = if ($null -ne $helmRelease) { $helmRelease.Chart } else { "" }
            HelmEnabled = if ($null -ne $helmRelease) { [bool]$helmRelease.Enabled } else { $false }
        }
    }

    $profileCatalog += [PSCustomObject]@{
        Name = $profileName
        Description = $selection.Description
        PrimaryUse = Get-ProfileMetadataString -Definition $definition -Key "PrimaryUse" -Default $selection.Description
        RecommendedFor = @($recommendedFor)
        AvoidWhen = @($avoidWhen)
        ExampleApplications = @($exampleApplications)
        ExampleDataServices = @($exampleDataServices)
        IncludeAllK8s = [bool]$selection.IncludeAllK8s
        IncludeAllServices = [bool]$selection.IncludeAllServices
        K8sDirectories = @($effectiveK8sDirectories)
        ServiceDirectories = @($effectiveServiceDirectories)
        K8sDirectoryCount = $effectiveK8sDirectories.Count
        ServiceDirectoryCount = $effectiveServiceDirectories.Count
        RawComponentCount = @($components | Where-Object { $_.Delivery -ne "helm" }).Count
        HelmComponentCount = @($components | Where-Object { $_.Delivery -eq "helm" }).Count
        PhaseNames = @($components | Where-Object { $_.PhaseName } | Select-Object -ExpandProperty PhaseName -Unique)
        Components = @($components)
        PreviewCommand = Get-PreviewCommand -ProfileName $profileName -ExampleApplications $exampleApplications -ExampleDataServices $exampleDataServices
    }
}

switch ($Format) {
    "json" {
        $document = ([ordered]@{
            GeneratedAt = (Get-Date).ToString("s")
            RepoRoot = $root
            Profiles = @($profileCatalog)
        } | ConvertTo-Json -Depth 10)
    }
    "markdown" {
        $lines = @(
            "# Profile Catalog",
            "",
            "## Recommendation Matrix",
            "",
            "| Profile | Primary Use | Kubernetes Dirs | Helm Dirs | Example Apps | Example Data Services |",
            "| --- | --- | --- | --- | --- | --- |"
        )

        foreach ($profile in $profileCatalog) {
            $lines += ("| {0} | {1} | {2} | {3} | {4} | {5} |" -f `
                $profile.Name, `
                $profile.PrimaryUse, `
                (Get-ScopeText -IncludesAll ([bool]$profile.IncludeAllK8s) -Count $profile.K8sDirectoryCount), `
                [string]$profile.HelmComponentCount, `
                (Get-TextList -Values $profile.ExampleApplications), `
                (Get-TextList -Values $profile.ExampleDataServices))
        }

        $lines += ""
        $lines += "## Profiles"
        $lines += ""

        foreach ($profile in $profileCatalog) {
            $lines += ("### " + $profile.Name)
            $lines += ""
            $lines += ("- Description: " + $profile.Description)
            $lines += ("- Primary use: " + $profile.PrimaryUse)
            $lines += ("- Recommended for: " + (Get-TextList -Values $profile.RecommendedFor))
            $lines += ("- Avoid when: " + (Get-TextList -Values $profile.AvoidWhen))
            $lines += ("- Kubernetes directories: " + (Get-TextList -Values $profile.K8sDirectories))
            $lines += ("- Service directories: " + (Get-TextList -Values $profile.ServiceDirectories))
            $lines += ("- Phase coverage: " + (Get-TextList -Values $profile.PhaseNames))
            $lines += ("- Example applications: " + (Get-TextList -Values $profile.ExampleApplications))
            $lines += ("- Example data services: " + (Get-TextList -Values $profile.ExampleDataServices))
            $lines += ('- Preview command: `{0}`' -f $profile.PreviewCommand)
            $lines += ""
            $lines += "Included components:"
            $lines += ""

            foreach ($component in @($profile.Components | Sort-Object Directory)) {
                $componentSuffix = if ($component.Delivery -eq "helm" -and $component.HelmChart) {
                    " (helm: {0})" -f $component.HelmChart
                }
                elseif ($component.Delivery) {
                    " ({0})" -f $component.Delivery
                }
                else {
                    ""
                }

                $lines += ('- `{0}`: {1}{2}' -f $component.Directory, $component.Description, $componentSuffix)
            }

            $lines += ""
        }

        $document = $lines -join [Environment]::NewLine
    }
    default {
        $lines = @(
            "Profile Catalog",
            "===============",
            ""
        )

        foreach ($profile in $profileCatalog) {
            $lines += ("Profile: " + $profile.Name)
            $lines += ("Description: " + $profile.Description)
            $lines += ("Primary use: " + $profile.PrimaryUse)
            $lines += ("Recommended for: " + (Get-TextList -Values $profile.RecommendedFor))
            $lines += ("Avoid when: " + (Get-TextList -Values $profile.AvoidWhen))
            $lines += ("Kubernetes directories: " + (Get-TextList -Values $profile.K8sDirectories))
            $lines += ("Service directories: " + (Get-TextList -Values $profile.ServiceDirectories))
            $lines += ("Phase coverage: " + (Get-TextList -Values $profile.PhaseNames))
            $lines += ("Helm components: " + [string]$profile.HelmComponentCount)
            $lines += ("Example applications: " + (Get-TextList -Values $profile.ExampleApplications))
            $lines += ("Example data services: " + (Get-TextList -Values $profile.ExampleDataServices))
            $lines += ("Preview command: " + $profile.PreviewCommand)
            $lines += "Included components:"

            foreach ($component in @($profile.Components | Sort-Object Directory)) {
                $componentSuffix = if ($component.Delivery -eq "helm" -and $component.HelmChart) {
                    " (helm: {0})" -f $component.HelmChart
                }
                elseif ($component.Delivery) {
                    " ({0})" -f $component.Delivery
                }
                else {
                    ""
                }

                $lines += ("- " + $component.Directory + ": " + $component.Description + $componentSuffix)
            }

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
    Write-Host ("Wrote profile catalog to {0}" -f $resolvedOutputPath)
}
else {
    Write-Output $document
}
