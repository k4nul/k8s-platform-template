Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot "environment-preset.ps1")

function Resolve-RenderMatrixRepoPath {
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

function ConvertTo-RenderMatrixList {
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

function Get-RenderMatrixListText {
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

    return @(ConvertTo-RenderMatrixList -Values @($Data[$Key]))
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
        Applications = @(ConvertTo-RenderMatrixList -Values $Applications)
        DataServices = @(ConvertTo-RenderMatrixList -Values $DataServices)
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

function Get-RenderValidationMatrix {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Root,

        [string]$DefaultValuesFile = "config\platform-values.env.example",

        [string]$ValuesFile
    )

    $matrixEntries = New-Object System.Collections.Generic.List[object]
    $matrixValuesFile = if ($ValuesFile) { $ValuesFile } else { $DefaultValuesFile }
    $environmentMatrixParameters = @{
        Root = $Root
        DefaultValuesFile = $DefaultValuesFile
    }

    if ($ValuesFile) {
        $environmentMatrixParameters.OverrideValuesFile = $ValuesFile
    }

    foreach ($entry in @(Get-EnvironmentRenderMatrix @environmentMatrixParameters)) {
        $matrixEntries.Add($entry) | Out-Null
    }

    $profileEntries = @(Get-ProfileRenderMatrix -ValuesFile $matrixValuesFile)
    $profileNames = @(
        Get-ChildItem -Path (Join-Path $Root "config\profiles") -File -Filter "*.psd1" |
            Sort-Object BaseName |
            Select-Object -ExpandProperty BaseName
    )
    $matrixProfileNames = @($profileEntries | Select-Object -ExpandProperty Name)
    $missingProfileNames = @($profileNames | Where-Object { $_ -notin $matrixProfileNames })
    $extraProfileNames = @($matrixProfileNames | Where-Object { $_ -notin $profileNames })

    if ($missingProfileNames.Count -gt 0 -or $extraProfileNames.Count -gt 0) {
        throw ("Profile render matrix does not match config/profiles. Missing: {0}. Extra: {1}." -f (Get-RenderMatrixListText -Values $missingProfileNames), (Get-RenderMatrixListText -Values $extraProfileNames))
    }

    foreach ($entry in $profileEntries) {
        $matrixEntries.Add($entry) | Out-Null
    }

    return $matrixEntries.ToArray()
}
