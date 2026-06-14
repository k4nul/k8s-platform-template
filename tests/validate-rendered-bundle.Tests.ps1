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

function New-TestRenderedBundle {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Root
    )

    $k8sRoot = Join-Path $Root "k8s"
    New-Item -ItemType Directory -Path $k8sRoot -Force | Out-Null
    Set-Content `
        -Path (Join-Path $k8sRoot "configmap.yaml") `
        -Value "apiVersion: v1`nkind: ConfigMap`nmetadata:`n  name: rendered-validator-test`n" `
        -NoNewline
}

function Invoke-WithEmptyToolPath {
    param(
        [Parameter(Mandatory = $true)]
        [scriptblock]$Body
    )

    $previousPath = $env:PATH
    $toolPath = Join-Path ([System.IO.Path]::GetTempPath()) ("rendered-validator-tools-" + [Guid]::NewGuid().ToString("N"))

    try {
        New-Item -ItemType Directory -Path $toolPath -Force | Out-Null
        $env:PATH = $toolPath
        & $Body
    }
    finally {
        $env:PATH = $previousPath
        if (Test-Path -LiteralPath $toolPath) {
            Remove-Item -LiteralPath $toolPath -Recurse -Force
        }
    }
}

$repoRoot = (Resolve-Path -Path (Join-Path $PSScriptRoot "..")).Path
$validateRenderedScript = Join-Path $repoRoot "scripts\validate-rendered-bundle.ps1"

Invoke-Test -Name "Rendered bundle validation skips schema validation without tools in non-strict mode" -Body {
    $testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("rendered-validator-test-" + [Guid]::NewGuid().ToString("N"))

    try {
        New-TestRenderedBundle -Root $testRoot

        Invoke-WithEmptyToolPath -Body {
            $output = (& $validateRenderedScript -RenderedPath $testRoot 3>&1 2>&1 | Out-String)
            Assert-Contains -Content $output -Expected "Skipping rendered manifest validation" -Message "Non-strict validation should explain the skipped schema gate."
        }
    }
    finally {
        if (Test-Path -LiteralPath $testRoot) {
            Remove-Item -LiteralPath $testRoot -Recurse -Force
        }
    }
}

Invoke-Test -Name "Rendered bundle validation fails without tools in strict mode" -Body {
    $testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("rendered-validator-test-" + [Guid]::NewGuid().ToString("N"))

    try {
        New-TestRenderedBundle -Root $testRoot

        $failed = Invoke-WithEmptyToolPath -Body {
            try {
                & $validateRenderedScript -RenderedPath $testRoot -Strict 3>&1 2>&1 | Out-String | Out-Null
                return $false
            }
            catch {
                Assert-Contains -Content $_.Exception.Message -Expected "kubeconform or kubectl is required" -Message "Strict validation should require an offline schema validator or kubectl."
                return $true
            }
        }

        Assert-True -Condition $failed -Message "Strict validation should fail when no rendered manifest validator is installed."
    }
    finally {
        if (Test-Path -LiteralPath $testRoot) {
            Remove-Item -LiteralPath $testRoot -Recurse -Force
        }
    }
}

if ($script:TestsFailed -gt 0) {
    throw ("{0} of {1} rendered bundle validator test(s) failed." -f $script:TestsFailed, $script:TestsRun)
}

Write-Host ("All {0} rendered bundle validator test(s) passed." -f $script:TestsRun)
