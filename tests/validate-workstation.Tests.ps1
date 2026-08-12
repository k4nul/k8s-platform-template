Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$script:TestsRun = 0
$script:TestsFailed = 0
$validateWorkstation = Join-Path (Resolve-Path (Join-Path $PSScriptRoot "..")) "scripts\validate-workstation.ps1"

function Invoke-Test {
    param([string]$Name, [scriptblock]$Body)
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

function Invoke-WithTools {
    param([string[]]$Tools, [scriptblock]$Body)
    $previousPath = $env:PATH
    $toolPath = Join-Path ([System.IO.Path]::GetTempPath()) ("workstation-tools-" + [Guid]::NewGuid().ToString("N"))
    try {
        New-Item -ItemType Directory -Path $toolPath | Out-Null
        foreach ($tool in $Tools) {
            $toolFile = Join-Path $toolPath $tool
            Set-Content -Path $toolFile -Value "#!/bin/sh`nprintf '%s test-version\n' '$tool'"
            & chmod +x $toolFile
        }
        $env:PATH = $toolPath
        & $Body
    }
    finally {
        $env:PATH = $previousPath
        Remove-Item -LiteralPath $toolPath -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Invoke-Test -Name "auto accepts kubeconform with helm" -Body {
    Invoke-WithTools -Tools @("helm", "kubeconform") -Body {
        & $validateWorkstation -Strict 3>&1 2>&1 | Out-String | Out-Null
    }
}

Invoke-Test -Name "auto accepts kubectl with helm" -Body {
    Invoke-WithTools -Tools @("helm", "kubectl") -Body {
        & $validateWorkstation -Strict 3>&1 2>&1 | Out-String | Out-Null
    }
}

Invoke-Test -Name "explicit validator fails closed" -Body {
    Invoke-WithTools -Tools @("helm", "kubectl") -Body {
        try {
            & $validateWorkstation -SchemaValidator kubeconform -Strict 3>&1 2>&1 | Out-String | Out-Null
            throw "Expected explicit kubeconform requirement to fail."
        }
        catch {
            if (-not $_.Exception.Message.Contains("kubeconform")) { throw }
        }
    }
}

Invoke-Test -Name "missing requirements are grouped" -Body {
    Invoke-WithTools -Tools @() -Body {
        try {
            & $validateWorkstation -Strict 3>&1 2>&1 | Out-String | Out-Null
            throw "Expected missing workstation requirements to fail."
        }
        catch {
            if (-not $_.Exception.Message.Contains("helm; kubeconform or kubectl")) { throw }
        }
    }
}

Write-Host ("Tests run: {0}" -f $script:TestsRun)
Write-Host ("Tests failed: {0}" -f $script:TestsFailed)
if ($script:TestsFailed -gt 0) { exit 1 }
