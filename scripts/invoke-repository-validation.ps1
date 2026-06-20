param(
    [string]$RepoRoot,
    [string]$EnvironmentPreset,
    [string]$EnvironmentPresetFile,
    [string]$ValuesFile,
    [string]$RenderedPath,
    [string]$HelmConfigFile,
    [string]$DockerRegistry = "",
    [string]$Version = "0.0.0-validation",
    [string]$Profile = "full",
    [string[]]$Applications = @(),
    [string[]]$DataServices = @(),
    [switch]$IncludeJenkins,
    [switch]$PrepareHelmRepos,
    [switch]$Strict,
    [switch]$ValidateCrdBackedResources,
    [ValidateSet("auto", "kubeconform", "kubectl")]
    [string]$SchemaValidator = "auto",
    [switch]$RequireBootstrapSecretsReady,
    [switch]$SkipTemplateValidation,
    [switch]$SkipWorkstationValidation,
    [switch]$SkipPlatformAssetValidation
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "environment-preset.ps1")
. (Join-Path $PSScriptRoot "repository-workflow-helpers.ps1")

if (-not $PSBoundParameters.ContainsKey("RepoRoot") -or -not $RepoRoot) {
    $RepoRoot = Join-Path $PSScriptRoot ".."
}

$root = (Resolve-Path -Path $RepoRoot).Path
$environmentPresetData = Get-EnvironmentPresetData `
    -RepoRoot $root `
    -EnvironmentPreset $EnvironmentPreset `
    -EnvironmentPresetFile $EnvironmentPresetFile

Set-ValueFromEnvironmentPreset `
    -Preset $environmentPresetData `
    -BoundParameters $PSBoundParameters `
    -Key "ValuesFile" `
    -Target ([ref]$ValuesFile)
if (
    -not $PSBoundParameters.ContainsKey("ValuesFile") -and
    $environmentPresetData -and
    $environmentPresetData.ContainsKey("ValidationValuesFile")
) {
    $ValuesFile = $environmentPresetData["ValidationValuesFile"]
}
Set-ValueFromEnvironmentPreset `
    -Preset $environmentPresetData `
    -BoundParameters $PSBoundParameters `
    -Key "RenderedPath" `
    -Target ([ref]$RenderedPath)
Set-ValueFromEnvironmentPreset `
    -Preset $environmentPresetData `
    -BoundParameters $PSBoundParameters `
    -Key "HelmConfigFile" `
    -Target ([ref]$HelmConfigFile)
Set-ValueFromEnvironmentPreset `
    -Preset $environmentPresetData `
    -BoundParameters $PSBoundParameters `
    -Key "DockerRegistry" `
    -Target ([ref]$DockerRegistry)
Set-ValueFromEnvironmentPreset `
    -Preset $environmentPresetData `
    -BoundParameters $PSBoundParameters `
    -Key "Version" `
    -Target ([ref]$Version)
Set-ValueFromEnvironmentPreset `
    -Preset $environmentPresetData `
    -BoundParameters $PSBoundParameters `
    -Key "Profile" `
    -Target ([ref]$Profile)
Set-ValueFromEnvironmentPreset `
    -Preset $environmentPresetData `
    -BoundParameters $PSBoundParameters `
    -Key "Applications" `
    -Target ([ref]$Applications) `
    -AsList
Set-ValueFromEnvironmentPreset `
    -Preset $environmentPresetData `
    -BoundParameters $PSBoundParameters `
    -Key "DataServices" `
    -Target ([ref]$DataServices) `
    -AsList
Set-ValueFromEnvironmentPreset `
    -Preset $environmentPresetData `
    -BoundParameters $PSBoundParameters `
    -Key "IncludeJenkins" `
    -Target ([ref]$IncludeJenkins) `
    -AsSwitch
Set-ValueFromEnvironmentPreset `
    -Preset $environmentPresetData `
    -BoundParameters $PSBoundParameters `
    -Key "PrepareHelmRepos" `
    -Target ([ref]$PrepareHelmRepos) `
    -AsSwitch
Set-ValueFromEnvironmentPreset `
    -Preset $environmentPresetData `
    -BoundParameters $PSBoundParameters `
    -Key "Strict" `
    -Target ([ref]$Strict) `
    -AsSwitch
Set-ValueFromEnvironmentPreset `
    -Preset $environmentPresetData `
    -BoundParameters $PSBoundParameters `
    -Key "ValidateCrdBackedResources" `
    -Target ([ref]$ValidateCrdBackedResources) `
    -AsSwitch
Set-ValueFromEnvironmentPreset `
    -Preset $environmentPresetData `
    -BoundParameters $PSBoundParameters `
    -Key "RequireBootstrapSecretsReady" `
    -Target ([ref]$RequireBootstrapSecretsReady) `
    -AsSwitch
Set-ValueFromEnvironmentPreset `
    -Preset $environmentPresetData `
    -BoundParameters $PSBoundParameters `
    -Key "SkipTemplateValidation" `
    -Target ([ref]$SkipTemplateValidation) `
    -AsSwitch
Set-ValueFromEnvironmentPreset `
    -Preset $environmentPresetData `
    -BoundParameters $PSBoundParameters `
    -Key "SkipWorkstationValidation" `
    -Target ([ref]$SkipWorkstationValidation) `
    -AsSwitch
Set-ValueFromEnvironmentPreset `
    -Preset $environmentPresetData `
    -BoundParameters $PSBoundParameters `
    -Key "SkipPlatformAssetValidation" `
    -Target ([ref]$SkipPlatformAssetValidation) `
    -AsSwitch

if (-not $ValuesFile) {
    $ValuesFile = "config\platform-values.env.example"
}

$resolvedValuesFile = Resolve-RepoPath -Root $root -Path $ValuesFile
$resolvedRenderedPath = ""
$resolvedHelmConfigFile = ""
$Applications = @(Normalize-List -Values $Applications)
$DataServices = @(Normalize-List -Values $DataServices)

if ($RenderedPath) {
    $resolvedRenderedPath = Resolve-RepoPath -Root $root -Path $RenderedPath
}

if ($HelmConfigFile) {
    $resolvedHelmConfigFile = Resolve-RepoPath -Root $root -Path $HelmConfigFile
}

if ($SkipPlatformAssetValidation -and $RequireBootstrapSecretsReady) {
    throw "-RequireBootstrapSecretsReady cannot be used together with -SkipPlatformAssetValidation."
}

if ($resolvedRenderedPath -and -not (Test-Path -Path $resolvedRenderedPath -PathType Container)) {
    throw ("Rendered bundle path does not exist: {0}" -f $resolvedRenderedPath)
}

$templateValidationScript = Join-Path $root "scripts\validate-template.ps1"
$workstationValidationScript = Join-Path $root "scripts\validate-workstation.ps1"
$platformAssetValidationScript = Join-Path $root "scripts\validate-platform-assets.ps1"

Write-Host "Repository validation suite"
Write-Host ("- Repo root: {0}" -f $root)
if ($environmentPresetData) {
    Write-Host ("- Environment preset: {0}" -f (Get-EnvironmentPresetDisplayText -Preset $environmentPresetData))
}
Write-Host ("- Values file: {0}" -f $resolvedValuesFile)
Write-Host ("- Profile: {0}" -f $Profile)
Write-Host ("- Applications: {0}" -f (Get-ListText -Values $Applications))
Write-Host ("- Data services: {0}" -f (Get-ListText -Values $DataServices))
Write-Host ("- Include Jenkins: {0}" -f [string]([bool]$IncludeJenkins))
if ($resolvedRenderedPath) {
    Write-Host ("- Rendered bundle path: {0}" -f $resolvedRenderedPath)
}
Write-Host ""

if (-not $SkipTemplateValidation) {
    Invoke-RepositoryWorkflowStep -Title "Repository template validation" -Action {
        & $templateValidationScript -RepoRoot $root -SchemaValidator $SchemaValidator
    }
}

if (-not $SkipWorkstationValidation) {
    Invoke-RepositoryWorkflowStep -Title "Workstation validation" -Action {
        & $workstationValidationScript -Strict
    }
}

if (-not $SkipPlatformAssetValidation) {
    $platformValidationParameters = @{
        RepoRoot = $root
        ValuesFile = $resolvedValuesFile
        DockerRegistry = $DockerRegistry
        Version = $Version
        Profile = $Profile
        Applications = @($Applications)
        DataServices = @($DataServices)
        IncludeJenkins = $IncludeJenkins
        PrepareHelmRepos = $PrepareHelmRepos
        Strict = $Strict
        ValidateCrdBackedResources = $ValidateCrdBackedResources
        SchemaValidator = $SchemaValidator
    }

    if ($resolvedRenderedPath) {
        $platformValidationParameters.RenderedPath = $resolvedRenderedPath
    }

    if ($resolvedHelmConfigFile) {
        $platformValidationParameters.HelmConfigFile = $resolvedHelmConfigFile
    }

    if ($RequireBootstrapSecretsReady) {
        $platformValidationParameters.RequireBootstrapSecretsReady = $true
    }

    Invoke-RepositoryWorkflowStep -Title "Rendered bundle validation" -Action {
        & $platformAssetValidationScript @platformValidationParameters
    }
}

Write-Host "Repository validation suite completed."
