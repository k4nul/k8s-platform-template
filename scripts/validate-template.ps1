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

$expectedPaths = @(
    "README.md",
    "QUICKSTART.md",
    "DEPLOYMENT_ENV.md",
    "ENV_CHECKLIST.md",
    "config\README.md",
    "config\platform-values.env.example",
    "config\platform-values.dev.env",
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
    "jenkins\README.md",
    "jenkins\JOB_BLUEPRINT.md",
    "scripts\platform-catalog.ps1",
    "scripts\validate-service-builds.ps1",
    "scripts\show-service-build-plan.ps1"
)

foreach ($relativePath in $expectedPaths) {
    Assert-PathExists -Path (Join-Path $root $relativePath) -Label "expected repository path"
}

$serviceCatalogValidation = Join-Path $root "scripts\validate-service-catalogs.ps1"
$serviceBuildValidation = Join-Path $root "scripts\validate-service-builds.ps1"
$serviceConfigValidation = Join-Path $root "scripts\validate-service-config-artifacts.ps1"
$servicePipelineValidation = Join-Path $root "scripts\validate-service-pipelines.ps1"
$serviceRuntimeValidation = Join-Path $root "scripts\validate-service-runtime.ps1"
$selectionValidation = Join-Path $root "scripts\validate-platform-selection.ps1"
$valueValidation = Join-Path $root "scripts\validate-platform-values.ps1"
$renderScript = Join-Path $root "scripts\render-platform-assets.ps1"
$assetValidation = Join-Path $root "scripts\validate-platform-assets.ps1"
$jenkinsPlanScript = Join-Path $root "scripts\show-jenkins-job-plan.ps1"
$jenkinsDslScript = Join-Path $root "scripts\export-jenkins-job-dsl.ps1"

& $serviceCatalogValidation -RepoRoot $root
& $serviceBuildValidation -RepoRoot $root
& $serviceConfigValidation -RepoRoot $root -ValuesFile (Join-Path $root "config\platform-values.dev.env")
& $servicePipelineValidation -RepoRoot $root
& $serviceRuntimeValidation -RepoRoot $root
& $selectionValidation -RepoRoot $root -Profile web-platform -Applications nginx-web,httpbin,whoami -DataServices redis
& $valueValidation -RepoRoot $root -ValuesFile (Join-Path $root "config\platform-values.dev.env") -Profile web-platform -Applications nginx-web,httpbin,whoami -DataServices redis

$tempOutput = Join-Path ([System.IO.Path]::GetTempPath()) ("platform-template-" + [Guid]::NewGuid().ToString("N"))
$tempDslPath = Join-Path ([System.IO.Path]::GetTempPath()) ("platform-template-dsl-" + [Guid]::NewGuid().ToString("N") + ".groovy")

try {
    & $renderScript `
        -RepoRoot $root `
        -OutputPath $tempOutput `
        -ValuesFile (Join-Path $root "config\platform-values.dev.env") `
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
        "services\whoami\docker-compose.yaml",
        "jenkins\JOB_PLAN.md",
        "jenkins\seed-job-dsl.groovy"
    )

    foreach ($relativePath in $renderedChecks) {
        Assert-PathExists -Path (Join-Path $tempOutput $relativePath) -Label "rendered bundle path"
    }

    Assert-FileContains -Path (Join-Path $tempOutput "k8s\400_platform_nginx-web\config.yaml") -Pattern "Development bundle for the generic Kubernetes platform template\." -Label "Rendered nginx-web config"
    Assert-FileContains -Path (Join-Path $tempOutput "k8s\308_platform_gateway-api\httproute-nginx-web.yaml") -Pattern "nginx\.dev\.example\.com" -Label "Rendered gateway route"

    & $assetValidation `
        -RepoRoot $root `
        -RenderedPath $tempOutput `
        -ValuesFile (Join-Path $root "config\platform-values.dev.env") `
        -Profile web-platform `
        -Applications nginx-web,httpbin,whoami `
        -DataServices redis

    $jenkinsPlanJson = (& $jenkinsPlanScript -RepoRoot $root -EnvironmentPreset dev -Format json | Out-String).Trim()
    if (-not $jenkinsPlanJson) {
        throw "show-jenkins-job-plan.ps1 returned no JSON output."
    }

    $jenkinsPlan = $jenkinsPlanJson | ConvertFrom-Json
    if (@($jenkinsPlan.ServiceJobs).Count -ne 0) {
        throw "Expected zero service jobs for the public-image sample services."
    }

    & $jenkinsDslScript -RepoRoot $root -EnvironmentPreset dev -OutputPath $tempDslPath
    Assert-PathExists -Path $tempDslPath -Label "generated Jenkins Job DSL"
    Assert-FileContains -Path $tempDslPath -Pattern "pipelineJob\('platform/dev/repository-validation'\)" -Label "Generated Jenkins Job DSL"
}
finally {
    if (Test-Path -LiteralPath $tempOutput) {
        Remove-Item -LiteralPath $tempOutput -Recurse -Force
    }

    if (Test-Path -LiteralPath $tempDslPath) {
        Remove-Item -LiteralPath $tempDslPath -Force
    }
}

Write-Host "Template validation completed."
