Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$script:TestsRun = 0
$script:TestsFailed = 0

function Assert-Contains {
    param(
        [string]$Content,
        [string]$Expected,
        [string]$Message
    )

    if (-not $Content.Contains($Expected)) {
        throw ("{0} Expected to find '{1}'." -f $Message, $Expected)
    }
}

function Invoke-Test {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [scriptblock]$Body
    )

    $script:TestsRun++
    try {
        & $Body
        Write-Host ("[PASS] {0}" -f $Name)
    }
    catch {
        $script:TestsFailed++
        Write-Host ("[FAIL] {0}" -f $Name)
        Write-Host ("       {0}" -f $_.Exception.Message)
    }
}

$repoRoot = (Resolve-Path -Path (Join-Path $PSScriptRoot "..")).Path
$renderScriptContent = Get-Content -Path (Join-Path $repoRoot "scripts\render-platform-assets.ps1") -Raw
$deliveryScriptContent = Get-Content -Path (Join-Path $repoRoot "scripts\invoke-bundle-delivery.ps1") -Raw
$assetValidationScriptContent = Get-Content -Path (Join-Path $repoRoot "scripts\validate-platform-assets.ps1") -Raw
$secretCatalogContent = Get-Content -Path (Join-Path $repoRoot "scripts\cluster-secret-catalog.ps1") -Raw
$secretPlanContent = Get-Content -Path (Join-Path $repoRoot "scripts\show-cluster-secret-plan.ps1") -Raw

Invoke-Test -Name "Render orchestration accepts and forwards Helm config" -Body {
    Assert-Contains `
        -Content $renderScriptContent `
        -Expected '[string]$HelmConfigFile' `
        -Message "Render orchestration should expose the Helm config boundary."
    Assert-Contains `
        -Content $renderScriptContent `
        -Expected '-HelmConfigFile $HelmConfigFile' `
        -Message "Render orchestration should forward Helm config to generated bundle helpers and reports."
}

Invoke-Test -Name "Delivery and validation forward custom Helm config into rendering" -Body {
    Assert-Contains `
        -Content $deliveryScriptContent `
        -Expected '$renderParameters.HelmConfigFile = $resolvedHelmConfigFile' `
        -Message "Bundle delivery should render with the same Helm config used by repository validation."
    Assert-Contains `
        -Content $assetValidationScriptContent `
        -Expected '-HelmConfigFile $HelmConfigFile' `
        -Message "Platform asset validation should render temporary bundles with the requested Helm config."
}

Invoke-Test -Name "Cluster secret plan shares Helm config with preflight data" -Body {
    Assert-Contains `
        -Content $secretPlanContent `
        -Expected '[string]$HelmConfigFile' `
        -Message "Cluster secret plan should accept the same Helm config as cluster preflight."
    Assert-Contains `
        -Content $secretCatalogContent `
        -Expected 'HelmConfigFile = $resolvedHelmConfigFile' `
        -Message "Cluster secret catalog should call preflight with the requested Helm config."
}

if ($script:TestsFailed -gt 0) {
    throw ("{0} of {1} render platform asset test(s) failed." -f $script:TestsFailed, $script:TestsRun)
}

Write-Host ("All {0} render platform asset test(s) passed." -f $script:TestsRun)
