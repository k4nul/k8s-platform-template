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
$catalogPath = Join-Path $root "config\service-pipelines.psd1"
$catalog = Import-PowerShellDataFile -Path $catalogPath

$catalogMap = [ordered]@{}
foreach ($service in @($catalog.Services | Sort-Object { $_.Name })) {
    $catalogMap[$service.Name] = $service
}

$serviceDirectories = @(Get-ChildItem -Path $servicesRoot -Directory | Sort-Object Name | Select-Object -ExpandProperty Name)
$missingEntries = @($serviceDirectories | Where-Object { -not $catalogMap.Contains($_) })
$missingDirectories = @($catalogMap.Keys | Where-Object { $serviceDirectories -notcontains $_ })
$errors = New-Object System.Collections.Generic.List[string]

foreach ($item in $missingEntries) {
    $errors.Add("Service directory is missing from config/service-pipelines.psd1: $item") | Out-Null
}

foreach ($item in $missingDirectories) {
    $errors.Add("Catalog entry is missing service directory: $item") | Out-Null
}

foreach ($serviceName in $catalogMap.Keys) {
    $definition = $catalogMap[$serviceName]
    $serviceRoot = Join-Path $servicesRoot $serviceName
    if (-not (Test-Path -Path $serviceRoot -PathType Container)) {
        continue
    }

    foreach ($fileName in @($definition.RequiredFiles)) {
        $filePath = Join-Path $serviceRoot $fileName
        if (-not (Test-Path -Path $filePath -PathType Leaf)) {
            $errors.Add("Missing required service file for ${serviceName}: services/$serviceName/$fileName") | Out-Null
        }
    }

    $jenkinsfilePath = Join-Path $serviceRoot "Jenkinsfile"
    if (-not (Test-Path -Path $jenkinsfilePath -PathType Leaf)) {
        continue
    }

    $jenkinsfile = Get-Content -Path $jenkinsfilePath -Raw

    $generalRequiredStrings = @(
        ('DOCKER_IMAGE = "' + $definition.ImageName + '"'),
        'DOCKER_CREDENTIALS_ID = ',
        'docker.withRegistry(',
        'app.push("${env.BUILD_NUMBER}")'
    )

    foreach ($requiredString in $generalRequiredStrings + @($definition.RequiredJenkinsStrings)) {
        if (-not $jenkinsfile.Contains($requiredString)) {
            $errors.Add("Jenkinsfile for $serviceName is missing expected text: $requiredString") | Out-Null
        }
    }

    if ($definition.UsesCacheToggle -and -not $jenkinsfile.Contains('env.CACHE?.toBoolean()')) {
        $errors.Add("Jenkinsfile for $serviceName should use the safe CACHE toggle pattern env.CACHE?.toBoolean().") | Out-Null
    }

    switch ($definition.BuildTagStrategy) {
        "mode" {
            if (-not $jenkinsfile.Contains('docker.build("${env.MODE}/${DOCKER_IMAGE}"')) {
                $errors.Add("Jenkinsfile for $serviceName should build mode-scoped image tags.") | Out-Null
            }
        }
        "release" {
            if (-not $jenkinsfile.Contains('docker.build("release/${DOCKER_IMAGE}"')) {
                $errors.Add("Jenkinsfile for $serviceName should build release-scoped image tags.") | Out-Null
            }
        }
        "project-prefix" {
            if (-not $jenkinsfile.Contains('docker.build("${PROJECT_NAME}/${DOCKER_IMAGE}"')) {
                $errors.Add("Jenkinsfile for $serviceName should build project-prefixed image tags.") | Out-Null
            }
        }
    }

    if ($definition.RequiresMode -and -not $jenkinsfile.Contains('MODE environment variable must be set')) {
        $errors.Add("Jenkinsfile for $serviceName should fail fast when MODE is missing.") | Out-Null
    }

    if ($definition.UsesModeBuildArg -and -not $jenkinsfile.Contains('--build-arg MODE=${env.MODE}')) {
        $errors.Add("Jenkinsfile for $serviceName should forward MODE as a Docker build argument.") | Out-Null
    }

    $hasComposeUpdate = $jenkinsfile -match 'docker-compose\s+up\s+-d'
    switch ($definition.ComposeUpdate) {
        "none" {
            if ($hasComposeUpdate) {
                $errors.Add("Jenkinsfile for $serviceName should not include a docker-compose update stage.") | Out-Null
            }
        }
        "test-only" {
            if (-not $hasComposeUpdate) {
                $errors.Add("Jenkinsfile for $serviceName should include a docker-compose update stage.") | Out-Null
            }

            if (-not ($jenkinsfile -match 'environment\s+name\s*:\s*["'']MODE["'']\s*,\s*value\s*:\s*["'']test["'']')) {
                $errors.Add("Jenkinsfile for $serviceName should gate compose update to MODE=test.") | Out-Null
            }

            if (-not $jenkinsfile.Contains('stage("Update")')) {
                $errors.Add("Jenkinsfile for $serviceName should use a consistent Update stage name.") | Out-Null
            }
        }
    }
}

if ($errors.Count -gt 0) {
    Write-Error ("Service pipeline validation failed:`n- {0}" -f ($errors -join "`n- "))
}

Write-Host "Service pipeline validation completed."
