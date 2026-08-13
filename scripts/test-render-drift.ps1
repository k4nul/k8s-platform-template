Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$script:TestsRun = 0
$script:TestsFailed = 0
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$compareScript = Join-Path $repoRoot "scripts\compare-rendered-environments.ps1"
$pwsh = (Get-Command pwsh -ErrorAction Stop).Source

function Invoke-Test {
    param([Parameter(Mandatory = $true)][string]$Name, [Parameter(Mandatory = $true)][scriptblock]$Body)
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

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

function Write-Manifest {
    param([string]$Root, [string]$Name, [string]$Content)
    New-Item -ItemType Directory -Path $Root -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $Root $Name) -Value $Content -NoNewline
}

function Invoke-Comparison {
    param([string]$Baseline, [string]$Candidate, [string]$ApprovalFile)
    $arguments = @("-NoProfile", "-File", $compareScript, "-BaselinePath", $Baseline, "-CandidatePath", $Candidate)
    if ($ApprovalFile) { $arguments += @("-ApprovalFile", $ApprovalFile) }
    $output = (& $pwsh @arguments 2>&1 | Out-String)
    return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = $output }
}

$deploymentBaseline = @"
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api
  namespace: platform
spec:
  template:
    spec:
      containers:
        - name: api
          image: example/api:1
          securityContext:
            privileged: false
"@
$deploymentPrivileged = $deploymentBaseline.Replace("privileged: false", "privileged: true")
$configMap = "apiVersion: v1`nkind: ConfigMap`nmetadata:`n  name: settings`n  namespace: platform`n"
$service = "apiVersion: v1`nkind: Service`nmetadata:`n  name: api`n  namespace: platform`n"

Invoke-Test -Name "Identical rendered environments are clean" -Body {
    $root = Join-Path ([System.IO.Path]::GetTempPath()) ("render-drift-clean-" + [Guid]::NewGuid().ToString("N"))
    try {
        $baseline = Join-Path $root "baseline"
        $candidate = Join-Path $root "candidate"
        Write-Manifest -Root $baseline -Name "deployment.yaml" -Content $deploymentBaseline
        Write-Manifest -Root $candidate -Name "deployment.yaml" -Content $deploymentBaseline
        $result = Invoke-Comparison -Baseline $baseline -Candidate $candidate
        Assert-True ($result.ExitCode -eq 0) $result.Output
        Assert-True ($result.Output.Contains("differences=0 unexpected=0")) "Clean comparison did not report zero drift."
    }
    finally { if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force } }
}

Invoke-Test -Name "Unapproved security-sensitive drift is rejected" -Body {
    $root = Join-Path ([System.IO.Path]::GetTempPath()) ("render-drift-reject-" + [Guid]::NewGuid().ToString("N"))
    try {
        $baseline = Join-Path $root "baseline"
        $candidate = Join-Path $root "candidate"
        Write-Manifest -Root $baseline -Name "deployment.yaml" -Content $deploymentBaseline
        Write-Manifest -Root $candidate -Name "deployment.yaml" -Content $deploymentPrivileged
        $result = Invoke-Comparison -Baseline $baseline -Candidate $candidate
        Assert-True ($result.ExitCode -ne 0) "Unapproved privileged drift unexpectedly passed."
        Assert-True ($result.Output.Contains("fields=privileged")) ("Rejected output did not identify the privileged field: {0}" -f $result.Output)
    }
    finally { if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force } }
}

Invoke-Test -Name "Explicit field-scoped drift approval passes" -Body {
    $root = Join-Path ([System.IO.Path]::GetTempPath()) ("render-drift-approve-" + [Guid]::NewGuid().ToString("N"))
    try {
        $baseline = Join-Path $root "baseline"
        $candidate = Join-Path $root "candidate"
        $approval = Join-Path $root "approved-differences.json"
        Write-Manifest -Root $baseline -Name "deployment.yaml" -Content $deploymentBaseline
        Write-Manifest -Root $candidate -Name "deployment.yaml" -Content $deploymentPrivileged
        [pscustomobject]@{
            schemaVersion = "1.0.0"
            approvedDifferences = @(
                [pscustomobject]@{
                    type = "modified"
                    resource = "Deployment/platform/api"
                    fields = @("privileged")
                    reason = "Fixture verifies an explicit review boundary."
                }
            )
        } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $approval
        $result = Invoke-Comparison -Baseline $baseline -Candidate $candidate -ApprovalFile $approval
        Assert-True ($result.ExitCode -eq 0) $result.Output
        Assert-True ($result.Output.Contains("[APPROVED] modified Deployment/platform/api")) "Approved drift was not reported."
    }
    finally { if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force } }
}

Invoke-Test -Name "Stale drift approvals are rejected" -Body {
    $root = Join-Path ([System.IO.Path]::GetTempPath()) ("render-drift-stale-" + [Guid]::NewGuid().ToString("N"))
    try {
        $baseline = Join-Path $root "baseline"
        $candidate = Join-Path $root "candidate"
        $approval = Join-Path $root "approved-differences.json"
        Write-Manifest -Root $baseline -Name "deployment.yaml" -Content $deploymentBaseline
        Write-Manifest -Root $candidate -Name "deployment.yaml" -Content $deploymentBaseline
        [pscustomobject]@{
            schemaVersion = "1.0.0"
            approvedDifferences = @(
                [pscustomobject]@{
                    type = "modified"
                    resource = "Deployment/platform/api"
                    fields = @("privileged")
                    reason = "Fixture approval must not outlive the matching drift."
                }
            )
        } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $approval
        $result = Invoke-Comparison -Baseline $baseline -Candidate $candidate -ApprovalFile $approval
        Assert-True ($result.ExitCode -ne 0) "Stale approval unexpectedly passed."
        Assert-True ($result.Output.Contains("stale or mismatched entries")) ("Stale approval failure was not explicit: {0}" -f $result.Output)
    }
    finally { if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force } }
}

Invoke-Test -Name "Resource additions and removals are rejected" -Body {
    $root = Join-Path ([System.IO.Path]::GetTempPath()) ("render-drift-resources-" + [Guid]::NewGuid().ToString("N"))
    try {
        $baseline = Join-Path $root "baseline"
        $candidate = Join-Path $root "candidate"
        Write-Manifest -Root $baseline -Name "deployment.yaml" -Content $deploymentBaseline
        Write-Manifest -Root $baseline -Name "configmap.yaml" -Content $configMap
        Write-Manifest -Root $candidate -Name "deployment.yaml" -Content $deploymentBaseline
        Write-Manifest -Root $candidate -Name "service.yaml" -Content $service
        $result = Invoke-Comparison -Baseline $baseline -Candidate $candidate
        Assert-True ($result.ExitCode -ne 0) "Unexpected resource inventory drift passed."
        Assert-True ($result.Output.Contains("removed ConfigMap/platform/settings")) ("Removed resource was not reported: {0}" -f $result.Output)
        Assert-True ($result.Output.Contains("added Service/platform/api")) ("Added resource was not reported: {0}" -f $result.Output)
    }
    finally { if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force } }
}

if ($script:TestsFailed -gt 0) {
    throw ("Render drift tests failed: {0}/{1}" -f $script:TestsFailed, $script:TestsRun)
}

Write-Host ("Render drift tests passed: {0}" -f $script:TestsRun)
