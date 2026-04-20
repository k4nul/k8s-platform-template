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

function Get-EffectiveDataServices {
    param(
        [string[]]$K8sDirectories,
        [pscustomobject]$Selection,
        [hashtable]$DataServiceCatalog
    )

    $effectiveDataServices = New-Object System.Collections.Generic.List[string]
    foreach ($serviceName in @($DataServiceCatalog.Keys | Sort-Object)) {
        if ($Selection.DataServices -contains $serviceName -or $K8sDirectories -contains $DataServiceCatalog[$serviceName]) {
            $effectiveDataServices.Add($serviceName) | Out-Null
        }
    }

    return @($effectiveDataServices | Sort-Object -Unique)
}

function Get-ListText {
    param(
        [object[]]$Values
    )

    if (@($Values).Count -gt 0) {
        return (@($Values) -join ", ")
    }

    return "none"
}

if (-not $PSBoundParameters.ContainsKey("RepoRoot") -or -not $RepoRoot) {
    $RepoRoot = Join-Path $PSScriptRoot ".."
}

$root = (Resolve-Path -Path $RepoRoot).Path
$selection = Resolve-PlatformSelection -Profile $Profile -Applications $Applications -DataServices $DataServices -IncludeJenkins:$IncludeJenkins
$dependencyCatalog = Import-PowerShellDataFile -Path (Join-Path $root "config\service-dependencies.psd1")
$dataServiceCatalog = Get-PlatformDataServiceCatalog

$dependencyMap = [ordered]@{}
foreach ($service in @($dependencyCatalog.Services | Sort-Object { $_.Name })) {
    $dependencyMap[$service.Name] = $service
}

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

$applicationsText = Get-ListText -Values $selection.Applications
$explicitDataServicesText = Get-ListText -Values $selection.DataServices
$effectiveDataServicesText = Get-ListText -Values $effectiveDataServices
$serviceDirectoriesText = Get-ListText -Values $effectiveServiceDirectories
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
            ("Status counts: " + $statusSummaryText),
            ""
        )

        foreach ($service in $serviceRecords) {
            $lines += $service.Name
            $lines += ("  Status: " + $service.Status)
            $lines += ("  Notes: " + $service.Notes)
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
