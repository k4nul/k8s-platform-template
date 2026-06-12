param(
    [string]$RepoRoot,
    [string]$ValuesFile,
    [switch]$Strict,
    [switch]$ValidateCrdBackedResources,
    [switch]$FailOnHighSecurityBaselineFinding
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
        [object[]]$Values = @()
    )

    $normalized = New-Object System.Collections.Generic.List[string]

    foreach ($value in @($Values)) {
        if ($null -eq $value) {
            continue
        }

        foreach ($entry in ([string]$value -split ",")) {
            $trimmed = $entry.Trim()
            if ($trimmed) {
                $normalized.Add($trimmed) | Out-Null
            }
        }
    }

    return $normalized.ToArray()
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

function Get-MatrixString {
    param(
        [hashtable]$Data,
        [string]$Key,
        [string]$Default = ""
    )

    if ($null -eq $Data -or -not $Data.ContainsKey($Key) -or $null -eq $Data[$Key]) {
        return $Default
    }

    return ([string]$Data[$Key]).Trim()
}

function Get-MatrixList {
    param(
        [hashtable]$Data,
        [string]$Key
    )

    if ($null -eq $Data -or -not $Data.ContainsKey($Key)) {
        return @()
    }

    return @(Normalize-List -Values @($Data[$Key]))
}

function Get-MatrixFlag {
    param(
        [hashtable]$Data,
        [string]$Key
    )

    return ($null -ne $Data -and $Data.ContainsKey($Key) -and [bool]$Data[$Key])
}

function New-RenderMatrixEntry {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Scope,

        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [string]$ValuesFile,

        [string]$Version = "0.0.0-matrix",
        [string]$Profile = "full",
        [string[]]$Applications = @(),
        [string[]]$DataServices = @(),
        [switch]$IncludeJenkins
    )

    return [PSCustomObject]@{
        Scope = $Scope
        Name = $Name
        ValuesFile = $ValuesFile
        Version = $Version
        Profile = $Profile
        Applications = @(Normalize-List -Values $Applications)
        DataServices = @(Normalize-List -Values $DataServices)
        IncludeJenkins = [bool]$IncludeJenkins
    }
}

function Get-ProfileRenderMatrix {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ValuesFile
    )

    return @(
        (New-RenderMatrixEntry `
            -Scope "profile" `
            -Name "minimal-application" `
            -ValuesFile $ValuesFile `
            -Profile "minimal-application" `
            -Applications @("nginx-web", "whoami")),
        (New-RenderMatrixEntry `
            -Scope "profile" `
            -Name "developer-sandbox" `
            -ValuesFile $ValuesFile `
            -Profile "developer-sandbox" `
            -Applications @("nginx-web", "httpbin", "whoami") `
            -DataServices @("mysql", "redis")),
        (New-RenderMatrixEntry `
            -Scope "profile" `
            -Name "data-services" `
            -ValuesFile $ValuesFile `
            -Profile "data-services" `
            -DataServices @("mysql", "postgresql", "redis")),
        (New-RenderMatrixEntry `
            -Scope "profile" `
            -Name "reverse-proxy-platform" `
            -ValuesFile $ValuesFile `
            -Profile "reverse-proxy-platform" `
            -Applications @("nginx-web", "whoami")),
        (New-RenderMatrixEntry `
            -Scope "profile" `
            -Name "web-platform" `
            -ValuesFile $ValuesFile `
            -Profile "web-platform" `
            -Applications @("nginx-web", "httpbin", "whoami") `
            -DataServices @("redis")),
        (New-RenderMatrixEntry `
            -Scope "profile" `
            -Name "shared-services" `
            -ValuesFile $ValuesFile `
            -Profile "shared-services" `
            -Applications @("nginx-web", "adminer") `
            -DataServices @("postgresql", "redis")),
        (New-RenderMatrixEntry `
            -Scope "profile" `
            -Name "full" `
            -ValuesFile $ValuesFile `
            -Profile "full" `
            -Applications @("nginx-web", "httpbin", "whoami", "adminer") `
            -DataServices @("mysql", "postgresql", "redis"))
    )
}

function Get-EnvironmentRenderMatrix {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Root,

        [Parameter(Mandatory = $true)]
        [string]$DefaultValuesFile,

        [string]$OverrideValuesFile
    )

    $environmentDirectory = Join-Path $Root "config\environments"
    $entries = New-Object System.Collections.Generic.List[object]

    foreach ($presetFile in @(Get-ChildItem -Path $environmentDirectory -File -Filter "*.psd1" | Sort-Object BaseName)) {
        $preset = Get-EnvironmentPresetData -RepoRoot $Root -EnvironmentPreset $presetFile.BaseName
        $entryValuesFile = if ($OverrideValuesFile) {
            $OverrideValuesFile
        }
        elseif ($preset.ContainsKey("ValidationValuesFile")) {
            [string]$preset["ValidationValuesFile"]
        }
        elseif ($preset.ContainsKey("ValuesFile")) {
            [string]$preset["ValuesFile"]
        }
        else {
            $DefaultValuesFile
        }

        $entries.Add((New-RenderMatrixEntry `
            -Scope "environment" `
            -Name $presetFile.BaseName `
            -ValuesFile $entryValuesFile `
            -Version (Get-MatrixString -Data $preset -Key "Version" -Default ("0.0.0-" + $presetFile.BaseName + "-matrix")) `
            -Profile (Get-MatrixString -Data $preset -Key "Profile" -Default "full") `
            -Applications (Get-MatrixList -Data $preset -Key "Applications") `
            -DataServices (Get-MatrixList -Data $preset -Key "DataServices") `
            -IncludeJenkins:(Get-MatrixFlag -Data $preset -Key "IncludeJenkins"))) | Out-Null
    }

    return $entries.ToArray()
}

if (-not $PSBoundParameters.ContainsKey("RepoRoot") -or -not $RepoRoot) {
    $RepoRoot = Join-Path $PSScriptRoot ".."
}

$root = (Resolve-Path -Path $RepoRoot).Path
$defaultValuesFile = "config\platform-values.env.example"
$matrixValuesFile = if ($ValuesFile) { $ValuesFile } else { $defaultValuesFile }
$assetValidation = Join-Path $root "scripts\validate-platform-assets.ps1"

$matrixEntries = New-Object System.Collections.Generic.List[object]
$environmentMatrixParameters = @{
    Root = $root
    DefaultValuesFile = $defaultValuesFile
}

if ($ValuesFile) {
    $environmentMatrixParameters.OverrideValuesFile = $ValuesFile
}

foreach ($entry in @(Get-EnvironmentRenderMatrix @environmentMatrixParameters)) {
    $matrixEntries.Add($entry) | Out-Null
}

$profileEntries = @(Get-ProfileRenderMatrix -ValuesFile $matrixValuesFile)
$profileNames = @(
    Get-ChildItem -Path (Join-Path $root "config\profiles") -File -Filter "*.psd1" |
        Sort-Object BaseName |
        Select-Object -ExpandProperty BaseName
)
$matrixProfileNames = @($profileEntries | Select-Object -ExpandProperty Name)
$missingProfileNames = @($profileNames | Where-Object { $_ -notin $matrixProfileNames })
$extraProfileNames = @($matrixProfileNames | Where-Object { $_ -notin $profileNames })

if ($missingProfileNames.Count -gt 0 -or $extraProfileNames.Count -gt 0) {
    throw ("Profile render matrix does not match config/profiles. Missing: {0}. Extra: {1}." -f (Get-ListText -Values $missingProfileNames), (Get-ListText -Values $extraProfileNames))
}

foreach ($entry in $profileEntries) {
    $matrixEntries.Add($entry) | Out-Null
}

Write-Host "Render validation matrix"
Write-Host ("- Repository root: {0}" -f $root)
Write-Host ("- Matrix entries: {0}" -f $matrixEntries.Count)
Write-Host ""

foreach ($entry in $matrixEntries) {
    $resolvedValuesFile = Resolve-RepoPath -Root $root -Path $entry.ValuesFile
    if (-not (Test-Path -Path $resolvedValuesFile -PathType Leaf)) {
        throw ("Render matrix values file was not found for {0} '{1}': {2}" -f $entry.Scope, $entry.Name, $resolvedValuesFile)
    }

    Write-Host ("== Render matrix {0}: {1} ==" -f $entry.Scope, $entry.Name)
    Write-Host ("- Values file: {0}" -f $resolvedValuesFile)
    Write-Host ("- Profile: {0}" -f $entry.Profile)
    Write-Host ("- Applications: {0}" -f (Get-ListText -Values @($entry.Applications)))
    Write-Host ("- Data services: {0}" -f (Get-ListText -Values @($entry.DataServices)))

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
