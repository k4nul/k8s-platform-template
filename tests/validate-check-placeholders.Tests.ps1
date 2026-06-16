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

$repoRoot = (Resolve-Path -Path (Join-Path $PSScriptRoot "..")).Path
$placeholderScript = Join-Path $repoRoot "scripts\check-placeholders.ps1"

Invoke-Test -Name "Placeholder scan excludes rendered out bundles during broad repository scans" -Body {
    $testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("placeholder-scan-test-" + [Guid]::NewGuid().ToString("N"))

    try {
        $renderedPath = Join-Path $testRoot "out\delivery\dev"
        New-Item -ItemType Directory -Path $renderedPath -Force | Out-Null
        Set-Content `
            -Path (Join-Path $renderedPath "platform-values.env") `
            -Value "REDIS_PASSWORD=change-me-redis-password`n" `
            -NoNewline

        $output = (& $placeholderScript -Path $testRoot 6>&1 3>&1 2>&1 | Out-String)

        Assert-Contains `
            -Content $output `
            -Expected "No tracked placeholder values were found." `
            -Message "Broad repository scans should keep generated out bundles excluded."
        Assert-NotContains `
            -Content $output `
            -Unexpected "platform-values.env" `
            -Message "Broad scans should not report generated out files."
    }
    finally {
        if (Test-Path -LiteralPath $testRoot) {
            Remove-Item -LiteralPath $testRoot -Recurse -Force
        }
    }
}

Invoke-Test -Name "Placeholder scan honors explicit rendered out bundle targets" -Body {
    $testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("placeholder-scan-test-" + [Guid]::NewGuid().ToString("N"))

    try {
        $renderedPath = Join-Path $testRoot "out\delivery\dev"
        New-Item -ItemType Directory -Path $renderedPath -Force | Out-Null
        Set-Content `
            -Path (Join-Path $renderedPath "platform-values.env") `
            -Value "REDIS_PASSWORD=change-me-redis-password`n" `
            -NoNewline

        $output = (& $placeholderScript -Path $renderedPath 6>&1 3>&1 2>&1 | Out-String)

        Assert-Contains `
            -Content $output `
            -Expected "Placeholder Password" `
            -Message "Explicit rendered bundle scans should report placeholder values."
        Assert-Contains `
            -Content $output `
            -Expected "Found 1 placeholder matches" `
            -Message "Explicit rendered bundle scans should report the rendered placeholder."
    }
    finally {
        if (Test-Path -LiteralPath $testRoot) {
            Remove-Item -LiteralPath $testRoot -Recurse -Force
        }
    }
}

if ($script:TestsFailed -gt 0) {
    throw ("{0} of {1} placeholder scan test(s) failed." -f $script:TestsFailed, $script:TestsRun)
}

Write-Host ("All {0} placeholder scan test(s) passed." -f $script:TestsRun)
