param(
    [Parameter(Mandatory = $true)]
    [string]$EnvironmentName,
    [string]$EnvironmentPreset,
    [string]$EnvironmentPresetFile,

    [string]$ValuesFilePath,
    [string]$BaseValuesFile,
    [string]$Profile = "full",
    [string[]]$Applications = @(),
    [string[]]$DataServices = @(),
    [switch]$IncludeJenkins,
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "environment-preset.ps1")
. (Join-Path $PSScriptRoot "platform-catalog.ps1")

$root = (Resolve-Path -Path (Join-Path $PSScriptRoot "..")).Path
$environmentPresetData = Get-EnvironmentPresetData `
    -RepoRoot $root `
    -EnvironmentPreset $EnvironmentPreset `
    -EnvironmentPresetFile $EnvironmentPresetFile

Set-ValueFromEnvironmentPreset -Preset $environmentPresetData -BoundParameters $PSBoundParameters -Key "ValuesFilePath" -Target ([ref]$ValuesFilePath)
if (-not $PSBoundParameters.ContainsKey("ValuesFilePath") -and -not $ValuesFilePath -and $environmentPresetData -and $environmentPresetData.ContainsKey("ValuesFile")) {
    $ValuesFilePath = $environmentPresetData["ValuesFile"]
}
Set-ValueFromEnvironmentPreset -Preset $environmentPresetData -BoundParameters $PSBoundParameters -Key "BaseValuesFile" -Target ([ref]$BaseValuesFile)
Set-ValueFromEnvironmentPreset -Preset $environmentPresetData -BoundParameters $PSBoundParameters -Key "Profile" -Target ([ref]$Profile)
Set-ValueFromEnvironmentPreset -Preset $environmentPresetData -BoundParameters $PSBoundParameters -Key "Applications" -Target ([ref]$Applications) -AsList
Set-ValueFromEnvironmentPreset -Preset $environmentPresetData -BoundParameters $PSBoundParameters -Key "DataServices" -Target ([ref]$DataServices) -AsList
Set-ValueFromEnvironmentPreset -Preset $environmentPresetData -BoundParameters $PSBoundParameters -Key "IncludeJenkins" -Target ([ref]$IncludeJenkins) -AsSwitch

if (-not $BaseValuesFile) {
    $BaseValuesFile = Join-Path $PSScriptRoot "..\config\platform-values.env.example"
}

$selection = Resolve-PlatformSelection -Profile $Profile -Applications $Applications -DataServices $DataServices -IncludeJenkins:$IncludeJenkins
$targetPath = if ($ValuesFilePath) {
    [System.IO.Path]::GetFullPath($ValuesFilePath)
}
else {
    [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ("..\config\platform-values.{0}.env" -f $EnvironmentName)))
}

$baseValuesPath = (Resolve-Path -Path $BaseValuesFile).Path
$platformValuesPlanScript = Join-Path $root "scripts\show-platform-values-plan.ps1"
if ((Test-Path -Path $targetPath) -and -not $Force) {
    throw "Values file already exists: $targetPath"
}

$applicationsText = if ($selection.ServiceDirectories.Count -gt 0) {
    $selection.ServiceDirectories -join ", "
}
else {
    "none selected"
}

$dataServicesText = if (@($DataServices).Count -gt 0) {
    @($DataServices) -join ", "
}
else {
    "none selected"
}

$header = @(
    "# Environment: $EnvironmentName",
    "# Environment preset: $(if ($environmentPresetData) { Get-EnvironmentPresetDisplayText -Preset $environmentPresetData } else { 'none' })",
    "# Profile: $($selection.Profile)",
    "# Description: $($selection.Description)",
    "# Applications: $applicationsText",
    "# Data services: $dataServicesText",
    "# Include Jenkins: $([bool]$IncludeJenkins)",
    "#",
    "# Preview the selected layout with:",
    "# .\scripts\show-platform-plan.ps1 -Profile $($selection.Profile) -Applications $($Applications -join ',') -DataServices $($DataServices -join ',')",
    "# .\scripts\show-platform-values-plan.ps1 -Profile $($selection.Profile) -Applications $($Applications -join ',') -DataServices $($DataServices -join ',') -Format markdown",
    "#",
    "# After editing this file, render a deployment bundle with:",
    "# .\scripts\render-platform-assets.ps1 -OutputPath .\out\$EnvironmentName -Version 1.0.0 -ValuesFile $targetPath -Profile $($selection.Profile) -Applications $($Applications -join ',') -DataServices $($DataServices -join ',')"
)

$valuesBody = & $platformValuesPlanScript `
    -RepoRoot $root `
    -Profile $Profile `
    -Applications $Applications `
    -DataServices $DataServices `
    -IncludeJenkins:$IncludeJenkins `
    -ValuesFile $baseValuesPath `
    -Format env

$content = ($header -join [Environment]::NewLine) + [Environment]::NewLine + [Environment]::NewLine + ($valuesBody -join [Environment]::NewLine)
$targetDirectory = Split-Path -Path $targetPath -Parent

if ($targetDirectory) {
    New-Item -ItemType Directory -Path $targetDirectory -Force | Out-Null
}

Set-Content -Path $targetPath -Value $content -NoNewline

Write-Host ("Created environment values file: {0}" -f $targetPath)
if ($environmentPresetData) {
    Write-Host ("Environment preset: {0}" -f (Get-EnvironmentPresetDisplayText -Preset $environmentPresetData))
}
Write-Host ("Base values file: {0}" -f $baseValuesPath)
Write-Host ("Profile: {0}" -f $selection.Profile)
Write-Host ("Kubernetes directories: {0}" -f (($selection.K8sDirectories -join ", ")))
Write-Host ("Service directories: {0}" -f (($selection.ServiceDirectories -join ", ")))
