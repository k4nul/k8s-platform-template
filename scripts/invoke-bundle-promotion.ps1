param(
    [string]$RepoRoot,
    [string]$EnvironmentPreset,
    [string]$EnvironmentPresetFile,

    [string]$ArchivePath,

    [string]$ExtractPath,

    [switch]$CleanExtractPath,
    [switch]$PrepareHelmRepos,
    [switch]$IncludeDeferredComponents,
    [switch]$RequireBootstrapSecretsReady,
    [switch]$RequireBootstrapStatus,
    [switch]$SkipBundleValidation,
    [switch]$DeployBundle,
    [switch]$DeploymentDryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "environment-preset.ps1")

function Resolve-RepoPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Root,

        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if ([System.IO.Path]::IsPathRooted($Path)) {
        return [System.IO.Path]::GetFullPath($Path)
    }

    return [System.IO.Path]::GetFullPath((Join-Path $Root $Path))
}

function Invoke-WorkflowStep {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Title,

        [Parameter(Mandatory = $true)]
        [ScriptBlock]$Action
    )

    Write-Host ("== {0} ==" -f $Title)
    & $Action
    Write-Host ("Completed: {0}" -f $Title)
    Write-Host ""
}

function Test-UnsafeDeletionTarget {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$RepoPath
    )

    $resolvedPath = [System.IO.Path]::GetFullPath($Path).TrimEnd('\')
    $resolvedRepoPath = [System.IO.Path]::GetFullPath($RepoPath).TrimEnd('\')
    $pathRoot = [System.IO.Path]::GetPathRoot($resolvedPath).TrimEnd('\')

    if (-not $resolvedPath -or $resolvedPath.Length -le ($pathRoot.Length + 1)) {
        return $true
    }

    if ($resolvedPath -eq $resolvedRepoPath) {
        return $true
    }

    return $false
}

function Resolve-ExtractedBundleRoot {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ExtractRoot
    )

    $manifestMatches = @(
        Get-ChildItem -Path $ExtractRoot -Recurse -Filter "bundle-manifest.json" -File |
            Select-Object -ExpandProperty FullName
    )

    if ($manifestMatches.Count -eq 0) {
        throw ("No bundle-manifest.json file was found under the extracted path: {0}" -f $ExtractRoot)
    }

    $uniqueBundleRoots = @(
        $manifestMatches |
            ForEach-Object { Split-Path -Path $_ -Parent } |
            Sort-Object -Unique
    )

    if ($uniqueBundleRoots.Count -ne 1) {
        throw ("Expected exactly one extracted bundle root under {0}, but found {1}." -f $ExtractRoot, $uniqueBundleRoots.Count)
    }

    return $uniqueBundleRoots[0]
}

if (-not $PSBoundParameters.ContainsKey("RepoRoot") -or -not $RepoRoot) {
    $RepoRoot = Join-Path $PSScriptRoot ".."
}

$root = (Resolve-Path -Path $RepoRoot).Path
$environmentPresetData = Get-EnvironmentPresetData `
    -RepoRoot $root `
    -EnvironmentPreset $EnvironmentPreset `
    -EnvironmentPresetFile $EnvironmentPresetFile

Set-ValueFromEnvironmentPreset -Preset $environmentPresetData -BoundParameters $PSBoundParameters -Key "ArchivePath" -Target ([ref]$ArchivePath)
Set-ValueFromEnvironmentPreset -Preset $environmentPresetData -BoundParameters $PSBoundParameters -Key "PrepareHelmRepos" -Target ([ref]$PrepareHelmRepos) -AsSwitch
Set-ValueFromEnvironmentPreset -Preset $environmentPresetData -BoundParameters $PSBoundParameters -Key "IncludeDeferredComponents" -Target ([ref]$IncludeDeferredComponents) -AsSwitch
Set-ValueFromEnvironmentPreset -Preset $environmentPresetData -BoundParameters $PSBoundParameters -Key "RequireBootstrapSecretsReady" -Target ([ref]$RequireBootstrapSecretsReady) -AsSwitch
Set-ValueFromEnvironmentPreset -Preset $environmentPresetData -BoundParameters $PSBoundParameters -Key "RequireBootstrapStatus" -Target ([ref]$RequireBootstrapStatus) -AsSwitch
Set-ValueFromEnvironmentPreset -Preset $environmentPresetData -BoundParameters $PSBoundParameters -Key "SkipBundleValidation" -Target ([ref]$SkipBundleValidation) -AsSwitch
Set-ValueFromEnvironmentPreset -Preset $environmentPresetData -BoundParameters $PSBoundParameters -Key "DeployBundle" -Target ([ref]$DeployBundle) -AsSwitch
Set-ValueFromEnvironmentPreset -Preset $environmentPresetData -BoundParameters $PSBoundParameters -Key "DeploymentDryRun" -Target ([ref]$DeploymentDryRun) -AsSwitch
Set-ValueFromEnvironmentPreset -Preset $environmentPresetData -BoundParameters $PSBoundParameters -Key "CleanExtractPath" -Target ([ref]$CleanExtractPath) -AsSwitch

if (-not $PSBoundParameters.ContainsKey("ExtractPath") -and -not $ExtractPath -and $environmentPresetData) {
    if ($environmentPresetData.ContainsKey("PromotionExtractPath")) {
        $ExtractPath = $environmentPresetData["PromotionExtractPath"]
    }
    elseif ($environmentPresetData.ContainsKey("ExtractPath")) {
        $ExtractPath = $environmentPresetData["ExtractPath"]
    }
}

if (-not $ArchivePath) {
    throw "-ArchivePath is required unless it is provided by the selected environment preset."
}

if (-not $ExtractPath) {
    throw "-ExtractPath is required unless it is provided by the selected environment preset."
}

$resolvedArchivePath = Resolve-RepoPath -Root $root -Path $ArchivePath
$resolvedExtractPath = Resolve-RepoPath -Root $root -Path $ExtractPath

if (-not (Test-Path -Path $resolvedArchivePath -PathType Leaf)) {
    throw ("Bundle archive was not found: {0}" -f $resolvedArchivePath)
}

if ($CleanExtractPath -and (Test-UnsafeDeletionTarget -Path $resolvedExtractPath -RepoPath $root)) {
    throw ("Refusing to clean unsafe extract path: {0}" -f $resolvedExtractPath)
}

if (Test-Path -Path $resolvedExtractPath) {
    if (-not (Test-Path -Path $resolvedExtractPath -PathType Container)) {
        throw ("Extract path exists but is not a directory: {0}" -f $resolvedExtractPath)
    }

    $existingExtractEntries = @(Get-ChildItem -Path $resolvedExtractPath -Force)
    if ($existingExtractEntries.Count -gt 0) {
        if (-not $CleanExtractPath) {
            throw ("Extract path already exists and is not empty: {0}. Re-run with -CleanExtractPath to replace it." -f $resolvedExtractPath)
        }

        Remove-Item -LiteralPath $resolvedExtractPath -Recurse -Force
    }
}

New-Item -ItemType Directory -Path $resolvedExtractPath -Force | Out-Null

$resolvedBundleRoot = ""
$bundleValidateScript = ""
$bundleDeployScript = ""

Invoke-WorkflowStep -Title "Expand bundle archive" -Action {
    Expand-Archive -LiteralPath $resolvedArchivePath -DestinationPath $resolvedExtractPath -Force
    $script:resolvedBundleRoot = Resolve-ExtractedBundleRoot -ExtractRoot $resolvedExtractPath
    $script:bundleValidateScript = Join-Path $script:resolvedBundleRoot "validate-bundle.ps1"
    $script:bundleDeployScript = Join-Path $script:resolvedBundleRoot "deploy-bundle.ps1"

    foreach ($expectedFile in @("bundle-manifest.json", "validate-bundle.ps1", "deploy-bundle.ps1")) {
        $expectedPath = Join-Path $script:resolvedBundleRoot $expectedFile
        if (-not (Test-Path -Path $expectedPath -PathType Leaf)) {
            throw ("Expected promoted bundle file is missing after extraction: {0}" -f $expectedPath)
        }
    }
}

Write-Host "Bundle promotion workflow"
if ($environmentPresetData) {
    Write-Host ("- Environment preset: {0}" -f (Get-EnvironmentPresetDisplayText -Preset $environmentPresetData))
}
Write-Host ("- Archive path: {0}" -f $resolvedArchivePath)
Write-Host ("- Extract path: {0}" -f $resolvedExtractPath)
Write-Host ("- Resolved bundle root: {0}" -f $resolvedBundleRoot)
Write-Host ""

if (-not $SkipBundleValidation) {
    Invoke-WorkflowStep -Title "Promoted bundle validation" -Action {
        $bundleValidationParameters = @{
            BundleRoot = $resolvedBundleRoot
            PrepareHelmRepos = $PrepareHelmRepos
            IncludeDeferredComponents = $IncludeDeferredComponents
        }

        if ($RequireBootstrapSecretsReady) {
            $bundleValidationParameters.RequireBootstrapSecretsReady = $true
        }

        if ($RequireBootstrapStatus) {
            $bundleValidationParameters.RequireBootstrapStatus = $true
        }

        & $bundleValidateScript @bundleValidationParameters
    }
}

if ($DeployBundle) {
    Invoke-WorkflowStep -Title "Promoted bundle deployment" -Action {
        $deployParameters = @{
            BundleRoot = $resolvedBundleRoot
            PrepareHelmRepos = $PrepareHelmRepos
            DryRun = $DeploymentDryRun
            IncludeDeferredComponents = $IncludeDeferredComponents
        }

        & $bundleDeployScript @deployParameters
    }
}

Write-Host "Bundle promotion workflow completed."
