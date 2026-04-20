pipeline {
    agent any

    options {
        timestamps()
        disableConcurrentBuilds()
    }

    parameters {
        string(name: 'VALIDATION_ENVIRONMENT_PRESET', defaultValue: '', description: 'Optional environment preset name from config/environments.')
        string(name: 'VALIDATION_PROFILE', defaultValue: 'web-platform', description: 'Bundle profile to validate.')
        string(name: 'VALIDATION_APPLICATIONS', defaultValue: 'nginx-web,httpbin,whoami', description: 'Comma-separated application templates to include.')
        string(name: 'VALIDATION_DATA_SERVICES', defaultValue: 'redis', description: 'Comma-separated data services to include.')
        string(name: 'VALIDATION_VALUES_FILE', defaultValue: 'config/platform-values.env.example', description: 'Values file path, relative to the repository root unless absolute.')
        string(name: 'VALIDATION_HELM_CONFIG_FILE', defaultValue: 'config/helm-releases.psd1', description: 'Helm release catalog path, relative to the repository root unless absolute.')
        string(name: 'VALIDATION_DOCKER_REGISTRY', defaultValue: '', description: 'Optional registry override. Leave blank when using only public images.')
        string(name: 'VALIDATION_VERSION', defaultValue: '0.0.0-ci', description: 'Image tag version used for temporary render validation.')
        string(name: 'VALIDATION_RENDERED_PATH', defaultValue: '', description: 'Optional existing rendered bundle path for validating an already prepared bundle.')
        booleanParam(name: 'VALIDATION_INCLUDE_JENKINS', defaultValue: false, description: 'Include Jenkins deployment components in the selected bundle.')
        booleanParam(name: 'VALIDATION_PREPARE_HELM_REPOS', defaultValue: false, description: 'Refresh Helm repositories before Helm rendering.')
        booleanParam(name: 'VALIDATION_STRICT', defaultValue: false, description: 'Enable strict rendered-bundle and Helm validation modes.')
        booleanParam(name: 'VALIDATION_VALIDATE_CRD_BACKED_RESOURCES', defaultValue: false, description: 'Include CRD-backed manifests in dry-run validation when the agent cluster has the CRDs installed.')
        booleanParam(name: 'VALIDATION_REQUIRE_BOOTSTRAP_SECRETS_READY', defaultValue: false, description: 'Fail if generated bootstrap secret templates still contain placeholders.')
        booleanParam(name: 'VALIDATION_SKIP_TEMPLATE_VALIDATION', defaultValue: false, description: 'Skip repository template validation and only run workstation or bundle checks.')
        booleanParam(name: 'VALIDATION_SKIP_WORKSTATION_VALIDATION', defaultValue: false, description: 'Skip workstation tool checks.')
        booleanParam(name: 'VALIDATION_SKIP_PLATFORM_ASSET_VALIDATION', defaultValue: false, description: 'Skip rendered bundle validation and only run repository-level checks.')
    }

    environment {
        VALIDATION_ENVIRONMENT_PRESET = "${params.VALIDATION_ENVIRONMENT_PRESET}"
        VALIDATION_PROFILE = "${params.VALIDATION_PROFILE}"
        VALIDATION_APPLICATIONS = "${params.VALIDATION_APPLICATIONS}"
        VALIDATION_DATA_SERVICES = "${params.VALIDATION_DATA_SERVICES}"
        VALIDATION_VALUES_FILE = "${params.VALIDATION_VALUES_FILE}"
        VALIDATION_HELM_CONFIG_FILE = "${params.VALIDATION_HELM_CONFIG_FILE}"
        VALIDATION_DOCKER_REGISTRY = "${params.VALIDATION_DOCKER_REGISTRY}"
        VALIDATION_VERSION = "${params.VALIDATION_VERSION}"
        VALIDATION_RENDERED_PATH = "${params.VALIDATION_RENDERED_PATH}"
        VALIDATION_INCLUDE_JENKINS = "${params.VALIDATION_INCLUDE_JENKINS}"
        VALIDATION_PREPARE_HELM_REPOS = "${params.VALIDATION_PREPARE_HELM_REPOS}"
        VALIDATION_STRICT = "${params.VALIDATION_STRICT}"
        VALIDATION_VALIDATE_CRD_BACKED_RESOURCES = "${params.VALIDATION_VALIDATE_CRD_BACKED_RESOURCES}"
        VALIDATION_REQUIRE_BOOTSTRAP_SECRETS_READY = "${params.VALIDATION_REQUIRE_BOOTSTRAP_SECRETS_READY}"
        VALIDATION_SKIP_TEMPLATE_VALIDATION = "${params.VALIDATION_SKIP_TEMPLATE_VALIDATION}"
        VALIDATION_SKIP_WORKSTATION_VALIDATION = "${params.VALIDATION_SKIP_WORKSTATION_VALIDATION}"
        VALIDATION_SKIP_PLATFORM_ASSET_VALIDATION = "${params.VALIDATION_SKIP_PLATFORM_ASSET_VALIDATION}"
    }

    stages {
        stage('Agent Readiness') {
            steps {
                pwsh '''
function Test-TrueValue {
    param(
        [AllowEmptyString()]
        [string]$Value
    )

    return ($Value -and $Value.Equals('true', [System.StringComparison]::OrdinalIgnoreCase))
}

$scriptPath = Join-Path $env:WORKSPACE 'scripts\\validate-workstation.ps1'
$requiredTools = [System.Collections.Generic.List[string]]::new()

if (-not (Test-TrueValue -Value $env:VALIDATION_SKIP_WORKSTATION_VALIDATION) -or -not (Test-TrueValue -Value $env:VALIDATION_SKIP_PLATFORM_ASSET_VALIDATION)) {
    $requiredTools.Add('kubectl') | Out-Null
    $requiredTools.Add('helm') | Out-Null
}

& $scriptPath `
    -ProfileName 'repository validation agent' `
    -RequiredTools @($requiredTools.ToArray()) `
    -OptionalTools @('git', 'docker', 'python') `
    -Strict
'''
            }
        }

        stage('Repository Validation') {
            steps {
                pwsh '''
function Add-OptionalListArgument {
    param(
        [System.Collections.Generic.List[string]]$Arguments,
        [string]$Name,
        [string]$Value
    )

    if (-not $Value) {
        return
    }

    $entries = @($Value -split '\\s*,\\s*' | Where-Object { $_ })
    if ($entries.Count -eq 0) {
        return
    }

    $Arguments.Add($Name) | Out-Null
    foreach ($entry in $entries) {
        $Arguments.Add($entry) | Out-Null
    }
}

function Add-OptionalSwitch {
    param(
        [System.Collections.Generic.List[string]]$Arguments,
        [string]$Name,
        [string]$Value
    )

    if ($Value -and $Value.Equals('true', [System.StringComparison]::OrdinalIgnoreCase)) {
        $Arguments.Add($Name) | Out-Null
    }
}

$scriptPath = Join-Path $env:WORKSPACE 'scripts\\invoke-repository-validation.ps1'
$arguments = [System.Collections.Generic.List[string]]::new()
$arguments.Add('-RepoRoot') | Out-Null
$arguments.Add($env:WORKSPACE) | Out-Null
if ($env:VALIDATION_ENVIRONMENT_PRESET) {
    $arguments.Add('-EnvironmentPreset') | Out-Null
    $arguments.Add($env:VALIDATION_ENVIRONMENT_PRESET) | Out-Null
}
$arguments.Add('-Profile') | Out-Null
$arguments.Add($env:VALIDATION_PROFILE) | Out-Null
$arguments.Add('-ValuesFile') | Out-Null
$arguments.Add($env:VALIDATION_VALUES_FILE) | Out-Null
$arguments.Add('-HelmConfigFile') | Out-Null
$arguments.Add($env:VALIDATION_HELM_CONFIG_FILE) | Out-Null
if ($env:VALIDATION_DOCKER_REGISTRY) {
    $arguments.Add('-DockerRegistry') | Out-Null
    $arguments.Add($env:VALIDATION_DOCKER_REGISTRY) | Out-Null
}
$arguments.Add('-Version') | Out-Null
$arguments.Add($env:VALIDATION_VERSION) | Out-Null

Add-OptionalListArgument -Arguments $arguments -Name '-Applications' -Value $env:VALIDATION_APPLICATIONS
Add-OptionalListArgument -Arguments $arguments -Name '-DataServices' -Value $env:VALIDATION_DATA_SERVICES

if ($env:VALIDATION_RENDERED_PATH) {
    $arguments.Add('-RenderedPath') | Out-Null
    $arguments.Add($env:VALIDATION_RENDERED_PATH) | Out-Null
}

Add-OptionalSwitch -Arguments $arguments -Name '-IncludeJenkins' -Value $env:VALIDATION_INCLUDE_JENKINS
Add-OptionalSwitch -Arguments $arguments -Name '-PrepareHelmRepos' -Value $env:VALIDATION_PREPARE_HELM_REPOS
Add-OptionalSwitch -Arguments $arguments -Name '-Strict' -Value $env:VALIDATION_STRICT
Add-OptionalSwitch -Arguments $arguments -Name '-ValidateCrdBackedResources' -Value $env:VALIDATION_VALIDATE_CRD_BACKED_RESOURCES
Add-OptionalSwitch -Arguments $arguments -Name '-RequireBootstrapSecretsReady' -Value $env:VALIDATION_REQUIRE_BOOTSTRAP_SECRETS_READY
Add-OptionalSwitch -Arguments $arguments -Name '-SkipTemplateValidation' -Value $env:VALIDATION_SKIP_TEMPLATE_VALIDATION
Add-OptionalSwitch -Arguments $arguments -Name '-SkipWorkstationValidation' -Value $env:VALIDATION_SKIP_WORKSTATION_VALIDATION
Add-OptionalSwitch -Arguments $arguments -Name '-SkipPlatformAssetValidation' -Value $env:VALIDATION_SKIP_PLATFORM_ASSET_VALIDATION

& $scriptPath @($arguments.ToArray())
'''
            }
        }
    }
}
