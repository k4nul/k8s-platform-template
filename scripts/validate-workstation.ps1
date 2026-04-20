param(
    [string[]]$RequiredTools = @("kubectl", "helm"),
    [string[]]$OptionalTools = @("git", "docker", "python"),
    [string]$ProfileName = "platform validation",
    [switch]$Strict
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$report = New-Object System.Collections.Generic.List[object]

function Get-NormalizedToolList {
    param(
        [string[]]$Tools
    )

    return @(
        @($Tools) |
            ForEach-Object { [string]$_ } |
            ForEach-Object { $_.Trim().ToLowerInvariant() } |
            Where-Object { $_ } |
            Sort-Object -Unique
    )
}

function Get-ToolVersion {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    switch ($Name) {
        "pwsh"    { return $PSVersionTable.PSVersion.ToString() }
        "kubectl" { return (& kubectl version --client 2>$null | Out-String).Trim() }
        "helm"    { return (& helm version --short 2>$null | Out-String).Trim() }
        "git"     { return (& git --version 2>$null | Out-String).Trim() }
        "docker"  { return (& docker --version 2>$null | Out-String).Trim() }
        "python"  { return (& python --version 2>&1 | Out-String).Trim() }
        default   { return "" }
    }
}

$requiredTools = @(Get-NormalizedToolList -Tools $RequiredTools)
$optionalTools = @(
    Get-NormalizedToolList -Tools $OptionalTools |
        Where-Object { $requiredTools -notcontains $_ }
)

Write-Host ("Tool readiness profile: {0}" -f $ProfileName)
if ($requiredTools.Count -gt 0) {
    Write-Host ("Required tools: {0}" -f ($requiredTools -join ", "))
}
else {
    Write-Host "Required tools: none"
}

if ($optionalTools.Count -gt 0) {
    Write-Host ("Optional tools: {0}" -f ($optionalTools -join ", "))
}
else {
    Write-Host "Optional tools: none"
}
Write-Host ""

foreach ($tool in ($requiredTools + $optionalTools)) {
    $command = Get-Command $tool -ErrorAction SilentlyContinue
    $required = $requiredTools -contains $tool

    if ($null -ne $command) {
        $version = Get-ToolVersion -Name $tool
        $report.Add([PSCustomObject]@{
            Tool = $tool
            Required = $required
            Installed = $true
            Version = $version
        })
    }
    else {
        $report.Add([PSCustomObject]@{
            Tool = $tool
            Required = $required
            Installed = $false
            Version = ""
        })
    }
}

$report | Format-Table -AutoSize

$missingRequired = $report | Where-Object { $_.Required -and -not $_.Installed }

if ($missingRequired) {
    Write-Warning ("Missing required tools: {0}" -f (($missingRequired | Select-Object -ExpandProperty Tool) -join ", "))
    if ($Strict) {
        exit 1
    }
}
else {
    Write-Host "All required workstation tools are available."
}

Write-Host "For bundle-specific readiness, run .\scripts\show-validation-readiness.ps1 -Profile <name> -Format markdown."
Write-Host "For cluster-side prerequisites, run .\scripts\show-cluster-preflight.ps1 -Profile <name> -Format markdown."
Write-Host "For cluster secret inventory and example manifests, run .\scripts\show-cluster-secret-plan.ps1 -Profile <name> -Format markdown."
