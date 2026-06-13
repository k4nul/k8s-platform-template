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

function Assert-False {
    param(
        [bool]$Condition,
        [string]$Message
    )

    if ($Condition) {
        throw $Message
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
$renderManifestsScript = Join-Path $repoRoot "k8s\render-manifests.ps1"

Invoke-Test -Name "Render manifests excludes configured optional YAML paths" -Body {
    $testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("render-manifests-test-" + [Guid]::NewGuid().ToString("N"))
    $sourceRoot = Join-Path $testRoot "source"
    $outputRoot = Join-Path $testRoot "output"

    try {
        New-Item -ItemType Directory -Path (Join-Path $sourceRoot "optional") -Force | Out-Null

        Set-Content `
            -Path (Join-Path $sourceRoot "deployment.yaml") `
            -Value "apiVersion: v1`nkind: ConfigMap`nmetadata:`n  name: kept`n" `
            -NoNewline

        Set-Content `
            -Path (Join-Path $sourceRoot "optional\manual-admin.yaml") `
            -Value "apiVersion: v1`nkind: ServiceAccount`nmetadata:`n  name: manual-admin`n" `
            -NoNewline

        & $renderManifestsScript `
            -InputPath $sourceRoot `
            -OutputPath $outputRoot `
            -ExcludeRelativePath @("optional\manual-admin.yaml")

        Assert-True `
            -Condition (Test-Path -Path (Join-Path $outputRoot "deployment.yaml") -PathType Leaf) `
            -Message "Normal manifest should be rendered."

        Assert-False `
            -Condition (Test-Path -Path (Join-Path $outputRoot "optional\manual-admin.yaml") -PathType Leaf) `
            -Message "Excluded optional manifest should not be rendered."
    }
    finally {
        if (Test-Path -Path $testRoot) {
            Remove-Item -LiteralPath $testRoot -Recurse -Force
        }
    }
}

if ($script:TestsFailed -gt 0) {
    throw ("{0} of {1} render manifest test(s) failed." -f $script:TestsFailed, $script:TestsRun)
}

Write-Host ("All {0} render manifest test(s) passed." -f $script:TestsRun)
