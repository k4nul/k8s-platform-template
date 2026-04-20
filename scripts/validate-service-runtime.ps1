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
$catalogPath = Join-Path $root "config\service-runtime-bindings.psd1"
$envExamplePath = Join-Path $root "config\service-runtime.env.example"
$catalog = Import-PowerShellDataFile -Path $catalogPath
$errors = New-Object System.Collections.Generic.List[string]

$catalogMap = [ordered]@{}
foreach ($service in @($catalog.Services | Sort-Object { $_.Name })) {
    $catalogMap[$service.Name] = $service
}

$serviceDirectories = @(Get-ChildItem -Path $servicesRoot -Directory | Sort-Object Name | Select-Object -ExpandProperty Name)
$missingEntries = @($serviceDirectories | Where-Object { -not $catalogMap.Contains($_) })
$missingDirectories = @($catalogMap.Keys | Where-Object { $serviceDirectories -notcontains $_ })
$envExampleContent = Get-Content -Path $envExamplePath -Raw

foreach ($item in $missingEntries) {
    $errors.Add("Service directory is missing from config/service-runtime-bindings.psd1: $item") | Out-Null
}

foreach ($item in $missingDirectories) {
    $errors.Add("Runtime catalog entry is missing service directory: $item") | Out-Null
}

foreach ($variableName in @($catalog.Variables.Keys)) {
    $variablePattern = '(?m)^' + [regex]::Escape($variableName) + '='
    if ($envExampleContent -notmatch $variablePattern) {
        $errors.Add("config/service-runtime.env.example is missing variable: $variableName") | Out-Null
    }
}

foreach ($serviceName in $catalogMap.Keys) {
    $definition = $catalogMap[$serviceName]
    $composePath = Join-Path $servicesRoot ($serviceName + "\docker-compose.yaml")
    if (-not (Test-Path -Path $composePath -PathType Leaf)) {
        $errors.Add("Missing compose file for ${serviceName}: services/$serviceName/docker-compose.yaml") | Out-Null
        continue
    }

    $composeContent = Get-Content -Path $composePath -Raw
    $extractedEnvVars = @(
        [regex]::Matches($composeContent, '\$\{([A-Z0-9_]+):\?') |
            ForEach-Object { $_.Groups[1].Value } |
            Sort-Object -Unique
    )

    $expectedEnvVars = @($definition.RequiredEnvVars | Sort-Object -Unique)
    if ((@($extractedEnvVars) -join ",") -ne (@($expectedEnvVars) -join ",")) {
        $errors.Add("Runtime env var mismatch for ${serviceName}. Expected: $($expectedEnvVars -join ', '). Found: $($extractedEnvVars -join ', ')") | Out-Null
    }

    foreach ($requiredString in @("version: '3'", "services:", ($definition.ComposeServiceName + ":")) + @($definition.RequiredComposeStrings)) {
        if (-not $composeContent.Contains($requiredString)) {
            $errors.Add("docker-compose for ${serviceName} is missing expected text: $requiredString") | Out-Null
        }
    }

    foreach ($variableName in @($definition.RequiredEnvVars)) {
        if (-not $catalog.Variables.ContainsKey($variableName)) {
            $errors.Add("Runtime catalog for ${serviceName} references unknown variable: $variableName") | Out-Null
        }
    }

    if ($definition.RequiresHostGateway -and -not $composeContent.Contains('host.docker.internal:host-gateway')) {
        $errors.Add("docker-compose for ${serviceName} should include host.docker.internal host-gateway mapping.") | Out-Null
    }

    if ($definition.ContainerName -and -not $composeContent.Contains("CONTAINER_NAME=$($definition.ContainerName)")) {
        $errors.Add("docker-compose for ${serviceName} should set CONTAINER_NAME=$($definition.ContainerName).") | Out-Null
    }

    if ($definition.RestartPolicy -eq "always" -and -not $composeContent.Contains('restart: always')) {
        $errors.Add("docker-compose for ${serviceName} should set restart: always.") | Out-Null
    }

    if ($definition.RestartPolicy -eq "default" -and $composeContent.Contains('restart: always')) {
        $errors.Add("docker-compose for ${serviceName} should not force restart: always.") | Out-Null
    }
}

if ($errors.Count -gt 0) {
    Write-Error ("Service runtime validation failed:`n- {0}" -f ($errors -join "`n- "))
}

Write-Host "Service runtime validation completed."
