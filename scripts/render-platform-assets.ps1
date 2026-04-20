param(
    [string]$RepoRoot,

    [Parameter(Mandatory = $true)]
    [string]$OutputPath,

    [string]$DockerRegistry,

    [string]$Version,
    [string]$ValuesFile,
    [string]$Profile = "full",
    [string[]]$Applications = @(),
    [string[]]$DataServices = @(),
    [switch]$IncludeJenkins,
    [switch]$FailOnUnresolvedToken
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "platform-catalog.ps1")

if (-not $PSBoundParameters.ContainsKey("RepoRoot") -or -not $RepoRoot) {
    $RepoRoot = Join-Path $PSScriptRoot ".."
}

if (-not $PSBoundParameters.ContainsKey("ValuesFile") -or -not $ValuesFile) {
    $ValuesFile = Join-Path $PSScriptRoot "..\config\platform-values.env.example"
}

$root = (Resolve-Path -Path $RepoRoot).Path
$renderedRoot = [System.IO.Path]::GetFullPath($OutputPath)
$k8sRenderScript = Join-Path $root "k8s\render-manifests.ps1"
$serviceRenderScript = Join-Path $root "scripts\render-service-configs.ps1"
$bundleWriterScript = Join-Path $root "scripts\write-platform-bundle-files.ps1"
$clusterBootstrapWriterScript = Join-Path $root "scripts\write-cluster-bootstrap-files.ps1"
$profileCatalogScript = Join-Path $root "scripts\show-profile-catalog.ps1"
$clusterPreflightScript = Join-Path $root "scripts\show-cluster-preflight.ps1"
$clusterSecretPlanScript = Join-Path $root "scripts\show-cluster-secret-plan.ps1"
$validationReadinessScript = Join-Path $root "scripts\show-validation-readiness.ps1"
$planScript = Join-Path $root "scripts\show-platform-plan.ps1"
$platformValuesPlanScript = Join-Path $root "scripts\show-platform-values-plan.ps1"
$serviceBuildPlanScript = Join-Path $root "scripts\show-service-build-plan.ps1"
$serviceConfigPlanScript = Join-Path $root "scripts\show-service-config-plan.ps1"
$serviceDependencyPlanScript = Join-Path $root "scripts\show-service-dependency-plan.ps1"
$serviceInputPlanScript = Join-Path $root "scripts\show-service-input-plan.ps1"
$serviceRuntimePlanScript = Join-Path $root "scripts\show-service-runtime-plan.ps1"
$selection = Resolve-PlatformSelection -Profile $Profile -Applications $Applications -DataServices $DataServices -IncludeJenkins:$IncludeJenkins

New-Item -ItemType Directory -Path $renderedRoot -Force | Out-Null

$renderedK8sRoot = Join-Path $renderedRoot "k8s"
$renderedServicesRoot = Join-Path $renderedRoot "services"

if ($selection.IncludeAllK8s) {
    & $k8sRenderScript `
        -InputPath (Join-Path $root "k8s") `
        -OutputPath $renderedK8sRoot `
        -DockerRegistry $DockerRegistry `
        -Version $Version `
        -ValuesFile $ValuesFile `
        -FailOnUnresolvedToken:$FailOnUnresolvedToken
}
else {
    foreach ($directory in $selection.K8sDirectories) {
        & $k8sRenderScript `
            -InputPath (Join-Path $root ("k8s\{0}" -f $directory)) `
            -OutputPath (Join-Path $renderedK8sRoot $directory) `
            -DockerRegistry $DockerRegistry `
            -Version $Version `
            -ValuesFile $ValuesFile `
            -FailOnUnresolvedToken:$FailOnUnresolvedToken
    }
}

if ($selection.IncludeAllServices) {
    & $serviceRenderScript `
        -InputPath (Join-Path $root "services") `
        -OutputPath $renderedServicesRoot `
        -DockerRegistry $DockerRegistry `
        -Version $Version `
        -ValuesFile $ValuesFile `
        -FailOnUnresolvedToken:$FailOnUnresolvedToken
}
else {
    foreach ($directory in $selection.ServiceDirectories) {
        & $serviceRenderScript `
            -InputPath (Join-Path $root ("services\{0}" -f $directory)) `
            -OutputPath (Join-Path $renderedServicesRoot $directory) `
            -DockerRegistry $DockerRegistry `
            -Version $Version `
            -ValuesFile $ValuesFile `
            -FailOnUnresolvedToken:$FailOnUnresolvedToken
    }
}

Write-Host ("Rendered profile '{0}' to {1}" -f $selection.Profile, $renderedRoot)
if (-not $selection.IncludeAllK8s) {
    Write-Host ("Rendered Kubernetes directories: {0}" -f (($selection.K8sDirectories -join ", ")))
}
if (-not $selection.IncludeAllServices) {
    Write-Host ("Rendered service directories: {0}" -f (($selection.ServiceDirectories -join ", ")))
}

& $bundleWriterScript `
    -RepoRoot $root `
    -BundleRoot $renderedRoot `
    -ValuesFile $ValuesFile `
    -DockerRegistry $DockerRegistry `
    -Version $Version `
    -Profile $Profile `
    -Applications $Applications `
    -DataServices $DataServices `
    -IncludeJenkins:$IncludeJenkins

& $clusterBootstrapWriterScript `
    -RepoRoot $root `
    -BundleRoot $renderedRoot `
    -ValuesFile $ValuesFile `
    -Profile $Profile `
    -Applications $Applications `
    -DataServices $DataServices `
    -IncludeJenkins:$IncludeJenkins

& $profileCatalogScript `
    -RepoRoot $root `
    -Format markdown `
    -OutputPath (Join-Path $renderedRoot "PROFILE_CATALOG.md")

& $clusterPreflightScript `
    -RepoRoot $root `
    -ValuesFile $ValuesFile `
    -Profile $Profile `
    -Applications $Applications `
    -DataServices $DataServices `
    -IncludeJenkins:$IncludeJenkins `
    -Format markdown `
    -OutputPath (Join-Path $renderedRoot "CLUSTER_PREFLIGHT.md")

& $clusterSecretPlanScript `
    -RepoRoot $root `
    -ValuesFile $ValuesFile `
    -Profile $Profile `
    -Applications $Applications `
    -DataServices $DataServices `
    -IncludeJenkins:$IncludeJenkins `
    -Format markdown `
    -OutputPath (Join-Path $renderedRoot "CLUSTER_SECRET_PLAN.md")

& $validationReadinessScript `
    -RepoRoot $root `
    -ValuesFile $ValuesFile `
    -Profile $Profile `
    -Applications $Applications `
    -DataServices $DataServices `
    -IncludeJenkins:$IncludeJenkins `
    -Format markdown `
    -OutputPath (Join-Path $renderedRoot "VALIDATION_READINESS.md")

& $planScript `
    -RepoRoot $root `
    -Profile $Profile `
    -Applications $Applications `
    -DataServices $DataServices `
    -IncludeJenkins:$IncludeJenkins `
    -Format markdown `
    -OutputPath (Join-Path $renderedRoot "PLATFORM_PLAN.md")

& $planScript `
    -RepoRoot $root `
    -Profile $Profile `
    -Applications $Applications `
    -DataServices $DataServices `
    -IncludeJenkins:$IncludeJenkins `
    -Format mermaid `
    -OutputPath (Join-Path $renderedRoot "PLATFORM_PLAN.mmd")

& $platformValuesPlanScript `
    -RepoRoot $root `
    -Profile $Profile `
    -Applications $Applications `
    -DataServices $DataServices `
    -IncludeJenkins:$IncludeJenkins `
    -ValuesFile $ValuesFile `
    -Format markdown `
    -OutputPath (Join-Path $renderedRoot "PLATFORM_VALUES_PLAN.md")

$defaultPlatformValuesFile = Join-Path $root "config\platform-values.env.example"
& $platformValuesPlanScript `
    -RepoRoot $root `
    -Profile $Profile `
    -Applications $Applications `
    -DataServices $DataServices `
    -IncludeJenkins:$IncludeJenkins `
    -ValuesFile $defaultPlatformValuesFile `
    -Format env `
    -OutputPath (Join-Path $renderedRoot "platform-values.env.example")

$serviceBuildPlanParameters = @{
    RepoRoot = $root
    Format = "markdown"
    OutputPath = (Join-Path $renderedRoot "SERVICE_BUILD_PLAN.md")
}
if (-not $selection.IncludeAllServices) {
    $serviceBuildPlanParameters.ServiceNames = $selection.ServiceDirectories
}
& $serviceBuildPlanScript @serviceBuildPlanParameters

$serviceConfigPlanParameters = @{
    RepoRoot = $root
    Format = "markdown"
    OutputPath = (Join-Path $renderedRoot "SERVICE_CONFIG_PLAN.md")
}
if (-not $selection.IncludeAllServices) {
    $serviceConfigPlanParameters.ServiceNames = $selection.ServiceDirectories
}
& $serviceConfigPlanScript @serviceConfigPlanParameters

& $serviceDependencyPlanScript `
    -RepoRoot $root `
    -Profile $Profile `
    -Applications $Applications `
    -DataServices $DataServices `
    -IncludeJenkins:$IncludeJenkins `
    -Format markdown `
    -OutputPath (Join-Path $renderedRoot "SERVICE_DEPENDENCY_PLAN.md")

$serviceRuntimePlanParameters = @{
    RepoRoot = $root
    Format = "markdown"
    OutputPath = (Join-Path $renderedRoot "SERVICE_RUNTIME_PLAN.md")
}
if (-not $selection.IncludeAllServices) {
    $serviceRuntimePlanParameters.ServiceNames = $selection.ServiceDirectories
}
& $serviceRuntimePlanScript @serviceRuntimePlanParameters

$serviceRuntimeEnvParameters = @{
    RepoRoot = $root
    Format = "env"
    OutputPath = (Join-Path $renderedRoot "service-runtime.env.example")
}
if (-not $selection.IncludeAllServices) {
    $serviceRuntimeEnvParameters.ServiceNames = $selection.ServiceDirectories
}
& $serviceRuntimePlanScript @serviceRuntimeEnvParameters

& $serviceInputPlanScript `
    -RepoRoot $root `
    -Profile $Profile `
    -Applications $Applications `
    -DataServices $DataServices `
    -IncludeJenkins:$IncludeJenkins `
    -ValuesFile $ValuesFile `
    -RuntimeEnvFile (Join-Path $renderedRoot "service-runtime.env.example") `
    -Format markdown `
    -OutputPath (Join-Path $renderedRoot "SERVICE_INPUT_PLAN.md")
