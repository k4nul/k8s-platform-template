Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$script:TestsRun = 0
$script:TestsFailed = 0

function Assert-True {
    param(
        [bool]$Condition,
        [string]$Message
    )

    if (-not $Condition) {
        throw $Message
    }
}

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
        [string]$Unexpected,
        [string]$Message
    )

    if ($Content.Contains($Unexpected)) {
        throw ("{0} Did not expect to find '{1}'." -f $Message, $Unexpected)
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

function New-TestSecretBundle {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Root,

        [Parameter(Mandatory = $true)]
        [string]$SecretYaml
    )

    $k8sRoot = Join-Path $Root "k8s"
    New-Item -ItemType Directory -Path $k8sRoot -Force | Out-Null
    Set-Content `
        -Path (Join-Path $k8sRoot "secret.yaml") `
        -Value $SecretYaml `
        -NoNewline
}

function New-TestBootstrapSecretBundle {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Root,

        [Parameter(Mandatory = $true)]
        [string]$SecretYaml
    )

    $k8sRoot = Join-Path $Root "k8s"
    $bootstrapSecretRoot = Join-Path $Root "cluster-bootstrap\secrets\platform"
    New-Item -ItemType Directory -Path $k8sRoot -Force | Out-Null
    New-Item -ItemType Directory -Path $bootstrapSecretRoot -Force | Out-Null
    Set-Content `
        -Path (Join-Path $k8sRoot "configmap.yaml") `
        -Value "apiVersion: v1`nkind: ConfigMap`nmetadata:`n  name: bootstrap-scope-test`n" `
        -NoNewline
    Set-Content `
        -Path (Join-Path $bootstrapSecretRoot "secret.yaml") `
        -Value $SecretYaml `
        -NoNewline
}

$repoRoot = (Resolve-Path -Path (Join-Path $PSScriptRoot "..")).Path
$securityBaselineScript = Join-Path $repoRoot "scripts\validate-kubernetes-security-baseline.ps1"

Invoke-Test -Name "Security baseline allows placeholder-only Secret template values" -Body {
    $testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("security-baseline-test-" + [Guid]::NewGuid().ToString("N"))

    try {
        New-TestSecretBundle `
            -Root $testRoot `
            -SecretYaml "apiVersion: v1`nkind: Secret`nmetadata:`n  name: placeholder-secret`ntype: Opaque`nstringData:`n  password: change-me-placeholder-password`n  token: REPLACE_WITH_TOKEN`n"

        & $securityBaselineScript -Path $testRoot -FailOnMediumFinding 3>&1 2>&1 | Out-String | Out-Null
    }
    finally {
        if (Test-Path -LiteralPath $testRoot) {
            Remove-Item -LiteralPath $testRoot -Recurse -Force
        }
    }
}

Invoke-Test -Name "Security baseline reports concrete sensitive values without printing the value" -Body {
    $testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("security-baseline-test-" + [Guid]::NewGuid().ToString("N"))
    $secretValue = "actual-sensitive-value-123"

    try {
        New-TestSecretBundle `
            -Root $testRoot `
            -SecretYaml "apiVersion: v1`nkind: Secret`nmetadata:`n  name: concrete-secret`ntype: Opaque`nstringData:`n  password: $secretValue`n  username: platform_app`n"

        $output = (& $securityBaselineScript -Path $testRoot 3>&1 2>&1 | Out-String)

        Assert-Contains `
            -Content $output `
            -Expected "concrete-secret-template-value" `
            -Message "Concrete sensitive Secret values should be reported."
        Assert-NotContains `
            -Content $output `
            -Unexpected $secretValue `
            -Message "The finding output should not print the sensitive value."
    }
    finally {
        if (Test-Path -LiteralPath $testRoot) {
            Remove-Item -LiteralPath $testRoot -Recurse -Force
        }
    }
}

Invoke-Test -Name "Security baseline can fail on concrete sensitive Secret values" -Body {
    $testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("security-baseline-test-" + [Guid]::NewGuid().ToString("N"))

    try {
        New-TestSecretBundle `
            -Root $testRoot `
            -SecretYaml "apiVersion: v1`nkind: Secret`nmetadata:`n  name: concrete-secret`ntype: Opaque`ndata:`n  token: YWN0dWFsLXRva2Vu`n"

        $failed = $false
        try {
            & $securityBaselineScript -Path $testRoot -FailOnMediumFinding 3>&1 2>&1 | Out-String | Out-Null
        }
        catch {
            Assert-Contains `
                -Content $_.Exception.Message `
                -Expected "high or medium" `
                -Message "FailOnMediumFinding should block concrete sensitive Secret values."
            $failed = $true
        }

        Assert-True -Condition $failed -Message "FailOnMediumFinding should fail when a concrete sensitive Secret value is present."
    }
    finally {
        if (Test-Path -LiteralPath $testRoot) {
            Remove-Item -LiteralPath $testRoot -Recurse -Force
        }
    }
}

Invoke-Test -Name "Security baseline scans rendered bootstrap Secret templates" -Body {
    $testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("security-baseline-test-" + [Guid]::NewGuid().ToString("N"))

    try {
        New-TestBootstrapSecretBundle `
            -Root $testRoot `
            -SecretYaml "apiVersion: v1`nkind: Secret`nmetadata:`n  name: bootstrap-secret`ntype: Opaque`nstringData:`n  password: bootstrap-sensitive-value`n"

        $failed = $false
        try {
            & $securityBaselineScript -Path $testRoot -FailOnMediumFinding 3>&1 2>&1 | Out-String | Out-Null
        }
        catch {
            Assert-Contains `
                -Content $_.Exception.Message `
                -Expected "high or medium" `
                -Message "FailOnMediumFinding should include rendered bootstrap Secret templates."
            $failed = $true
        }

        Assert-True -Condition $failed -Message "Bootstrap Secret templates should be part of the security baseline scan."
    }
    finally {
        if (Test-Path -LiteralPath $testRoot) {
            Remove-Item -LiteralPath $testRoot -Recurse -Force
        }
    }
}

if ($script:TestsFailed -gt 0) {
    throw ("{0} of {1} Kubernetes security baseline test(s) failed." -f $script:TestsFailed, $script:TestsRun)
}

Write-Host ("All {0} Kubernetes security baseline test(s) passed." -f $script:TestsRun)
