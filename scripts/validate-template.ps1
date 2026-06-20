param(
    [string]$RepoRoot,
    [ValidateSet("auto", "kubeconform", "kubectl")]
    [string]$SchemaValidator = "auto"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Assert-PathExists {
    param(
        [string]$Path,
        [string]$Label
    )

    if (-not (Test-Path -Path $Path)) {
        throw ("Missing {0}: {1}" -f $Label, $Path)
    }
}

function Assert-FileContains {
    param(
        [string]$Path,
        [string]$Pattern,
        [string]$Label
    )

    $content = Get-Content -Path $Path -Raw
    if ($content -notmatch $Pattern) {
        throw ("{0} did not contain expected pattern '{1}': {2}" -f $Label, $Pattern, $Path)
    }
}

function Get-RequiredObjectProperty {
    param(
        [Parameter(Mandatory = $true)]
        [object]$InputObject,

        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [string]$Label
    )

    $property = $InputObject.PSObject.Properties[$Name]
    if ($null -eq $property) {
        throw ("{0} is missing required property '{1}'." -f $Label, $Name)
    }

    return $property.Value
}

function Assert-PhaseTransitionMetadata {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $phaseGates = Get-Content -Path $Path -Raw | ConvertFrom-Json
    $currentPhase = [string](Get-RequiredObjectProperty -InputObject $phaseGates -Name "current_phase" -Label "Phase gates manifest")
    if ($currentPhase -notin @("public-default-security-review", "template-maintenance")) {
        return
    }

    $nextPhase = [string](Get-RequiredObjectProperty -InputObject $phaseGates -Name "next_phase" -Label "Phase gates manifest")
    $transition = Get-RequiredObjectProperty -InputObject $phaseGates -Name "transition" -Label "Phase gates manifest"
    $transitionValidationCommand = [string](
        Get-RequiredObjectProperty `
            -InputObject $transition `
            -Name "transition_validation_command" `
            -Label "Phase gates transition"
    )

    if ($currentPhase -eq "public-default-security-review" -and $nextPhase.Trim() -ne "template-maintenance") {
        throw "Public-default security review phase must declare next_phase 'template-maintenance' before automated transition routing can resume."
    }

    if (-not $nextPhase.Trim()) {
        throw "Template maintenance phase must declare next_phase before automated transition routing can resume."
    }

    if (-not $transitionValidationCommand.Trim()) {
        throw ("{0} phase must declare transition.transition_validation_command before automated transition routing can resume." -f $currentPhase)
    }
}

function Assert-PublicDefaultSecurityReviewPosture {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Root
    )

    $networkPolicy = Join-Path $Root "k8s\100_namespace\platform-network-policy.yaml"
    $namespaceReadme = Join-Path $Root "k8s\100_namespace\README.md"
    $dashboardReadme = Join-Path $Root "k8s\311_platform_kubernetes-dashboard\README.md"
    $platformCatalog = Join-Path $Root "scripts\platform-catalog.ps1"
    $dashboardAdminSample = Join-Path $Root "k8s\311_platform_kubernetes-dashboard\sample-admin-user.yaml"
    $dashboardViewerSample = Join-Path $Root "k8s\311_platform_kubernetes-dashboard\sample-viewer-user.yaml"

    Assert-FileContains -Path $networkPolicy -Pattern '(?m)^kind:\s*NetworkPolicy\s*$' -Label "Public-default NetworkPolicy manifest"
    Assert-FileContains -Path $networkPolicy -Pattern 'platform-public-ingress-baseline' -Label "Public-default NetworkPolicy manifest"
    Assert-FileContains -Path $networkPolicy -Pattern '(?m)^\s*podSelector:\s*\{\}\s*$' -Label "Public-default NetworkPolicy manifest"
    Assert-FileContains -Path $networkPolicy -Pattern '(?m)^\s*-\s*\{\}\s*$' -Label "Public-default NetworkPolicy manifest"
    Assert-FileContains -Path $namespaceReadme -Pattern 'intentionally permissive' -Label "Public-default NetworkPolicy documentation"
    Assert-FileContains -Path $namespaceReadme -Pattern 'environment-specific allow lists' -Label "Public-default NetworkPolicy documentation"

    Assert-FileContains -Path $platformCatalog -Pattern ([regex]::Escape("sample-admin-user.yaml")) -Label "Optional dashboard admin sample exclusion"
    Assert-FileContains -Path $platformCatalog -Pattern ([regex]::Escape("sample-viewer-user.yaml")) -Label "Optional dashboard viewer sample exclusion"
    Assert-FileContains -Path $dashboardAdminSample -Pattern '(?m)^kind:\s*ClusterRoleBinding\s*$' -Label "Dashboard manual admin RBAC sample"
    Assert-FileContains -Path $dashboardAdminSample -Pattern '(?m)^\s*name:\s*cluster-admin\s*$' -Label "Dashboard manual admin RBAC sample"
    Assert-FileContains -Path $dashboardViewerSample -Pattern '(?m)^kind:\s*RoleBinding\s*$' -Label "Dashboard manual viewer RBAC sample"
    Assert-FileContains -Path $dashboardViewerSample -Pattern '(?m)^\s*name:\s*view\s*$' -Label "Dashboard manual viewer RBAC sample"
    Assert-FileContains -Path $dashboardReadme -Pattern '(?s)not copied into\s+generated bundles by default' -Label "Dashboard manual RBAC documentation"
    Assert-FileContains -Path $dashboardReadme -Pattern 'cluster-admin' -Label "Dashboard manual RBAC documentation"
    Assert-FileContains -Path $dashboardReadme -Pattern 'namespace-scoped' -Label "Dashboard manual RBAC documentation"
    Assert-FileContains -Path $dashboardReadme -Pattern 'short-lived local evaluation' -Label "Dashboard manual RBAC documentation"
}

if (-not $PSBoundParameters.ContainsKey("RepoRoot") -or -not $RepoRoot) {
    $RepoRoot = Join-Path $PSScriptRoot ".."
}

$root = (Resolve-Path -Path $RepoRoot).Path
$publicValuesFile = Join-Path $root "config\platform-values.env.example"

$expectedPaths = @(
    "README.md",
    "QUICKSTART.md",
    "DEPLOYMENT_ENV.md",
    "ENV_CHECKLIST.md",
    "docs\instructions\phase-gates.json",
    "config\README.md",
    "config\platform-values.env.example",
    "config\profiles\README.md",
    "services\README.md",
    "services\nginx-web\README.md",
    "services\httpbin\README.md",
    "services\whoami\README.md",
    "services\adminer\README.md",
    "k8s\README.md",
    "k8s\100_namespace\platform-network-policy.yaml",
    "k8s\400_platform_nginx-web\README.md",
    "k8s\400_platform_httpbin\README.md",
    "k8s\400_platform_whoami\README.md",
    "k8s\401_platform_adminer\README.md",
    "k8s\311_platform_kubernetes-dashboard\sample-admin-user.yaml",
    "k8s\311_platform_kubernetes-dashboard\sample-viewer-user.yaml",
    "scripts\README.md",
    "scripts\platform-catalog.ps1",
    "scripts\validate-service-builds.ps1",
    "scripts\show-service-build-plan.ps1",
    "scripts\validate-rendered-bundle.ps1",
    "scripts\render-matrix-catalog.ps1",
    "scripts\show-render-matrix.ps1",
    "scripts\repository-workflow-helpers.ps1",
    "scripts\validate-render-matrix.ps1",
    "scripts\validate-kubernetes-security-baseline.ps1",
    "tests\validate-check-placeholders.Tests.ps1",
    "tests\validate-render-manifests.Tests.ps1",
    "tests\validate-rendered-bundle.Tests.ps1",
    "tests\repository-workflow-helpers.Tests.ps1",
    "tests\validate-kubernetes-security-baseline.Tests.ps1",
    "tests\validate-render-matrix.Tests.ps1",
    "tests\render-platform-assets.Tests.ps1",
    "tests\show-service-runtime-plan.Tests.ps1",
    "tests\show-platform-plan.Tests.ps1",
    "tests\show-validation-readiness.Tests.ps1"
)

foreach ($relativePath in $expectedPaths) {
    Assert-PathExists -Path (Join-Path $root $relativePath) -Label "expected repository path"
}

$serviceCatalogValidation = Join-Path $root "scripts\validate-service-catalogs.ps1"
$serviceBuildValidation = Join-Path $root "scripts\validate-service-builds.ps1"
$serviceConfigValidation = Join-Path $root "scripts\validate-service-config-artifacts.ps1"
$serviceRuntimeValidation = Join-Path $root "scripts\validate-service-runtime.ps1"
$selectionValidation = Join-Path $root "scripts\validate-platform-selection.ps1"
$valueValidation = Join-Path $root "scripts\validate-platform-values.ps1"
$renderScript = Join-Path $root "scripts\render-platform-assets.ps1"
$assetValidation = Join-Path $root "scripts\validate-platform-assets.ps1"
$renderMatrixCatalog = Join-Path $root "scripts\render-matrix-catalog.ps1"
$renderMatrixValidation = Join-Path $root "scripts\validate-render-matrix.ps1"
$renderManifestsTests = Join-Path $root "tests\validate-render-manifests.Tests.ps1"
$placeholderTests = Join-Path $root "tests\validate-check-placeholders.Tests.ps1"
$renderedBundleTests = Join-Path $root "tests\validate-rendered-bundle.Tests.ps1"
$repositoryWorkflowHelperTests = Join-Path $root "tests\repository-workflow-helpers.Tests.ps1"
$securityBaselineTests = Join-Path $root "tests\validate-kubernetes-security-baseline.Tests.ps1"
$renderMatrixTests = Join-Path $root "tests\validate-render-matrix.Tests.ps1"
$renderPlatformAssetsTests = Join-Path $root "tests\render-platform-assets.Tests.ps1"
$serviceRuntimePlanTests = Join-Path $root "tests\show-service-runtime-plan.Tests.ps1"
$platformPlanTests = Join-Path $root "tests\show-platform-plan.Tests.ps1"
$validationReadinessTests = Join-Path $root "tests\show-validation-readiness.Tests.ps1"
$renderedBundleValidation = Join-Path $root "scripts\validate-rendered-bundle.ps1"
$securityBaselineValidation = Join-Path $root "scripts\validate-kubernetes-security-baseline.ps1"
$phaseGatesManifest = Join-Path $root "docs\instructions\phase-gates.json"

Assert-FileContains -Path $renderedBundleValidation -Pattern "kubeconform" -Label "Rendered Kubernetes offline schema validation gate"
Assert-FileContains -Path $renderedBundleValidation -Pattern "kubectl apply --dry-run=client" -Label "Rendered Kubernetes kubectl dry-run validation gate"
Assert-PhaseTransitionMetadata -Path $phaseGatesManifest
Assert-PublicDefaultSecurityReviewPosture -Root $root

$coreRenderMatrixProfiles = @(
    "data-services",
    "shared-services",
    "full"
)

foreach ($profileName in $coreRenderMatrixProfiles) {
    Assert-FileContains -Path $renderMatrixCatalog -Pattern ([regex]::Escape($profileName)) -Label "Core render matrix profile coverage"
}

$securityBaselineTerms = @(
    "securityContext",
    "resources",
    "readinessProbe",
    "livenessProbe",
    "automountServiceAccountToken",
    "NetworkPolicy",
    "wildcard-rbac"
)

foreach ($term in $securityBaselineTerms) {
    Assert-FileContains -Path $securityBaselineValidation -Pattern $term -Label "Kubernetes security baseline validation gate"
}

& $securityBaselineValidation -Path $root -FailOnHighFinding

& $renderManifestsTests
& $placeholderTests
& $renderedBundleTests
& $repositoryWorkflowHelperTests
& $securityBaselineTests
& $renderMatrixTests
& $renderPlatformAssetsTests
& $serviceRuntimePlanTests
& $platformPlanTests
& $validationReadinessTests
& $serviceCatalogValidation -RepoRoot $root
& $serviceBuildValidation -RepoRoot $root
& $serviceConfigValidation -RepoRoot $root -ValuesFile $publicValuesFile
& $serviceRuntimeValidation -RepoRoot $root
& $selectionValidation -RepoRoot $root -Profile web-platform -Applications nginx-web,httpbin,whoami -DataServices redis
& $valueValidation -RepoRoot $root -ValuesFile $publicValuesFile -Profile web-platform -Applications nginx-web,httpbin,whoami -DataServices redis

$tempOutput = Join-Path ([System.IO.Path]::GetTempPath()) ("platform-template-" + [Guid]::NewGuid().ToString("N"))

try {
    & $renderScript `
        -RepoRoot $root `
        -OutputPath $tempOutput `
        -ValuesFile $publicValuesFile `
        -Version "0.0.0-check" `
        -Profile web-platform `
        -Applications nginx-web,httpbin,whoami `
        -DataServices redis `
        -FailOnUnresolvedToken

    $renderedChecks = @(
        "bundle-manifest.json",
        "DEPLOYMENT_BUNDLE.md",
        "k8s\400_platform_nginx-web\nginx-web.yaml",
        "k8s\400_platform_httpbin\httpbin.yaml",
        "k8s\400_platform_whoami\whoami.yaml",
        "services\httpbin\docker-compose.yaml",
        "services\nginx-web\docker-compose.yaml",
        "services\whoami\docker-compose.yaml"
    )

    foreach ($relativePath in $renderedChecks) {
        Assert-PathExists -Path (Join-Path $tempOutput $relativePath) -Label "rendered bundle path"
    }

    Assert-FileContains -Path (Join-Path $tempOutput "k8s\400_platform_nginx-web\config.yaml") -Pattern "Replace this landing page message with your own text\." -Label "Rendered nginx-web config"
    Assert-FileContains -Path (Join-Path $tempOutput "k8s\308_platform_gateway-api\httproute-nginx-web.yaml") -Pattern "nginx\.example\.com" -Label "Rendered gateway route"

    & $assetValidation `
        -RepoRoot $root `
        -RenderedPath $tempOutput `
        -ValuesFile $publicValuesFile `
        -Profile web-platform `
        -Applications nginx-web,httpbin,whoami `
        -DataServices redis `
        -SchemaValidator $SchemaValidator `
        -FailOnHighSecurityBaselineFinding

    & $renderMatrixValidation `
        -RepoRoot $root `
        -ValuesFile $publicValuesFile `
        -SchemaValidator $SchemaValidator `
        -FailOnHighSecurityBaselineFinding
}
finally {
    if (Test-Path -LiteralPath $tempOutput) {
        Remove-Item -LiteralPath $tempOutput -Recurse -Force
    }
}

Write-Host "Template validation completed."
