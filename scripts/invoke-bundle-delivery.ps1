param(
    [string]$RepoRoot,
    [string]$EnvironmentPreset,
    [string]$EnvironmentPresetFile,

    [string]$OutputPath,

    [string]$ValuesFile,
    [string]$HelmConfigFile,
    [string]$ArchivePath,
    [string]$DockerRegistry = "",
    [string]$Version = "0.0.0-delivery",
    [string]$Profile = "full",
    [string[]]$Applications = @(),
    [string[]]$DataServices = @(),
    [switch]$IncludeJenkins,
    [switch]$PrepareHelmRepos,
    [switch]$IncludeDeferredComponents,
    [switch]$RequireBootstrapSecretsReady,
    [switch]$RequireBootstrapStatus,
    [switch]$CleanOutput,
    [switch]$OverwriteArchive,
    [switch]$SkipRepositoryValidation,
    [switch]$SkipTemplateValidation,
    [switch]$SkipWorkstationValidation,
    [switch]$SkipBundleValidation,
    [switch]$SkipArchive,
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

function Normalize-List {
    param(
        [string[]]$Values = @()
    )

    $normalized = New-Object System.Collections.Generic.List[string]

    foreach ($value in @($Values)) {
        if ($null -eq $value) {
            continue
        }

        foreach ($entry in ($value -split ",")) {
            $trimmed = $entry.Trim()
            if ($trimmed) {
                $normalized.Add($trimmed) | Out-Null
            }
        }
    }

    return @($normalized)
}

function Get-ListText {
    param(
        [string[]]$Values = @(),
        [string]$Empty = "none"
    )

    if (@($Values).Count -gt 0) {
        return (@($Values) -join ", ")
    }

    return $Empty
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

if (-not $PSBoundParameters.ContainsKey("RepoRoot") -or -not $RepoRoot) {
    $RepoRoot = Join-Path $PSScriptRoot ".."
}

$root = (Resolve-Path -Path $RepoRoot).Path
$environmentPresetData = Get-EnvironmentPresetData `
    -RepoRoot $root `
    -EnvironmentPreset $EnvironmentPreset `
    -EnvironmentPresetFile $EnvironmentPresetFile

Set-ValueFromEnvironmentPreset -Preset $environmentPresetData -BoundParameters $PSBoundParameters -Key "OutputPath" -Target ([ref]$OutputPath)
Set-ValueFromEnvironmentPreset -Preset $environmentPresetData -BoundParameters $PSBoundParameters -Key "ValuesFile" -Target ([ref]$ValuesFile)
Set-ValueFromEnvironmentPreset -Preset $environmentPresetData -BoundParameters $PSBoundParameters -Key "HelmConfigFile" -Target ([ref]$HelmConfigFile)
Set-ValueFromEnvironmentPreset -Preset $environmentPresetData -BoundParameters $PSBoundParameters -Key "ArchivePath" -Target ([ref]$ArchivePath)
Set-ValueFromEnvironmentPreset -Preset $environmentPresetData -BoundParameters $PSBoundParameters -Key "DockerRegistry" -Target ([ref]$DockerRegistry)
Set-ValueFromEnvironmentPreset -Preset $environmentPresetData -BoundParameters $PSBoundParameters -Key "Version" -Target ([ref]$Version)
Set-ValueFromEnvironmentPreset -Preset $environmentPresetData -BoundParameters $PSBoundParameters -Key "Profile" -Target ([ref]$Profile)
Set-ValueFromEnvironmentPreset -Preset $environmentPresetData -BoundParameters $PSBoundParameters -Key "Applications" -Target ([ref]$Applications) -AsList
Set-ValueFromEnvironmentPreset -Preset $environmentPresetData -BoundParameters $PSBoundParameters -Key "DataServices" -Target ([ref]$DataServices) -AsList
Set-ValueFromEnvironmentPreset -Preset $environmentPresetData -BoundParameters $PSBoundParameters -Key "IncludeJenkins" -Target ([ref]$IncludeJenkins) -AsSwitch
Set-ValueFromEnvironmentPreset -Preset $environmentPresetData -BoundParameters $PSBoundParameters -Key "PrepareHelmRepos" -Target ([ref]$PrepareHelmRepos) -AsSwitch
Set-ValueFromEnvironmentPreset -Preset $environmentPresetData -BoundParameters $PSBoundParameters -Key "IncludeDeferredComponents" -Target ([ref]$IncludeDeferredComponents) -AsSwitch
Set-ValueFromEnvironmentPreset -Preset $environmentPresetData -BoundParameters $PSBoundParameters -Key "RequireBootstrapSecretsReady" -Target ([ref]$RequireBootstrapSecretsReady) -AsSwitch
Set-ValueFromEnvironmentPreset -Preset $environmentPresetData -BoundParameters $PSBoundParameters -Key "RequireBootstrapStatus" -Target ([ref]$RequireBootstrapStatus) -AsSwitch
Set-ValueFromEnvironmentPreset -Preset $environmentPresetData -BoundParameters $PSBoundParameters -Key "CleanOutput" -Target ([ref]$CleanOutput) -AsSwitch
Set-ValueFromEnvironmentPreset -Preset $environmentPresetData -BoundParameters $PSBoundParameters -Key "OverwriteArchive" -Target ([ref]$OverwriteArchive) -AsSwitch
Set-ValueFromEnvironmentPreset -Preset $environmentPresetData -BoundParameters $PSBoundParameters -Key "SkipRepositoryValidation" -Target ([ref]$SkipRepositoryValidation) -AsSwitch
Set-ValueFromEnvironmentPreset -Preset $environmentPresetData -BoundParameters $PSBoundParameters -Key "SkipTemplateValidation" -Target ([ref]$SkipTemplateValidation) -AsSwitch
Set-ValueFromEnvironmentPreset -Preset $environmentPresetData -BoundParameters $PSBoundParameters -Key "SkipWorkstationValidation" -Target ([ref]$SkipWorkstationValidation) -AsSwitch
Set-ValueFromEnvironmentPreset -Preset $environmentPresetData -BoundParameters $PSBoundParameters -Key "SkipBundleValidation" -Target ([ref]$SkipBundleValidation) -AsSwitch
Set-ValueFromEnvironmentPreset -Preset $environmentPresetData -BoundParameters $PSBoundParameters -Key "SkipArchive" -Target ([ref]$SkipArchive) -AsSwitch
Set-ValueFromEnvironmentPreset -Preset $environmentPresetData -BoundParameters $PSBoundParameters -Key "DeployBundle" -Target ([ref]$DeployBundle) -AsSwitch
Set-ValueFromEnvironmentPreset -Preset $environmentPresetData -BoundParameters $PSBoundParameters -Key "DeploymentDryRun" -Target ([ref]$DeploymentDryRun) -AsSwitch

if (-not $OutputPath) {
    throw "-OutputPath is required unless it is provided by the selected environment preset."
}

if (-not $ValuesFile) {
    $ValuesFile = "config\platform-values.env.example"
}

$resolvedOutputPath = Resolve-RepoPath -Root $root -Path $OutputPath
$resolvedValuesFile = Resolve-RepoPath -Root $root -Path $ValuesFile
$resolvedHelmConfigFile = ""
$resolvedArchivePath = ""
$Applications = @(Normalize-List -Values $Applications)
$DataServices = @(Normalize-List -Values $DataServices)

if ($PSBoundParameters.ContainsKey("HelmConfigFile") -and $HelmConfigFile) {
    $resolvedHelmConfigFile = Resolve-RepoPath -Root $root -Path $HelmConfigFile
}

if (-not $SkipArchive) {
    if ($PSBoundParameters.ContainsKey("ArchivePath") -and $ArchivePath) {
        $resolvedArchivePath = Resolve-RepoPath -Root $root -Path $ArchivePath
    }
    else {
        $outputParent = Split-Path -Path $resolvedOutputPath -Parent
        $outputLeaf = Split-Path -Path $resolvedOutputPath -Leaf
        $resolvedArchivePath = Join-Path $outputParent ($outputLeaf + ".zip")
    }
}

if ($CleanOutput -and (Test-UnsafeDeletionTarget -Path $resolvedOutputPath -RepoPath $root)) {
    throw ("Refusing to clean unsafe output path: {0}" -f $resolvedOutputPath)
}

if (Test-Path -Path $resolvedOutputPath) {
    if (-not (Test-Path -Path $resolvedOutputPath -PathType Container)) {
        throw ("Output path exists but is not a directory: {0}" -f $resolvedOutputPath)
    }

    $existingOutputEntries = @(Get-ChildItem -Path $resolvedOutputPath -Force)
    if ($existingOutputEntries.Count -gt 0) {
        if (-not $CleanOutput) {
            throw ("Output path already exists and is not empty: {0}. Re-run with -CleanOutput to replace it." -f $resolvedOutputPath)
        }

        Remove-Item -LiteralPath $resolvedOutputPath -Recurse -Force
    }
}

if ($resolvedArchivePath -and (Test-Path -Path $resolvedArchivePath)) {
    if (-not $OverwriteArchive) {
        throw ("Archive already exists: {0}. Re-run with -OverwriteArchive to replace it." -f $resolvedArchivePath)
    }

    Remove-Item -LiteralPath $resolvedArchivePath -Force
}

New-Item -ItemType Directory -Path $resolvedOutputPath -Force | Out-Null

$repositoryValidationScript = Join-Path $root "scripts\invoke-repository-validation.ps1"
$renderPlatformAssetsScript = Join-Path $root "scripts\render-platform-assets.ps1"
$bundleValidateScript = Join-Path $resolvedOutputPath "validate-bundle.ps1"
$bundleDeployScript = Join-Path $resolvedOutputPath "deploy-bundle.ps1"

Write-Host "Bundle delivery workflow"
Write-Host ("- Repo root: {0}" -f $root)
if ($environmentPresetData) {
    Write-Host ("- Environment preset: {0}" -f (Get-EnvironmentPresetDisplayText -Preset $environmentPresetData))
}
Write-Host ("- Output path: {0}" -f $resolvedOutputPath)
Write-Host ("- Values file: {0}" -f $resolvedValuesFile)
Write-Host ("- Profile: {0}" -f $Profile)
Write-Host ("- Applications: {0}" -f (Get-ListText -Values $Applications))
Write-Host ("- Data services: {0}" -f (Get-ListText -Values $DataServices))
Write-Host ("- Include Jenkins: {0}" -f [string]([bool]$IncludeJenkins))
if ($resolvedArchivePath) {
    Write-Host ("- Archive path: {0}" -f $resolvedArchivePath)
}
Write-Host ""

if (-not $SkipRepositoryValidation) {
    $repositoryValidationParameters = @{
        RepoRoot = $root
        ValuesFile = $resolvedValuesFile
        DockerRegistry = $DockerRegistry
        Version = $Version
        Profile = $Profile
        Applications = @($Applications)
        DataServices = @($DataServices)
        IncludeJenkins = $IncludeJenkins
        SkipPlatformAssetValidation = $true
    }

    if ($resolvedHelmConfigFile) {
        $repositoryValidationParameters.HelmConfigFile = $resolvedHelmConfigFile
    }

    if ($SkipTemplateValidation) {
        $repositoryValidationParameters.SkipTemplateValidation = $true
    }

    if ($SkipWorkstationValidation) {
        $repositoryValidationParameters.SkipWorkstationValidation = $true
    }

    Invoke-WorkflowStep -Title "Repository validation preflight" -Action {
        & $repositoryValidationScript @repositoryValidationParameters
    }
}

Invoke-WorkflowStep -Title "Render deployment bundle" -Action {
    $renderParameters = @{
        RepoRoot = $root
        OutputPath = $resolvedOutputPath
        DockerRegistry = $DockerRegistry
        Version = $Version
        ValuesFile = $resolvedValuesFile
        Profile = $Profile
        Applications = @($Applications)
        DataServices = @($DataServices)
        IncludeJenkins = $IncludeJenkins
        FailOnUnresolvedToken = $true
    }

    & $renderPlatformAssetsScript @renderParameters
}

if (-not $SkipBundleValidation) {
    Invoke-WorkflowStep -Title "Bundle-local validation" -Action {
        if (-not (Test-Path -Path $bundleValidateScript -PathType Leaf)) {
            throw ("Bundle validation helper not found: {0}" -f $bundleValidateScript)
        }

        $bundleValidationParameters = @{
            BundleRoot = $resolvedOutputPath
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

if (-not $SkipArchive) {
    Invoke-WorkflowStep -Title "Archive rendered bundle" -Action {
        $archiveDirectory = Split-Path -Path $resolvedArchivePath -Parent
        if ($archiveDirectory) {
            New-Item -ItemType Directory -Path $archiveDirectory -Force | Out-Null
        }

        Compress-Archive -LiteralPath $resolvedOutputPath -DestinationPath $resolvedArchivePath
        if (-not (Test-Path -Path $resolvedArchivePath -PathType Leaf)) {
            throw ("Failed to create bundle archive: {0}" -f $resolvedArchivePath)
        }
    }
}

if ($DeployBundle) {
    Invoke-WorkflowStep -Title "Deploy rendered bundle" -Action {
        if (-not (Test-Path -Path $bundleDeployScript -PathType Leaf)) {
            throw ("Bundle deployment helper not found: {0}" -f $bundleDeployScript)
        }

        $deployParameters = @{
            BundleRoot = $resolvedOutputPath
            PrepareHelmRepos = $PrepareHelmRepos
            DryRun = $DeploymentDryRun
            IncludeDeferredComponents = $IncludeDeferredComponents
        }

        & $bundleDeployScript @deployParameters
    }
}

Write-Host "Bundle delivery workflow completed."
