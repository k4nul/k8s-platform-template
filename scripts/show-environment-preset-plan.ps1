param(
    [string]$RepoRoot,
    [ValidateSet("text", "markdown", "json")]
    [string]$Format = "text",
    [string]$OutputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "environment-preset.ps1")

function Get-TextList {
    param(
        [object[]]$Values,
        [string]$Empty = "none"
    )

    if (@($Values).Count -gt 0) {
        return (@($Values) -join ", ")
    }

    return $Empty
}

function Get-PresetString {
    param(
        [hashtable]$Preset,
        [string]$Key,
        [string]$Default = ""
    )

    if ($null -eq $Preset -or -not $Preset.ContainsKey($Key)) {
        return $Default
    }

    return ([string]$Preset[$Key]).Trim()
}

function Get-PresetArray {
    param(
        [hashtable]$Preset,
        [string]$Key
    )

    if ($null -eq $Preset -or -not $Preset.ContainsKey($Key)) {
        return @()
    }

    return @(
        @($Preset[$Key]) |
            ForEach-Object { [string]$_ } |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ } |
            Sort-Object -Unique
    )
}

function Get-PresetCommand {
    param(
        [string]$ScriptName,
        [string]$PresetName,
        [string]$AdditionalArguments = ""
    )

    $command = ".\scripts\{0} -EnvironmentPreset {1}" -f $ScriptName, $PresetName
    if ($AdditionalArguments) {
        $command += (" " + $AdditionalArguments.Trim())
    }

    return $command
}

if (-not $PSBoundParameters.ContainsKey("RepoRoot") -or -not $RepoRoot) {
    $RepoRoot = Join-Path $PSScriptRoot ".."
}

$root = (Resolve-Path -Path $RepoRoot).Path
$presetDirectory = Join-Path $root "config\environments"
$presetFiles = @(
    Get-ChildItem -Path $presetDirectory -File -Filter "*.psd1" |
        Sort-Object BaseName
)

$presetCatalog = @()

foreach ($presetFile in $presetFiles) {
    $presetName = $presetFile.BaseName
    $presetData = Get-EnvironmentPresetData -RepoRoot $root -EnvironmentPreset $presetName
    $applications = @(Get-PresetArray -Preset $presetData -Key "Applications")
    $dataServices = @(Get-PresetArray -Preset $presetData -Key "DataServices")

    $presetCatalog += [PSCustomObject]@{
        Name = $presetName
        Description = Get-PresetString -Preset $presetData -Key "Description"
        ValuesFile = Get-PresetString -Preset $presetData -Key "ValuesFile" -Default "config\platform-values.env.example"
        DockerRegistry = Get-PresetString -Preset $presetData -Key "DockerRegistry" -Default "not set"
        Version = Get-PresetString -Preset $presetData -Key "Version" -Default "not set"
        Profile = Get-PresetString -Preset $presetData -Key "Profile" -Default "full"
        Applications = @($applications)
        DataServices = @($dataServices)
        IncludeJenkins = if ($presetData.ContainsKey("IncludeJenkins")) { [bool]$presetData["IncludeJenkins"] } else { $false }
        OutputPath = Get-PresetString -Preset $presetData -Key "OutputPath" -Default "not set"
        ArchivePath = Get-PresetString -Preset $presetData -Key "ArchivePath" -Default "not set"
        PromotionExtractPath = if ($presetData.ContainsKey("PromotionExtractPath")) {
            Get-PresetString -Preset $presetData -Key "PromotionExtractPath"
        }
        elseif ($presetData.ContainsKey("ExtractPath")) {
            Get-PresetString -Preset $presetData -Key "ExtractPath"
        }
        else {
            "not set"
        }
        PresetPath = [string]$presetData["_PresetPath"]
        ScaffoldCommand = Get-PresetCommand -ScriptName "new-platform-environment.ps1" -PresetName $presetName -AdditionalArguments ("-EnvironmentName " + $presetName)
        ValidationCommand = Get-PresetCommand -ScriptName "invoke-repository-validation.ps1" -PresetName $presetName
        DeliveryCommand = Get-PresetCommand -ScriptName "invoke-bundle-delivery.ps1" -PresetName $presetName
        PromotionCommand = Get-PresetCommand -ScriptName "invoke-bundle-promotion.ps1" -PresetName $presetName
    }
}

switch ($Format) {
    "json" {
        $document = ([ordered]@{
            GeneratedAt = (Get-Date).ToString("s")
            RepoRoot = $root
            Presets = @($presetCatalog)
        } | ConvertTo-Json -Depth 10)
    }
    "markdown" {
        $lines = @(
            "# Environment Preset Catalog",
            "",
            "## Summary",
            "",
            ("- Repository root: " + $root),
            ("- Preset count: " + [string]$presetCatalog.Count),
            ""
        )

        if ($presetCatalog.Count -gt 0) {
            $lines += "| Preset | Profile | Applications | Data Services | Values File | Archive Path |"
            $lines += "| --- | --- | --- | --- | --- | --- |"
            foreach ($preset in $presetCatalog) {
                $lines += ("| {0} | {1} | {2} | {3} | {4} | {5} |" -f $preset.Name, $preset.Profile, (Get-TextList -Values $preset.Applications), (Get-TextList -Values $preset.DataServices), $preset.ValuesFile, $preset.ArchivePath)
            }

            $lines += ""
            $lines += "## Preset Details"
            $lines += ""

            foreach ($preset in $presetCatalog) {
                $lines += ("### " + $preset.Name)
                $lines += ""
                $lines += ("- Description: " + $preset.Description)
                $lines += ("- Profile: " + $preset.Profile)
                $lines += ("- Applications: " + (Get-TextList -Values $preset.Applications))
                $lines += ("- Data services: " + (Get-TextList -Values $preset.DataServices))
                $lines += ("- Include Jenkins: " + [string]([bool]$preset.IncludeJenkins))
                $lines += ("- Values file: " + $preset.ValuesFile)
                $lines += ("- Docker registry: " + $preset.DockerRegistry)
                $lines += ("- Version: " + $preset.Version)
                $lines += ("- Delivery output: " + $preset.OutputPath)
                $lines += ("- Archive path: " + $preset.ArchivePath)
                $lines += ("- Promotion extract path: " + $preset.PromotionExtractPath)
                $lines += ("- Preset file: " + $preset.PresetPath)
                $lines += ('- Scaffold command: `' + $preset.ScaffoldCommand + '`')
                $lines += ('- Validation command: `' + $preset.ValidationCommand + '`')
                $lines += ('- Delivery command: `' + $preset.DeliveryCommand + '`')
                $lines += ('- Promotion command: `' + $preset.PromotionCommand + '`')
                $lines += ""
            }
        }

        $document = $lines -join [Environment]::NewLine
    }
    default {
        $lines = @(
            "Environment Preset Catalog",
            "==========================",
            ("Repository root: " + $root),
            ("Preset count: " + [string]$presetCatalog.Count),
            ""
        )

        foreach ($preset in $presetCatalog) {
            $lines += ($preset.Name + " [" + $preset.Profile + "]")
            $lines += ("  Description: " + $preset.Description)
            $lines += ("  Applications: " + (Get-TextList -Values $preset.Applications))
            $lines += ("  Data services: " + (Get-TextList -Values $preset.DataServices))
            $lines += ("  Include Jenkins: " + [string]([bool]$preset.IncludeJenkins))
            $lines += ("  Values file: " + $preset.ValuesFile)
            $lines += ("  Docker registry: " + $preset.DockerRegistry)
            $lines += ("  Version: " + $preset.Version)
            $lines += ("  Delivery output: " + $preset.OutputPath)
            $lines += ("  Archive path: " + $preset.ArchivePath)
            $lines += ("  Promotion extract path: " + $preset.PromotionExtractPath)
            $lines += ("  Preset file: " + $preset.PresetPath)
            $lines += ("  Scaffold: " + $preset.ScaffoldCommand)
            $lines += ("  Validation: " + $preset.ValidationCommand)
            $lines += ("  Delivery: " + $preset.DeliveryCommand)
            $lines += ("  Promotion: " + $preset.PromotionCommand)
            $lines += ""
        }

        $document = $lines -join [Environment]::NewLine
    }
}

if ($PSBoundParameters.ContainsKey("OutputPath") -and $OutputPath) {
    $resolvedOutputPath = [System.IO.Path]::GetFullPath($OutputPath)
    $outputDirectory = Split-Path -Path $resolvedOutputPath -Parent
    if ($outputDirectory) {
        New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
    }

    Set-Content -Path $resolvedOutputPath -Value $document -NoNewline
    Write-Host ("Wrote environment preset catalog to {0}" -f $resolvedOutputPath)
}
else {
    Write-Output $document
}
