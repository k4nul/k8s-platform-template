param(
    [string]$RepoRoot
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
    "config\README.md",
    "config\platform-values.env.example",
    "config\profiles\README.md",
    "services\README.md",
    "services\nginx-web\README.md",
    "services\httpbin\README.md",
    "services\whoami\README.md",
    "services\adminer\README.md",
    "k8s\README.md",
    "k8s\400_platform_nginx-web\README.md",
    "k8s\400_platform_httpbin\README.md",
    "k8s\400_platform_whoami\README.md",
    "k8s\401_platform_adminer\README.md",
    "scripts\README.md",
    "scripts\platform-catalog.ps1",
    "scripts\validate-service-builds.ps1",
    "scripts\show-service-build-plan.ps1",
    "scripts\validate-rendered-bundle.ps1",
    "scripts\render-matrix-catalog.ps1",
    "scripts\validate-render-matrix.ps1",
    "scripts\validate-kubernetes-security-baseline.ps1",
    "tests\validate-render-manifests.Tests.ps1",
    "tests\validate-rendered-bundle.Tests.ps1",
    "tests\validate-kubernetes-security-baseline.Tests.ps1",
    "tests\validate-render-matrix.Tests.ps1"
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
$renderedBundleTests = Join-Path $root "tests\validate-rendered-bundle.Tests.ps1"
$securityBaselineTests = Join-Path $root "tests\validate-kubernetes-security-baseline.Tests.ps1"
$renderMatrixTests = Join-Path $root "tests\validate-render-matrix.Tests.ps1"
$renderedBundleValidation = Join-Path $root "scripts\validate-rendered-bundle.ps1"
$securityBaselineValidation = Join-Path $root "scripts\validate-kubernetes-security-baseline.ps1"

Assert-FileContains -Path $renderedBundleValidation -Pattern "kubeconform" -Label "Rendered Kubernetes offline schema validation gate"
Assert-FileContains -Path $renderedBundleValidation -Pattern "kubectl apply --dry-run=client" -Label "Rendered Kubernetes kubectl dry-run validation gate"

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
    "NetworkPolicy"
)

foreach ($term in $securityBaselineTerms) {
    Assert-FileContains -Path $securityBaselineValidation -Pattern $term -Label "Kubernetes security baseline validation gate"
}

& $renderManifestsTests
& $renderedBundleTests
& $securityBaselineTests
& $renderMatrixTests
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
        -DataServices redis

    & $renderMatrixValidation `
        -RepoRoot $root `
        -ValuesFile $publicValuesFile
}
finally {
    if (Test-Path -LiteralPath $tempOutput) {
        Remove-Item -LiteralPath $tempOutput -Recurse -Force
    }
}

Write-Host "Template validation completed."
