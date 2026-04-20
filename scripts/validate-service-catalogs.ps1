param(
    [string]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "platform-catalog.ps1")

if (-not $PSBoundParameters.ContainsKey("RepoRoot") -or -not $RepoRoot) {
    $RepoRoot = Join-Path $PSScriptRoot ".."
}

$root = (Resolve-Path -Path $RepoRoot).Path
$servicesRoot = Join-Path $root "services"
$k8sRoot = Join-Path $root "k8s"

$serviceDirectories = @(
    Get-ChildItem -Path $servicesRoot -Directory |
        Sort-Object Name |
        Select-Object -ExpandProperty Name
)
$k8sDirectories = @(
    Get-ChildItem -Path $k8sRoot -Directory |
        Sort-Object Name |
        Select-Object -ExpandProperty Name
)

$catalogFiles = @(
    @{ Name = "config/service-builds.psd1"; Path = Join-Path $root "config\service-builds.psd1" },
    @{ Name = "config/service-config-artifacts.psd1"; Path = Join-Path $root "config\service-config-artifacts.psd1" },
    @{ Name = "config/service-dependencies.psd1"; Path = Join-Path $root "config\service-dependencies.psd1" },
    @{ Name = "config/service-pipelines.psd1"; Path = Join-Path $root "config\service-pipelines.psd1" },
    @{ Name = "config/service-runtime-bindings.psd1"; Path = Join-Path $root "config\service-runtime-bindings.psd1" }
)

$errors = New-Object System.Collections.Generic.List[string]

foreach ($catalogFile in $catalogFiles) {
    $catalog = Import-PowerShellDataFile -Path $catalogFile.Path
    $catalogServiceNames = @($catalog.Services | Sort-Object { $_.Name } | ForEach-Object { $_.Name })
    $missingEntries = @($serviceDirectories | Where-Object { $catalogServiceNames -notcontains $_ })
    $extraEntries = @($catalogServiceNames | Where-Object { $serviceDirectories -notcontains $_ })

    foreach ($serviceName in $missingEntries) {
        $errors.Add("$($catalogFile.Name) is missing a catalog entry for services/$serviceName.") | Out-Null
    }

    foreach ($serviceName in $extraEntries) {
        $errors.Add("$($catalogFile.Name) references a service that does not exist: $serviceName") | Out-Null
    }
}

$pipelineCatalog = Import-PowerShellDataFile -Path (Join-Path $root "config\service-pipelines.psd1")
$runtimeCatalog = Import-PowerShellDataFile -Path (Join-Path $root "config\service-runtime-bindings.psd1")
$dependencyCatalog = Import-PowerShellDataFile -Path (Join-Path $root "config\service-dependencies.psd1")

$knownJenkinsVariables = @(
    "DOCKER_REGISTRY",
    "MODE",
    "BUILD_PROJECT",
    "CACHE",
    "SSHKEY_FILTER",
    "SOURCE_PROJECT"
)

foreach ($service in @($pipelineCatalog.Services)) {
    foreach ($variableName in @($service.OptionalEnvVars)) {
        if ($knownJenkinsVariables -notcontains $variableName) {
            $errors.Add("Pipeline catalog for $($service.Name) references an unknown Jenkins variable: $variableName") | Out-Null
        }
    }
}

$runtimeVariableNames = @($runtimeCatalog.Variables.Keys | Sort-Object)
foreach ($service in @($runtimeCatalog.Services)) {
    foreach ($variableName in @($service.RequiredEnvVars)) {
        if ($runtimeVariableNames -notcontains $variableName) {
            $errors.Add("Runtime catalog for $($service.Name) references an unknown compose variable: $variableName") | Out-Null
        }
    }
}

$knownDataServices = @((Get-PlatformDataServiceCatalog).Keys | Sort-Object)
foreach ($service in @($dependencyCatalog.Services)) {
    foreach ($directory in @($service.RequiredK8sDirectories)) {
        if ($k8sDirectories -notcontains $directory) {
            $errors.Add("Dependency catalog for $($service.Name) references a missing required Kubernetes directory: $directory") | Out-Null
        }
    }

    foreach ($directory in @($service.RecommendedK8sDirectories)) {
        if ($k8sDirectories -notcontains $directory) {
            $errors.Add("Dependency catalog for $($service.Name) references a missing recommended Kubernetes directory: $directory") | Out-Null
        }
    }

    foreach ($dataService in @($service.CompatibleDataServices)) {
        if ($knownDataServices -notcontains $dataService) {
            $errors.Add("Dependency catalog for $($service.Name) references an unknown data service: $dataService") | Out-Null
        }
    }

    foreach ($relatedApplication in @($service.RelatedApplications)) {
        if ($serviceDirectories -notcontains $relatedApplication) {
            $errors.Add("Dependency catalog for $($service.Name) references an unknown related application: $relatedApplication") | Out-Null
        }
    }
}

$applicationCatalog = Get-PlatformApplicationCatalog
foreach ($applicationName in @($applicationCatalog.Keys | Sort-Object)) {
    $definition = $applicationCatalog[$applicationName]
    if ($definition.ServiceDirectory -and $serviceDirectories -notcontains $definition.ServiceDirectory) {
        $errors.Add("Platform application catalog entry '$applicationName' references a missing service directory: $($definition.ServiceDirectory)") | Out-Null
    }

    if ($definition.K8sDirectory -and $k8sDirectories -notcontains $definition.K8sDirectory) {
        $errors.Add("Platform application catalog entry '$applicationName' references a missing Kubernetes directory: $($definition.K8sDirectory)") | Out-Null
    }
}

$dataServiceCatalog = Get-PlatformDataServiceCatalog
foreach ($dataServiceName in @($dataServiceCatalog.Keys | Sort-Object)) {
    if ($k8sDirectories -notcontains $dataServiceCatalog[$dataServiceName]) {
        $errors.Add("Platform data service catalog entry '$dataServiceName' references a missing Kubernetes directory: $($dataServiceCatalog[$dataServiceName])") | Out-Null
    }
}

if ($errors.Count -gt 0) {
    Write-Error ("Service catalog validation failed:`n- {0}" -f ($errors -join "`n- "))
}

Write-Host "Service catalog validation completed."
