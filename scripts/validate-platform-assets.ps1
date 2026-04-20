param(
    [string]$RepoRoot,
    [string]$RenderedPath,
    [string]$ValuesFile,
    [string]$HelmConfigFile,
    [string]$DockerRegistry = "",
    [string]$Version = "0.0.0-validate",
    [string]$Profile = "full",
    [string[]]$Applications = @(),
    [string[]]$DataServices = @(),
    [switch]$IncludeJenkins,
    [switch]$PrepareHelmRepos,
    [switch]$Strict,
    [switch]$ValidateCrdBackedResources,
    [switch]$RequireBootstrapSecretsReady,
    [switch]$KeepRenderedOutput
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if (-not $PSBoundParameters.ContainsKey("RepoRoot") -or -not $RepoRoot) {
    $RepoRoot = Join-Path $PSScriptRoot ".."
}

if (-not $PSBoundParameters.ContainsKey("ValuesFile") -or -not $ValuesFile) {
    $ValuesFile = Join-Path $PSScriptRoot "..\config\platform-values.env.example"
}

if (-not $PSBoundParameters.ContainsKey("HelmConfigFile") -or -not $HelmConfigFile) {
    $HelmConfigFile = Join-Path $PSScriptRoot "..\config\helm-releases.psd1"
}

$root = (Resolve-Path -Path $RepoRoot).Path
$renderScript = Join-Path $root "scripts\render-platform-assets.ps1"
$platformValuesValidationScript = Join-Path $root "scripts\validate-platform-values.ps1"
$selectionValidationScript = Join-Path $root "scripts\validate-platform-selection.ps1"
$validateRenderedScript = Join-Path $root "scripts\validate-rendered-bundle.ps1"
$validateHelmScript = Join-Path $root "scripts\validate-helm-values.ps1"
$createdTempOutput = $false

& $platformValuesValidationScript `
    -RepoRoot $root `
    -ValuesFile $ValuesFile `
    -Profile $Profile `
    -Applications $Applications `
    -DataServices $DataServices `
    -IncludeJenkins:$IncludeJenkins

& $selectionValidationScript `
    -RepoRoot $root `
    -Profile $Profile `
    -Applications $Applications `
    -DataServices $DataServices `
    -IncludeJenkins:$IncludeJenkins

if ($RequireBootstrapSecretsReady -and (-not $PSBoundParameters.ContainsKey("RenderedPath") -or -not $RenderedPath)) {
    throw "-RequireBootstrapSecretsReady requires -RenderedPath so the script can validate an already edited rendered bundle."
}

if (-not $PSBoundParameters.ContainsKey("RenderedPath") -or -not $RenderedPath) {
    $RenderedPath = Join-Path ([System.IO.Path]::GetTempPath()) ("platform-assets-" + [Guid]::NewGuid().ToString("N"))
    $createdTempOutput = $true

    & $renderScript `
        -RepoRoot $root `
        -OutputPath $RenderedPath `
        -DockerRegistry $DockerRegistry `
        -Version $Version `
        -ValuesFile $ValuesFile `
        -Profile $Profile `
        -Applications $Applications `
        -DataServices $DataServices `
        -IncludeJenkins:$IncludeJenkins `
        -FailOnUnresolvedToken
}

try {
    if ($RequireBootstrapSecretsReady) {
        $bootstrapCheckScript = Join-Path $RenderedPath "cluster-bootstrap\check-secret-templates.ps1"
        if (-not (Test-Path -Path $bootstrapCheckScript -PathType Leaf)) {
            throw ("Bootstrap placeholder check script not found: {0}" -f $bootstrapCheckScript)
        }

        $bootstrapCheckOutput = (& powershell -NoProfile -ExecutionPolicy Bypass -File $bootstrapCheckScript -BundleRoot $RenderedPath -FailOnMatch 2>&1 | Out-String)
        if ($LASTEXITCODE -ne 0) {
            throw ("Bootstrap secret placeholder validation failed.`n{0}" -f $bootstrapCheckOutput.Trim())
        }

        Write-Host "Bootstrap secret placeholder validation completed successfully."
    }

    & $validateRenderedScript `
        -RenderedPath $RenderedPath `
        -Strict:$Strict `
        -ValidateCrdBackedResources:$ValidateCrdBackedResources

    & $validateHelmScript `
        -RepoRoot $root `
        -InputRoot $RenderedPath `
        -HelmConfigFile $HelmConfigFile `
        -Profile $Profile `
        -Applications $Applications `
        -DataServices $DataServices `
        -IncludeJenkins:$IncludeJenkins `
        -PrepareRepos:$PrepareHelmRepos `
        -Strict:$Strict
}
finally {
    if ($createdTempOutput -and -not $KeepRenderedOutput -and (Test-Path -Path $RenderedPath)) {
        Remove-Item -LiteralPath $RenderedPath -Recurse -Force
    }
}

Write-Host "Platform asset validation completed."
