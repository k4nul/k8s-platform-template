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

function Assert-NotContains {
    param(
        [string]$Content,
        [string]$Expected,
        [string]$Message
    )

    if ($Content.Contains($Expected)) {
        throw ("{0} Did not expect to find '{1}'." -f $Message, $Expected)
    }
}

function Assert-Equal {
    param(
        [object]$Expected,
        [object]$Actual,
        [string]$Message
    )

    if ($Expected -ne $Actual) {
        throw ("{0} Expected '{1}', got '{2}'." -f $Message, $Expected, $Actual)
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
$templateValidationScriptContent = Get-Content -Path (Join-Path $repoRoot "scripts\validate-template.ps1") -Raw
$bundleWriterScriptContent = Get-Content -Path (Join-Path $repoRoot "scripts\write-platform-bundle-files.ps1") -Raw
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

Invoke-Test -Name "Platform asset validation resolves bootstrap secret PowerShell host" -Body {
    Assert-Contains `
        -Content $assetValidationScriptContent `
        -Expected 'function Resolve-PowerShellHostCommand' `
        -Message "Platform asset validation should centralize PowerShell host resolution."
    Assert-Contains `
        -Content $assetValidationScriptContent `
        -Expected 'Get-Command -Name $candidate -CommandType Application' `
        -Message "Bootstrap secret readiness should fall back to pwsh or powershell on PATH."
    Assert-Contains `
        -Content $assetValidationScriptContent `
        -Expected '$bootstrapPowerShellHost = Resolve-PowerShellHostCommand' `
        -Message "Bootstrap secret readiness should resolve the host before invoking the generated helper."
    Assert-Contains `
        -Content $assetValidationScriptContent `
        -Expected '& $bootstrapPowerShellHost -NoProfile -ExecutionPolicy Bypass -File $bootstrapCheckScript' `
        -Message "Bootstrap secret readiness should invoke the generated helper through the resolved host."
    Assert-NotContains `
        -Content $assetValidationScriptContent `
        -Expected '& powershell -NoProfile -ExecutionPolicy Bypass -File $bootstrapCheckScript' `
        -Message "Bootstrap secret readiness should not hardcode Windows PowerShell."
}

Invoke-Test -Name "Template validation forwards rendered schema and high security gates" -Body {
    $schemaForwardCount = ([regex]::Matches($templateValidationScriptContent, [regex]::Escape("-SchemaValidator `$SchemaValidator"))).Count
    $highSecurityForwardCount = ([regex]::Matches($templateValidationScriptContent, [regex]::Escape("-FailOnHighSecurityBaselineFinding"))).Count

    Assert-Equal `
        -Expected 2 `
        -Actual $schemaForwardCount `
        -Message "Template validation should forward schema validator selection to smoke and matrix rendered checks."
    Assert-Equal `
        -Expected 2 `
        -Actual $highSecurityForwardCount `
        -Message "Template validation should make smoke and matrix rendered security high findings fail."
    Assert-Contains `
        -Content $templateValidationScriptContent `
        -Expected '-RenderedPath $tempOutput' `
        -Message "Template validation should validate the smoke-rendered bundle."
    Assert-Contains `
        -Content $templateValidationScriptContent `
        -Expected '-ValuesFile $publicValuesFile' `
        -Message "Template validation should keep rendered checks on public values."
}

Invoke-Test -Name "Template validation asserts public-default transition metadata" -Body {
    Assert-Contains `
        -Content $templateValidationScriptContent `
        -Expected 'function Assert-PhaseTransitionMetadata' `
        -Message "Template validation should centralize phase transition metadata checks."
    Assert-Contains `
        -Content $templateValidationScriptContent `
        -Expected 'public-default-security-review' `
        -Message "Template validation should keep the active public-default review phase covered."
    Assert-Contains `
        -Content $templateValidationScriptContent `
        -Expected 'next_phase ''template-maintenance''' `
        -Message "Template validation should require the documented public-default handoff target."
    Assert-Contains `
        -Content $templateValidationScriptContent `
        -Expected 'transition.transition_validation_command' `
        -Message "Template validation should require an automated transition validation command."
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

Invoke-Test -Name "Generated bundle validation supports offline schema validator selection" -Body {
    Assert-Contains `
        -Content $bundleWriterScriptContent `
        -Expected '[ValidateSet("auto", "kubeconform", "kubectl")]' `
        -Message "Generated bundle validation should expose the same schema validator choices as repository validation."
    Assert-Contains `
        -Content $bundleWriterScriptContent `
        -Expected '[string]$SchemaValidator = "auto"' `
        -Message "Generated bundle validation should default to automatic validator selection."
    Assert-Contains `
        -Content $bundleWriterScriptContent `
        -Expected 'Get-RawManifestValidator -RequestedValidator $SchemaValidator' `
        -Message "Generated bundle validation should resolve the requested raw manifest validator."
    Assert-Contains `
        -Content $bundleWriterScriptContent `
        -Expected 'kubeconform -strict -summary -ignore-missing-schemas' `
        -Message "Generated bundle validation should support offline kubeconform schema validation."
    Assert-Contains `
        -Content $bundleWriterScriptContent `
        -Expected '& $applyScript -BundleRoot $BundleRoot -DryRun' `
        -Message "Generated bundle validation should keep the kubectl dry-run fallback path."
}

if ($script:TestsFailed -gt 0) {
    throw ("{0} of {1} render platform asset test(s) failed." -f $script:TestsFailed, $script:TestsRun)
}

Write-Host ("All {0} render platform asset test(s) passed." -f $script:TestsRun)
