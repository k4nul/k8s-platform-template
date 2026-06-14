param(
    [string]$RepoRoot,
    [string]$ValuesFile,
    [switch]$Strict,
    [switch]$ValidateCrdBackedResources,
    [switch]$FailOnHighSecurityBaselineFinding
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "render-matrix-catalog.ps1")

if (-not $PSBoundParameters.ContainsKey("RepoRoot") -or -not $RepoRoot) {
    $RepoRoot = Join-Path $PSScriptRoot ".."
}

$root = (Resolve-Path -Path $RepoRoot).Path
$defaultValuesFile = "config\platform-values.env.example"
$assetValidation = Join-Path $root "scripts\validate-platform-assets.ps1"
$matrixEntries = @(
    Get-RenderValidationMatrix `
        -Root $root `
        -DefaultValuesFile $defaultValuesFile `
        -ValuesFile $ValuesFile
)

Write-Host "Render validation matrix"
Write-Host ("- Repository root: {0}" -f $root)
Write-Host ("- Matrix entries: {0}" -f $matrixEntries.Count)
Write-Host ""

foreach ($entry in $matrixEntries) {
    $resolvedValuesFile = Resolve-RenderMatrixRepoPath -Root $root -Path $entry.ValuesFile
    if (-not (Test-Path -Path $resolvedValuesFile -PathType Leaf)) {
        throw ("Render matrix values file was not found for {0} '{1}': {2}" -f $entry.Scope, $entry.Name, $resolvedValuesFile)
    }

    Write-Host ("== Render matrix {0}: {1} ==" -f $entry.Scope, $entry.Name)
    Write-Host ("- Values file: {0}" -f $resolvedValuesFile)
    Write-Host ("- Profile: {0}" -f $entry.Profile)
    Write-Host ("- Applications: {0}" -f (Get-RenderMatrixListText -Values @($entry.Applications)))
    Write-Host ("- Data services: {0}" -f (Get-RenderMatrixListText -Values @($entry.DataServices)))

    & $assetValidation `
        -RepoRoot $root `
        -ValuesFile $resolvedValuesFile `
        -Version $entry.Version `
        -Profile $entry.Profile `
        -Applications @($entry.Applications) `
        -DataServices @($entry.DataServices) `
        -IncludeJenkins:$entry.IncludeJenkins `
        -Strict:$Strict `
        -ValidateCrdBackedResources:$ValidateCrdBackedResources `
        -FailOnHighSecurityBaselineFinding:$FailOnHighSecurityBaselineFinding

    Write-Host ("Completed render matrix {0}: {1}" -f $entry.Scope, $entry.Name)
    Write-Host ""
}

Write-Host "Render validation matrix completed."
