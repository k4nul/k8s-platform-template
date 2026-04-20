param(
    [string]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if (-not $PSBoundParameters.ContainsKey("RepoRoot") -or -not $RepoRoot) {
    $RepoRoot = Join-Path $PSScriptRoot ".."
}

$root = (Resolve-Path -Path $RepoRoot).Path
$servicesRoot = Join-Path $root "services"
$catalogPath = Join-Path $root "config\service-builds.psd1"
$catalog = Import-PowerShellDataFile -Path $catalogPath
$errors = New-Object System.Collections.Generic.List[string]

$catalogMap = [ordered]@{}
foreach ($service in @($catalog.Services | Sort-Object { $_.Name })) {
    $catalogMap[$service.Name] = $service
}

$serviceDirectories = @(Get-ChildItem -Path $servicesRoot -Directory | Sort-Object Name | Select-Object -ExpandProperty Name)
$missingEntries = @($serviceDirectories | Where-Object { -not $catalogMap.Contains($_) })
$missingDirectories = @($catalogMap.Keys | Where-Object { $serviceDirectories -notcontains $_ })

foreach ($item in $missingEntries) {
    $errors.Add("Service directory is missing from config/service-builds.psd1: $item") | Out-Null
}

foreach ($item in $missingDirectories) {
    $errors.Add("Build catalog entry is missing service directory: $item") | Out-Null
}

foreach ($serviceName in $catalogMap.Keys) {
    $definition = $catalogMap[$serviceName]
    $serviceRoot = Join-Path $servicesRoot $serviceName
    $composePath = Join-Path $serviceRoot "docker-compose.yaml"
    $readmePath = Join-Path $serviceRoot "README.md"

    if (-not (Test-Path -Path $composePath -PathType Leaf)) {
        $errors.Add("Missing docker-compose.yaml for ${serviceName}: services/$serviceName/docker-compose.yaml") | Out-Null
    }

    if (-not (Test-Path -Path $readmePath -PathType Leaf)) {
        $errors.Add("Missing README.md for ${serviceName}: services/$serviceName/README.md") | Out-Null
    }

    $sourceType = if ($definition.ContainsKey("SourceType")) { [string]$definition.SourceType } else { "" }
    if ($sourceType -ne "public-image") {
        $errors.Add("Unsupported service build source type for ${serviceName}: $sourceType") | Out-Null
        continue
    }

    if (-not $definition.ContainsKey("PublicImage") -or -not [string]$definition.PublicImage) {
        $errors.Add("Build catalog entry for ${serviceName} is missing PublicImage.") | Out-Null
        continue
    }

    if (Test-Path -Path $composePath -PathType Leaf) {
        $composeContent = Get-Content -Path $composePath -Raw
        if (-not $composeContent.Contains("image: $($definition.PublicImage)")) {
            $errors.Add("docker-compose for ${serviceName} should reference the public image $($definition.PublicImage).") | Out-Null
        }
    }
}

if ($errors.Count -gt 0) {
    Write-Error ("Service build validation failed:`n- {0}" -f ($errors -join "`n- "))
}

Write-Host "Service build validation completed."
