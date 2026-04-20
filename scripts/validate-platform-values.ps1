param(
    [string]$RepoRoot,
    [string]$ValuesFile,
    [string]$Profile = "full",
    [string[]]$Applications = @(),
    [string[]]$DataServices = @(),
    [switch]$IncludeJenkins,
    [switch]$RequireCatalogComplete
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "platform-values-catalog.ps1")

if (-not $PSBoundParameters.ContainsKey("RepoRoot") -or -not $RepoRoot) {
    $RepoRoot = Join-Path $PSScriptRoot ".."
}

if (-not $PSBoundParameters.ContainsKey("ValuesFile") -or -not $ValuesFile) {
    $ValuesFile = Join-Path $PSScriptRoot "..\config\platform-values.env.example"
}

$planData = Get-PlatformValuePlanData `
    -RepoRoot $RepoRoot `
    -Profile $Profile `
    -Applications $Applications `
    -DataServices $DataServices `
    -IncludeJenkins:$IncludeJenkins `
    -ValuesFile $ValuesFile

$catalogMap = Get-PlatformValueCatalogMap -RepoRoot $RepoRoot
$errors = New-Object System.Collections.Generic.List[string]

foreach ($tokenName in @($planData.MissingCatalogKeys)) {
    $errors.Add("Required platform value is missing from config/platform-values-catalog.psd1: $tokenName") | Out-Null
}

foreach ($tokenName in @($planData.MissingValuesFileKeys)) {
    $errors.Add("Values file is missing required key for the selected bundle: $tokenName") | Out-Null
}

foreach ($tokenName in @($planData.UnknownValuesFileKeys)) {
    $errors.Add("Values file contains a key that is not cataloged in config/platform-values-catalog.psd1: $tokenName") | Out-Null
}

if ($RequireCatalogComplete) {
    foreach ($tokenName in @($catalogMap.Keys | Sort-Object)) {
        if ($planData.ValuesFileKeys -notcontains $tokenName) {
            $errors.Add("Values file is missing cataloged key: $tokenName") | Out-Null
        }
    }
}

if ($errors.Count -gt 0) {
    Write-Error ("Platform values validation failed:`n- {0}" -f ($errors -join "`n- "))
}

Write-Host "Platform values validation completed."
