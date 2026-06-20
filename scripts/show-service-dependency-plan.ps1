param(
    [string]$RepoRoot,
    [string]$Profile = "full",
    [string[]]$Applications = @(),
    [string[]]$DataServices = @(),
    [switch]$IncludeJenkins,
    [ValidateSet("text", "markdown", "json")]
    [string]$Format = "text",
    [string]$OutputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "platform-catalog.ps1")

function Get-ListText {
    param(
        [object[]]$Values
    )

    if (@($Values).Count -gt 0) {
        return (@($Values) -join ", ")
    }

    return "none"
}

function Get-CatalogMap {
    param(
        [object[]]$Items
    )

    $map = [ordered]@{}
    foreach ($item in @($Items | Sort-Object Name)) {
        $map[$item.Name] = $item
    }

    return $map
}

function Get-OptionalCatalogValue {
    param(
        [object]$Item,
        [string]$Name
    )

    if ($null -eq $Item) {
        return ""
    }

    if ($Item -is [System.Collections.IDictionary]) {
        if ($Item.Contains($Name) -and $Item[$Name]) {
            return [string]$Item[$Name]
        }

        return ""
    }

    $property = $Item.PSObject.Properties[$Name]
    if ($null -ne $property -and $property.Value) {
        return [string]$property.Value
    }

    return ""
}

function Get-ImageProvenanceStatus {
    param(
        [string]$BuildPublicImage,
        [string]$RuntimePublicImage
    )

    if (-not $BuildPublicImage -and -not $RuntimePublicImage) {
        return "missing"
    }

    if ($BuildPublicImage -and $RuntimePublicImage -and $BuildPublicImage -ne $RuntimePublicImage) {
        return "mismatch"
    }

    if ($BuildPublicImage -and $RuntimePublicImage) {
        return "catalog-aligned"
    }

    return "partial"
}

function Get-HelmChartSourceType {
    param(
        [object]$Release
    )

    $chart = Get-OptionalCatalogValue -Item $Release -Name "Chart"
    $repoName = Get-OptionalCatalogValue -Item $Release -Name "RepoName"
    $repoUrl = Get-OptionalCatalogValue -Item $Release -Name "RepoUrl"

    if (-not $chart) {
        return "not-configured"
    }

    if ($chart.StartsWith("oci://", [System.StringComparison]::OrdinalIgnoreCase)) {
        return "oci"
    }

    if ($repoName -and $repoUrl) {
        return "helm-repo"
    }

    return "missing-source"
}

function Get-HelmVersionPinStatus {
    param(
        [object]$Release
    )

    $chart = Get-OptionalCatalogValue -Item $Release -Name "Chart"
    $chartVersion = Get-OptionalCatalogValue -Item $Release -Name "ChartVersion"

    if (-not $chart) {
        return "not-configured"
    }

    if ($chartVersion) {
        return "pinned"
    }

    return "unpinned"
}

if (-not $PSBoundParameters.ContainsKey("RepoRoot") -or -not $RepoRoot) {
    $RepoRoot = Join-Path $PSScriptRoot ".."
}

$root = (Resolve-Path -Path $RepoRoot).Path
$selection = Resolve-PlatformSelection -Profile $Profile -Applications $Applications -DataServices $DataServices -IncludeJenkins:$IncludeJenkins
$dependencyCatalog = Import-PowerShellDataFile -Path (Join-Path $root "config\service-dependencies.psd1")
$serviceBuildCatalog = Import-PowerShellDataFile -Path (Join-Path $root "config\service-builds.psd1")
$serviceRuntimeCatalog = Import-PowerShellDataFile -Path (Join-Path $root "config\service-runtime-bindings.psd1")
$helmReleaseCatalog = Import-PowerShellDataFile -Path (Join-Path $root "config\helm-releases.psd1")
$dataServiceCatalog = Get-PlatformDataServiceCatalog

$dependencyMap = Get-CatalogMap -Items $dependencyCatalog.Services
$serviceBuildMap = Get-CatalogMap -Items $serviceBuildCatalog.Services
$serviceRuntimeMap = Get-CatalogMap -Items $serviceRuntimeCatalog.Services

$effectiveK8sDirectories = Get-EffectiveK8sDirectories -Root $root -Selection $selection
$effectiveServiceDirectories = Get-EffectiveServiceDirectories -Root $root -Selection $selection
$effectiveDataServices = Get-EffectiveDataServices -K8sDirectories $effectiveK8sDirectories -Selection $selection -DataServiceCatalog $dataServiceCatalog

$serviceRecords = @()
$statusCounts = [ordered]@{
    ready = 0
    attention = 0
    error = 0
    uncatalogued = 0
}

foreach ($serviceName in $effectiveServiceDirectories) {
    if (-not $dependencyMap.Contains($serviceName)) {
        $statusCounts.uncatalogued += 1
        $serviceRecords += [PSCustomObject]@{
            Name = $serviceName
            Status = "uncatalogued"
            Notes = "No service dependency catalog entry is defined yet."
            BuildProfile = ""
            BuildPublicImage = ""
            RuntimePublicImage = ""
            ImageProvenanceStatus = "uncatalogued"
            RequiredK8sDirectories = @()
            MissingRequiredK8sDirectories = @()
            RecommendedK8sDirectories = @()
            MissingRecommendedK8sDirectories = @()
            CompatibleDataServices = @()
            SelectedCompatibleDataServices = @()
            MissingCompatibleDataServices = @()
            RelatedApplications = @()
            SelectedRelatedApplications = @()
            MissingRelatedApplications = @()
        }
        continue
    }

    $definition = $dependencyMap[$serviceName]
    $requiredK8sDirectories = @($definition.RequiredK8sDirectories | Sort-Object -Unique)
    $recommendedK8sDirectories = @($definition.RecommendedK8sDirectories | Sort-Object -Unique)
    $compatibleDataServices = @($definition.CompatibleDataServices | Sort-Object -Unique)
    $relatedApplications = @($definition.RelatedApplications | Sort-Object -Unique)
    $buildDefinition = if ($serviceBuildMap.Contains($serviceName)) { $serviceBuildMap[$serviceName] } else { $null }
    $runtimeDefinition = if ($serviceRuntimeMap.Contains($serviceName)) { $serviceRuntimeMap[$serviceName] } else { $null }
    $buildProfile = Get-OptionalCatalogValue -Item $buildDefinition -Name "BuildProfile"
    $buildPublicImage = Get-OptionalCatalogValue -Item $buildDefinition -Name "PublicImage"
    $runtimePublicImage = Get-OptionalCatalogValue -Item $runtimeDefinition -Name "PublicImage"
    $imageProvenanceStatus = Get-ImageProvenanceStatus -BuildPublicImage $buildPublicImage -RuntimePublicImage $runtimePublicImage

    $missingRequiredK8sDirectories = @($requiredK8sDirectories | Where-Object { $effectiveK8sDirectories -notcontains $_ })
    $missingRecommendedK8sDirectories = @($recommendedK8sDirectories | Where-Object { $effectiveK8sDirectories -notcontains $_ })
    $selectedCompatibleDataServices = @($compatibleDataServices | Where-Object { $effectiveDataServices -contains $_ })
    $selectedRelatedApplications = @($relatedApplications | Where-Object { $effectiveServiceDirectories -contains $_ })

    $missingCompatibleDataServices = @()
    if ($compatibleDataServices.Count -gt 0 -and $selectedCompatibleDataServices.Count -eq 0) {
        $missingCompatibleDataServices = @($compatibleDataServices)
    }

    $missingRelatedApplications = @()
    if ($relatedApplications.Count -gt 0 -and $selectedRelatedApplications.Count -eq 0) {
        $missingRelatedApplications = @($relatedApplications)
    }

    $status = "ready"
    if ($missingRequiredK8sDirectories.Count -gt 0) {
        $status = "error"
    }
    elseif (
        $missingRecommendedK8sDirectories.Count -gt 0 -or
        $missingCompatibleDataServices.Count -gt 0 -or
        $missingRelatedApplications.Count -gt 0
    ) {
        $status = "attention"
    }

    $statusCounts[$status] += 1
    $serviceRecords += [PSCustomObject]@{
        Name = $serviceName
        Status = $status
        Notes = $definition.Notes
        BuildProfile = $buildProfile
        BuildPublicImage = $buildPublicImage
        RuntimePublicImage = $runtimePublicImage
        ImageProvenanceStatus = $imageProvenanceStatus
        RequiredK8sDirectories = @($requiredK8sDirectories)
        MissingRequiredK8sDirectories = @($missingRequiredK8sDirectories)
        RecommendedK8sDirectories = @($recommendedK8sDirectories)
        MissingRecommendedK8sDirectories = @($missingRecommendedK8sDirectories)
        CompatibleDataServices = @($compatibleDataServices)
        SelectedCompatibleDataServices = @($selectedCompatibleDataServices)
        MissingCompatibleDataServices = @($missingCompatibleDataServices)
        RelatedApplications = @($relatedApplications)
        SelectedRelatedApplications = @($selectedRelatedApplications)
        MissingRelatedApplications = @($missingRelatedApplications)
    }
}

$helmRecords = @()
foreach ($release in @($helmReleaseCatalog.Releases | Sort-Object Name)) {
    if ($effectiveK8sDirectories -notcontains $release.K8sDirectory) {
        continue
    }

    $chart = Get-OptionalCatalogValue -Item $release -Name "Chart"
    $repoName = Get-OptionalCatalogValue -Item $release -Name "RepoName"
    $repoUrl = Get-OptionalCatalogValue -Item $release -Name "RepoUrl"
    $notes = Get-OptionalCatalogValue -Item $release -Name "Notes"

    $helmRecords += [PSCustomObject]@{
        Name = $release.Name
        Enabled = [bool]$release.Enabled
        Namespace = $release.Namespace
        K8sDirectory = $release.K8sDirectory
        Chart = $chart
        RepoName = $repoName
        RepoUrl = $repoUrl
        ChartSourceType = Get-HelmChartSourceType -Release $release
        VersionPinStatus = Get-HelmVersionPinStatus -Release $release
        Notes = $notes
    }
}

$applicationsText = Get-ListText -Values $selection.Applications
$explicitDataServicesText = Get-ListText -Values $selection.DataServices
$effectiveDataServicesText = Get-ListText -Values $effectiveDataServices
$serviceDirectoriesText = Get-ListText -Values $effectiveServiceDirectories
$helmComponentsText = Get-ListText -Values @($helmRecords | ForEach-Object { $_.Name })
$statusSummaryText = "ready={0}, attention={1}, error={2}, uncatalogued={3}" -f `
    $statusCounts.ready,
    $statusCounts.attention,
    $statusCounts.error,
    $statusCounts.uncatalogued

switch ($Format) {
    "json" {
        $document = ([ordered]@{
            Profile = $selection.Profile
            Description = $selection.Description
            Applications = @($selection.Applications)
            ExplicitDataServices = @($selection.DataServices)
            EffectiveDataServices = @($effectiveDataServices)
            IncludeJenkins = [bool]$IncludeJenkins
            K8sDirectories = @($effectiveK8sDirectories)
            ServiceDirectories = @($effectiveServiceDirectories)
            StatusCounts = $statusCounts
            Services = @($serviceRecords)
            HelmReleases = @($helmRecords)
        } | ConvertTo-Json -Depth 10)
    }
    "markdown" {
        $lines = @(
            "# Service Dependency Plan",
            "",
            "## Summary",
            "",
            ("- Profile: " + $selection.Profile),
            ("- Description: " + $selection.Description),
            ("- Applications: " + $applicationsText),
            ("- Explicit data services: " + $explicitDataServicesText),
            ("- Effective in-cluster data services: " + $effectiveDataServicesText),
            ("- Service templates in scope: " + $serviceDirectoriesText),
            ("- Helm components in scope: " + $helmComponentsText),
            ("- Status counts: " + $statusSummaryText),
            ""
        )

        if ($serviceRecords.Count -gt 0) {
            $lines += "## Service Dependency Details"
            $lines += ""
            foreach ($service in $serviceRecords) {
                $lines += ("### " + $service.Name)
                $lines += ""
                $lines += ("- Status: " + $service.Status)
                $lines += ("- Notes: " + $service.Notes)
                $lines += ("- Build profile: " + $(if ($service.BuildProfile) { $service.BuildProfile } else { "not cataloged" }))
                $lines += ("- Build public image: " + $(if ($service.BuildPublicImage) { $service.BuildPublicImage } else { "not cataloged" }))
                $lines += ("- Runtime public image: " + $(if ($service.RuntimePublicImage) { $service.RuntimePublicImage } else { "not cataloged" }))
                $lines += ("- Image provenance status: " + $service.ImageProvenanceStatus)
                $lines += ("- Required Kubernetes prerequisites: " + (Get-ListText -Values $service.RequiredK8sDirectories))
                $lines += ("- Missing required Kubernetes prerequisites: " + (Get-ListText -Values $service.MissingRequiredK8sDirectories))
                $lines += ("- Recommended Kubernetes add-ons: " + (Get-ListText -Values $service.RecommendedK8sDirectories))
                $lines += ("- Missing recommended Kubernetes add-ons: " + (Get-ListText -Values $service.MissingRecommendedK8sDirectories))
                $lines += ("- Compatible in-cluster data services: " + (Get-ListText -Values $service.CompatibleDataServices))
                $lines += ("- Compatible data services currently available: " + (Get-ListText -Values $service.SelectedCompatibleDataServices))
                $lines += ("- Missing compatible in-cluster data services: " + (Get-ListText -Values $service.MissingCompatibleDataServices))
                $lines += ("- Related applications: " + (Get-ListText -Values $service.RelatedApplications))
                $lines += ("- Related applications currently selected: " + (Get-ListText -Values $service.SelectedRelatedApplications))
                $lines += ("- Missing related applications: " + (Get-ListText -Values $service.MissingRelatedApplications))
                $lines += ""
            }
        }

        if ($helmRecords.Count -gt 0) {
            $lines += "## Helm Dependency Details"
            $lines += ""
            foreach ($release in $helmRecords) {
                $chart = if ($release.Chart) { $release.Chart } else { "not configured" }
                $repo = if ($release.RepoUrl) { $release.RepoUrl } else { "not configured" }
                $lines += ("### " + $release.Name)
                $lines += ""
                $lines += ("- Enabled: " + [string]$release.Enabled)
                $lines += ("- Namespace: " + $release.Namespace)
                $lines += ("- Kubernetes directory: " + $release.K8sDirectory)
                $lines += ("- Chart: " + $chart)
                $lines += ("- Repository: " + $repo)
                $lines += ("- Chart source type: " + $release.ChartSourceType)
                $lines += ("- Version pin status: " + $release.VersionPinStatus)
                if ($release.Notes) {
                    $lines += ("- Notes: " + $release.Notes)
                }
                $lines += ""
            }
        }

        $document = $lines -join [Environment]::NewLine
    }
    default {
        $lines = @(
            "Service Dependency Plan",
            "=======================",
            ("Profile: " + $selection.Profile),
            ("Description: " + $selection.Description),
            ("Applications: " + $applicationsText),
            ("Explicit data services: " + $explicitDataServicesText),
            ("Effective in-cluster data services: " + $effectiveDataServicesText),
            ("Service templates in scope: " + $serviceDirectoriesText),
            ("Helm components in scope: " + $helmComponentsText),
            ("Status counts: " + $statusSummaryText),
            ""
        )

        foreach ($service in $serviceRecords) {
            $lines += $service.Name
            $lines += ("  Status: " + $service.Status)
            $lines += ("  Notes: " + $service.Notes)
            $lines += ("  Build profile: " + $(if ($service.BuildProfile) { $service.BuildProfile } else { "not cataloged" }))
            $lines += ("  Build public image: " + $(if ($service.BuildPublicImage) { $service.BuildPublicImage } else { "not cataloged" }))
            $lines += ("  Runtime public image: " + $(if ($service.RuntimePublicImage) { $service.RuntimePublicImage } else { "not cataloged" }))
            $lines += ("  Image provenance status: " + $service.ImageProvenanceStatus)
            $lines += ("  Required Kubernetes prerequisites: " + (Get-ListText -Values $service.RequiredK8sDirectories))
            $lines += ("  Missing required Kubernetes prerequisites: " + (Get-ListText -Values $service.MissingRequiredK8sDirectories))
            $lines += ("  Recommended Kubernetes add-ons: " + (Get-ListText -Values $service.RecommendedK8sDirectories))
            $lines += ("  Missing recommended Kubernetes add-ons: " + (Get-ListText -Values $service.MissingRecommendedK8sDirectories))
            $lines += ("  Compatible in-cluster data services: " + (Get-ListText -Values $service.CompatibleDataServices))
            $lines += ("  Compatible data services currently available: " + (Get-ListText -Values $service.SelectedCompatibleDataServices))
            $lines += ("  Missing compatible in-cluster data services: " + (Get-ListText -Values $service.MissingCompatibleDataServices))
            $lines += ("  Related applications: " + (Get-ListText -Values $service.RelatedApplications))
            $lines += ("  Related applications currently selected: " + (Get-ListText -Values $service.SelectedRelatedApplications))
            $lines += ("  Missing related applications: " + (Get-ListText -Values $service.MissingRelatedApplications))
            $lines += ""
        }

        if ($serviceRecords.Count -eq 0) {
            $lines += "No services selected."
        }

        if ($helmRecords.Count -gt 0) {
            $lines += ""
            $lines += "Helm dependency details"
            foreach ($release in $helmRecords) {
                $chart = if ($release.Chart) { $release.Chart } else { "not configured" }
                $repo = if ($release.RepoUrl) { $release.RepoUrl } else { "not configured" }
                $lines += $release.Name
                $lines += ("  Enabled: " + [string]$release.Enabled)
                $lines += ("  Namespace: " + $release.Namespace)
                $lines += ("  Kubernetes directory: " + $release.K8sDirectory)
                $lines += ("  Chart: " + $chart)
                $lines += ("  Repository: " + $repo)
                $lines += ("  Chart source type: " + $release.ChartSourceType)
                $lines += ("  Version pin status: " + $release.VersionPinStatus)
                if ($release.Notes) {
                    $lines += ("  Notes: " + $release.Notes)
                }
                $lines += ""
            }
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
    Write-Host ("Wrote service dependency plan to {0}" -f $resolvedOutputPath)
}
else {
    Write-Output $document
}
