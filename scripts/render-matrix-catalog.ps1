Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot "environment-preset.ps1")
. (Join-Path $PSScriptRoot "platform-catalog.ps1")

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
        [System.Collections.IDictionary]$Data,
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
        [System.Collections.IDictionary]$Data,
        [string]$Key
    )

    if ($null -eq $Data -or -not $Data.ContainsKey($Key)) {
        return @()
    }

    return @(ConvertTo-RenderMatrixList -Values @($Data[$Key]))
}

function Get-MatrixFlag {
    param(
        [System.Collections.IDictionary]$Data,
        [string]$Key
    )

    return ($null -ne $Data -and $Data.ContainsKey($Key) -and [bool]$Data[$Key])
}

function Get-ProfileRenderMatrixNames {
    param(
        [System.Collections.IDictionary]$Profiles
    )

    $preferredOrder = @(
        "minimal-application",
        "developer-sandbox",
        "data-services",
        "reverse-proxy-platform",
        "web-platform",
        "shared-services",
        "full"
    )
    $orderedNames = New-Object System.Collections.Generic.List[string]

    foreach ($profileName in $preferredOrder) {
        if ($Profiles.Contains($profileName)) {
            $orderedNames.Add($profileName) | Out-Null
        }
    }

    foreach ($profileName in @($Profiles.Keys | Where-Object { $_ -notin $preferredOrder } | Sort-Object)) {
        $orderedNames.Add($profileName) | Out-Null
    }

    return @($orderedNames)
}

function Get-RequiredProfileMatrixList {
    param(
        [System.Collections.IDictionary]$Definition,
        [string]$ProfileName,
        [string]$Key
    )

    if (-not $Definition.Contains($Key)) {
        throw ("Profile '{0}' is missing '{1}'. Add an explicit public render-validation selection in config/profiles/{0}.psd1." -f $ProfileName, $Key)
    }

    return @(Get-MatrixList -Data $Definition -Key $Key)
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
        [string]$Root = (Join-Path $PSScriptRoot ".."),

        [Parameter(Mandatory = $true)]
        [string]$ValuesFile
    )

    $profiles = Get-PlatformProfileDefinitions -ProfileDirectory (Join-Path $Root "config\profiles")
    $entries = New-Object System.Collections.Generic.List[object]

    foreach ($profileName in (Get-ProfileRenderMatrixNames -Profiles $profiles)) {
        $definition = $profiles[$profileName]
        $entries.Add((New-RenderMatrixEntry `
            -Scope "profile" `
            -Name $profileName `
            -ValuesFile $ValuesFile `
            -Profile $profileName `
            -Applications (Get-RequiredProfileMatrixList -Definition $definition -ProfileName $profileName -Key "ValidationApplications") `
            -DataServices (Get-RequiredProfileMatrixList -Definition $definition -ProfileName $profileName -Key "ValidationDataServices") `
            -IncludeJenkins:(Get-MatrixFlag -Data $definition -Key "ValidationIncludeJenkins"))) | Out-Null
    }

    return $entries.ToArray()
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

    $profileEntries = @(Get-ProfileRenderMatrix -Root $Root -ValuesFile $matrixValuesFile)
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
