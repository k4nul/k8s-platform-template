param(
    [string]$RepoRoot,
    [string]$ValuesFile
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if (-not $PSBoundParameters.ContainsKey("RepoRoot") -or -not $RepoRoot) {
    $RepoRoot = Join-Path $PSScriptRoot ".."
}

if (-not $PSBoundParameters.ContainsKey("ValuesFile") -or -not $ValuesFile) {
    $ValuesFile = Join-Path $PSScriptRoot "..\config\platform-values.env.example"
}

$root = (Resolve-Path -Path $RepoRoot).Path
$servicesRoot = Join-Path $root "services"
$catalogPath = Join-Path $root "config\service-config-artifacts.psd1"
$catalog = Import-PowerShellDataFile -Path $catalogPath
$errors = New-Object System.Collections.Generic.List[string]

$valueKeys = New-Object System.Collections.Generic.List[string]
foreach ($line in Get-Content -Path $ValuesFile) {
    $trimmedLine = $line.Trim()
    if (-not $trimmedLine -or $trimmedLine.StartsWith("#")) {
        continue
    }

    $delimiterIndex = $trimmedLine.IndexOf("=")
    if ($delimiterIndex -lt 1) {
        continue
    }

    $valueKeys.Add($trimmedLine.Substring(0, $delimiterIndex).Trim()) | Out-Null
}

$catalogMap = [ordered]@{}
foreach ($service in @($catalog.Services | Sort-Object { $_.Name })) {
    $catalogMap[$service.Name] = $service
}

$serviceDirectories = @(Get-ChildItem -Path $servicesRoot -Directory | Sort-Object Name | Select-Object -ExpandProperty Name)
$missingEntries = @($serviceDirectories | Where-Object { -not $catalogMap.Contains($_) })
$missingDirectories = @($catalogMap.Keys | Where-Object { $serviceDirectories -notcontains $_ })

foreach ($item in $missingEntries) {
    $errors.Add("Service directory is missing from config/service-config-artifacts.psd1: $item") | Out-Null
}

foreach ($item in $missingDirectories) {
    $errors.Add("Config artifact catalog entry is missing service directory: $item") | Out-Null
}

foreach ($serviceName in $catalogMap.Keys) {
    $definition = $catalogMap[$serviceName]
    $serviceRoot = Join-Path $servicesRoot $serviceName
    if (-not (Test-Path -Path $serviceRoot -PathType Container)) {
        continue
    }

    $catalogedFiles = @($definition.ConfigArtifacts | ForEach-Object { $_.SourceFile } | Sort-Object -Unique)
    $actualFiles = @(
        Get-ChildItem -Path $serviceRoot -File |
            Where-Object { $_.Extension -in ".json", ".ini" } |
            Select-Object -ExpandProperty Name |
            Sort-Object -Unique
    )

    foreach ($fileName in $actualFiles) {
        if ($catalogedFiles -notcontains $fileName) {
            $errors.Add("Config file is not cataloged for ${serviceName}: services/$serviceName/$fileName") | Out-Null
        }
    }

    foreach ($fileName in $catalogedFiles) {
        if ($actualFiles -notcontains $fileName) {
            $errors.Add("Catalog references missing config file for ${serviceName}: services/$serviceName/$fileName") | Out-Null
        }
    }

    foreach ($artifact in @($definition.ConfigArtifacts)) {
        $artifactPath = Join-Path $serviceRoot $artifact.SourceFile
        if (-not (Test-Path -Path $artifactPath -PathType Leaf)) {
            continue
        }

        $content = Get-Content -Path $artifactPath -Raw
        $foundTokens = @(
            [regex]::Matches($content, '__([A-Z0-9_]+)__') |
                ForEach-Object { $_.Groups[1].Value } |
                Sort-Object -Unique
        )
        $expectedTokens = @($artifact.PlaceholderTokens | Sort-Object -Unique)

        if ((@($foundTokens) -join ",") -ne (@($expectedTokens) -join ",")) {
            $errors.Add("Placeholder mismatch for ${serviceName}/$($artifact.SourceFile). Expected: $($expectedTokens -join ', '). Found: $($foundTokens -join ', ')") | Out-Null
        }

        foreach ($token in $expectedTokens) {
            if ($valueKeys -notcontains $token) {
                $errors.Add("Values file is missing placeholder key $token required by ${serviceName}/$($artifact.SourceFile)") | Out-Null
            }
        }

        switch ($artifact.Format) {
            "json" {
                try {
                    $jsonObject = $content | ConvertFrom-Json
                }
                catch {
                    $errors.Add("JSON parsing failed for ${serviceName}/$($artifact.SourceFile): $($_.Exception.Message)") | Out-Null
                    continue
                }

                foreach ($requiredKey in @($artifact.RequiredJsonKeys)) {
                    if ($requiredKey -notin @($jsonObject.PSObject.Properties.Name)) {
                        $errors.Add("JSON config for ${serviceName}/$($artifact.SourceFile) is missing key: $requiredKey") | Out-Null
                    }
                }
            }
            "ini" {
                foreach ($sectionName in @($artifact.RequiredIniSections)) {
                    $sectionPattern = '(?m)^\[' + [regex]::Escape($sectionName) + '\]\s*$'
                    if ($content -notmatch $sectionPattern) {
                        $errors.Add("INI config for ${serviceName}/$($artifact.SourceFile) is missing section [$sectionName].") | Out-Null
                    }
                }
            }
            default {
                $errors.Add("Unsupported config artifact format '$($artifact.Format)' for ${serviceName}/$($artifact.SourceFile)") | Out-Null
            }
        }
    }
}

if ($errors.Count -gt 0) {
    Write-Error ("Service config artifact validation failed:`n- {0}" -f ($errors -join "`n- "))
}

Write-Host "Service config artifact validation completed."
