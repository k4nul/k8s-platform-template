param(
    [string]$RepoRoot,
    [string]$Profile = "full",
    [string[]]$Applications = @(),
    [string[]]$DataServices = @(),
    [switch]$IncludeJenkins,
    [switch]$Strict
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

if (-not $PSBoundParameters.ContainsKey("RepoRoot") -or -not $RepoRoot) {
    $RepoRoot = Join-Path $PSScriptRoot ".."
}

$root = (Resolve-Path -Path $RepoRoot).Path
$servicesRoot = Join-Path $root "services"
$catalogPath = Join-Path $root "config\service-dependencies.psd1"
$dependencyCatalog = Import-PowerShellDataFile -Path $catalogPath
$dataServiceCatalog = Get-PlatformDataServiceCatalog
$selection = Resolve-PlatformSelection -Profile $Profile -Applications $Applications -DataServices $DataServices -IncludeJenkins:$IncludeJenkins

$errors = New-Object System.Collections.Generic.List[string]
$warnings = New-Object System.Collections.Generic.List[string]
$catalogMap = [ordered]@{}

foreach ($service in @($dependencyCatalog.Services | Sort-Object { $_.Name })) {
    $catalogMap[$service.Name] = $service
}

$actualServiceDirectories = @(
    Get-ChildItem -Path $servicesRoot -Directory |
        Sort-Object Name |
        Select-Object -ExpandProperty Name
)

$missingCatalogEntries = @($actualServiceDirectories | Where-Object { -not $catalogMap.Contains($_) })
$missingServiceDirectories = @($catalogMap.Keys | Where-Object { $actualServiceDirectories -notcontains $_ })

foreach ($serviceName in $missingCatalogEntries) {
    $errors.Add("Service dependency catalog is missing services/$serviceName.") | Out-Null
}

foreach ($serviceName in $missingServiceDirectories) {
    $errors.Add("Service dependency catalog entry does not match an existing service directory: $serviceName") | Out-Null
}

$effectiveK8sDirectories = Get-EffectiveK8sDirectories -Root $root -Selection $selection
$effectiveServiceDirectories = Get-EffectiveServiceDirectories -Root $root -Selection $selection
$effectiveDataServices = Get-EffectiveDataServices -K8sDirectories $effectiveK8sDirectories -Selection $selection -DataServiceCatalog $dataServiceCatalog

foreach ($serviceName in $effectiveServiceDirectories) {
    if (-not $catalogMap.Contains($serviceName)) {
        continue
    }

    $definition = $catalogMap[$serviceName]
    $requiredK8sDirectories = @($definition.RequiredK8sDirectories | Sort-Object -Unique)
    $recommendedK8sDirectories = @($definition.RecommendedK8sDirectories | Sort-Object -Unique)
    $compatibleDataServices = @($definition.CompatibleDataServices | Sort-Object -Unique)
    $relatedApplications = @($definition.RelatedApplications | Sort-Object -Unique)

    $missingRequiredK8sDirectories = @($requiredK8sDirectories | Where-Object { $effectiveK8sDirectories -notcontains $_ })
    if ($missingRequiredK8sDirectories.Count -gt 0) {
        $errors.Add(
            "Selected service '$serviceName' is missing required Kubernetes prerequisites: $($missingRequiredK8sDirectories -join ', ')"
        ) | Out-Null
    }

    $missingRecommendedK8sDirectories = @($recommendedK8sDirectories | Where-Object { $effectiveK8sDirectories -notcontains $_ })
    if ($missingRecommendedK8sDirectories.Count -gt 0) {
        $warnings.Add(
            "Selected service '$serviceName' is missing recommended Kubernetes add-ons: $($missingRecommendedK8sDirectories -join ', ')"
        ) | Out-Null
    }

    if ($compatibleDataServices.Count -gt 0) {
        $selectedCompatibleDataServices = @($compatibleDataServices | Where-Object { $effectiveDataServices -contains $_ })
        if ($selectedCompatibleDataServices.Count -eq 0) {
            $warnings.Add(
                "Selected service '$serviceName' has no compatible in-cluster data service selected. Compatible options: $($compatibleDataServices -join ', '). This can be intentional when the service points at an external endpoint."
            ) | Out-Null
        }
    }

    if ($relatedApplications.Count -gt 0) {
        $selectedRelatedApplications = @($relatedApplications | Where-Object { $effectiveServiceDirectories -contains $_ })
        if ($selectedRelatedApplications.Count -eq 0) {
            $warnings.Add(
                "Selected service '$serviceName' has no related peer applications in the current bundle. Related applications: $($relatedApplications -join ', ')"
            ) | Out-Null
        }
    }
}

$failureSections = New-Object System.Collections.Generic.List[string]

if ($errors.Count -gt 0) {
    $failureSections.Add("Errors:`n- " + ($errors -join "`n- ")) | Out-Null
}

if ($Strict -and $warnings.Count -gt 0) {
    $failureSections.Add("Warnings promoted to errors:`n- " + ($warnings -join "`n- ")) | Out-Null
}

if ($failureSections.Count -gt 0) {
    Write-Error ("Platform selection validation failed:`n{0}" -f ($failureSections -join "`n"))
}

if ($warnings.Count -gt 0) {
    Write-Warning ("Platform selection warnings:`n- {0}" -f ($warnings -join "`n- "))
}

Write-Host "Platform selection validation completed."
