pipeline {
    agent any

    options {
        timestamps()
        disableConcurrentBuilds()
    }

    parameters {
        string(name: 'BUNDLE_ENVIRONMENT_PRESET', defaultValue: '', description: 'Optional environment preset name from config/environments.')
        string(name: 'BUNDLE_PROFILE', defaultValue: 'web-platform', description: 'Bundle profile to render.')
        string(name: 'BUNDLE_APPLICATIONS', defaultValue: 'nginx-web,httpbin,whoami', description: 'Comma-separated application templates to include.')
        string(name: 'BUNDLE_DATA_SERVICES', defaultValue: 'redis', description: 'Comma-separated data services to include.')
        string(name: 'BUNDLE_VALUES_FILE', defaultValue: 'config/platform-values.env.example', description: 'Values file path, relative to the repository root unless absolute.')
        string(name: 'BUNDLE_HELM_CONFIG_FILE', defaultValue: 'config/helm-releases.psd1', description: 'Helm release catalog path, relative to the repository root unless absolute.')
        string(name: 'BUNDLE_OUTPUT_PATH', defaultValue: 'out/ci/web-platform', description: 'Rendered bundle output path, relative to the workspace unless absolute.')
        string(name: 'BUNDLE_ARCHIVE_PATH', defaultValue: 'out/ci/web-platform.zip', description: 'Archive destination path, relative to the workspace unless absolute.')
        string(name: 'BUNDLE_DOCKER_REGISTRY', defaultValue: '', description: 'Optional registry override. Leave blank when using only public images.')
        string(name: 'BUNDLE_VERSION', defaultValue: '0.0.0-ci', description: 'Image tag version used for bundle rendering.')
        booleanParam(name: 'BUNDLE_INCLUDE_JENKINS', defaultValue: false, description: 'Include Jenkins deployment components in the selected bundle.')
        booleanParam(name: 'BUNDLE_PREPARE_HELM_REPOS', defaultValue: false, description: 'Refresh Helm repositories before bundle validation or deployment.')
        booleanParam(name: 'BUNDLE_INCLUDE_DEFERRED_COMPONENTS', defaultValue: false, description: 'Include deferred manifests during bundle validation or deployment.')
        booleanParam(name: 'BUNDLE_REQUIRE_BOOTSTRAP_SECRETS_READY', defaultValue: false, description: 'Fail if generated bootstrap secret YAML files still contain placeholders.')
        booleanParam(name: 'BUNDLE_REQUIRE_BOOTSTRAP_STATUS', defaultValue: false, description: 'Fail if bootstrap namespaces or secrets are not present in the current cluster context.')
        booleanParam(name: 'BUNDLE_CLEAN_OUTPUT', defaultValue: true, description: 'Replace the existing output directory before rendering the bundle.')
        booleanParam(name: 'BUNDLE_OVERWRITE_ARCHIVE', defaultValue: true, description: 'Replace the existing bundle archive before writing a new one.')
        booleanParam(name: 'BUNDLE_SKIP_REPOSITORY_VALIDATION', defaultValue: false, description: 'Skip repository preflight validation before rendering.')
        booleanParam(name: 'BUNDLE_SKIP_TEMPLATE_VALIDATION', defaultValue: false, description: 'Skip repository template validation inside the preflight stage.')
        booleanParam(name: 'BUNDLE_SKIP_WORKSTATION_VALIDATION', defaultValue: false, description: 'Skip workstation tool validation inside the preflight stage.')
        booleanParam(name: 'BUNDLE_SKIP_BUNDLE_VALIDATION', defaultValue: false, description: 'Skip validate-bundle.ps1 after rendering.')
        booleanParam(name: 'BUNDLE_SKIP_ARCHIVE', defaultValue: false, description: 'Skip archive creation for the rendered bundle.')
        booleanParam(name: 'BUNDLE_DEPLOY', defaultValue: false, description: 'Run deploy-bundle.ps1 after rendering and validation.')
        booleanParam(name: 'BUNDLE_DEPLOY_DRY_RUN', defaultValue: true, description: 'Run deployment in dry-run mode when BUNDLE_DEPLOY is enabled.')
    }

    environment {
        BUNDLE_ENVIRONMENT_PRESET = "${params.BUNDLE_ENVIRONMENT_PRESET}"
        BUNDLE_PROFILE = "${params.BUNDLE_PROFILE}"
        BUNDLE_APPLICATIONS = "${params.BUNDLE_APPLICATIONS}"
        BUNDLE_DATA_SERVICES = "${params.BUNDLE_DATA_SERVICES}"
        BUNDLE_VALUES_FILE = "${params.BUNDLE_VALUES_FILE}"
        BUNDLE_HELM_CONFIG_FILE = "${params.BUNDLE_HELM_CONFIG_FILE}"
        BUNDLE_OUTPUT_PATH = "${params.BUNDLE_OUTPUT_PATH}"
        BUNDLE_ARCHIVE_PATH = "${params.BUNDLE_ARCHIVE_PATH}"
        BUNDLE_DOCKER_REGISTRY = "${params.BUNDLE_DOCKER_REGISTRY}"
        BUNDLE_VERSION = "${params.BUNDLE_VERSION}"
        BUNDLE_INCLUDE_JENKINS = "${params.BUNDLE_INCLUDE_JENKINS}"
        BUNDLE_PREPARE_HELM_REPOS = "${params.BUNDLE_PREPARE_HELM_REPOS}"
        BUNDLE_INCLUDE_DEFERRED_COMPONENTS = "${params.BUNDLE_INCLUDE_DEFERRED_COMPONENTS}"
        BUNDLE_REQUIRE_BOOTSTRAP_SECRETS_READY = "${params.BUNDLE_REQUIRE_BOOTSTRAP_SECRETS_READY}"
        BUNDLE_REQUIRE_BOOTSTRAP_STATUS = "${params.BUNDLE_REQUIRE_BOOTSTRAP_STATUS}"
        BUNDLE_CLEAN_OUTPUT = "${params.BUNDLE_CLEAN_OUTPUT}"
        BUNDLE_OVERWRITE_ARCHIVE = "${params.BUNDLE_OVERWRITE_ARCHIVE}"
        BUNDLE_SKIP_REPOSITORY_VALIDATION = "${params.BUNDLE_SKIP_REPOSITORY_VALIDATION}"
        BUNDLE_SKIP_TEMPLATE_VALIDATION = "${params.BUNDLE_SKIP_TEMPLATE_VALIDATION}"
        BUNDLE_SKIP_WORKSTATION_VALIDATION = "${params.BUNDLE_SKIP_WORKSTATION_VALIDATION}"
        BUNDLE_SKIP_BUNDLE_VALIDATION = "${params.BUNDLE_SKIP_BUNDLE_VALIDATION}"
        BUNDLE_SKIP_ARCHIVE = "${params.BUNDLE_SKIP_ARCHIVE}"
        BUNDLE_DEPLOY = "${params.BUNDLE_DEPLOY}"
        BUNDLE_DEPLOY_DRY_RUN = "${params.BUNDLE_DEPLOY_DRY_RUN}"
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
$needsClusterTools =
    -not (Test-TrueValue -Value $env:BUNDLE_SKIP_BUNDLE_VALIDATION) -or
    (Test-TrueValue -Value $env:BUNDLE_DEPLOY) -or
    (Test-TrueValue -Value $env:BUNDLE_REQUIRE_BOOTSTRAP_STATUS) -or
    (Test-TrueValue -Value $env:BUNDLE_REQUIRE_BOOTSTRAP_SECRETS_READY) -or
    (Test-TrueValue -Value $env:BUNDLE_PREPARE_HELM_REPOS) -or
    (
        -not (Test-TrueValue -Value $env:BUNDLE_SKIP_REPOSITORY_VALIDATION) -and
        -not (Test-TrueValue -Value $env:BUNDLE_SKIP_WORKSTATION_VALIDATION)
    )

if ($needsClusterTools) {
    $requiredTools.Add('kubectl') | Out-Null
    $requiredTools.Add('helm') | Out-Null
}

& $scriptPath `
    -ProfileName 'bundle delivery agent' `
    -RequiredTools @($requiredTools.ToArray()) `
    -OptionalTools @('git', 'docker', 'python') `
    -Strict
'''
            }
        }

        stage('Bundle Delivery') {
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

$scriptPath = Join-Path $env:WORKSPACE 'scripts\\invoke-bundle-delivery.ps1'
$arguments = [System.Collections.Generic.List[string]]::new()
$arguments.Add('-RepoRoot') | Out-Null
$arguments.Add($env:WORKSPACE) | Out-Null
if ($env:BUNDLE_ENVIRONMENT_PRESET) {
    $arguments.Add('-EnvironmentPreset') | Out-Null
    $arguments.Add($env:BUNDLE_ENVIRONMENT_PRESET) | Out-Null
}
$arguments.Add('-OutputPath') | Out-Null
$arguments.Add($env:BUNDLE_OUTPUT_PATH) | Out-Null
$arguments.Add('-Profile') | Out-Null
$arguments.Add($env:BUNDLE_PROFILE) | Out-Null
$arguments.Add('-ValuesFile') | Out-Null
$arguments.Add($env:BUNDLE_VALUES_FILE) | Out-Null
$arguments.Add('-HelmConfigFile') | Out-Null
$arguments.Add($env:BUNDLE_HELM_CONFIG_FILE) | Out-Null
$arguments.Add('-ArchivePath') | Out-Null
$arguments.Add($env:BUNDLE_ARCHIVE_PATH) | Out-Null
if ($env:BUNDLE_DOCKER_REGISTRY) {
    $arguments.Add('-DockerRegistry') | Out-Null
    $arguments.Add($env:BUNDLE_DOCKER_REGISTRY) | Out-Null
}
$arguments.Add('-Version') | Out-Null
$arguments.Add($env:BUNDLE_VERSION) | Out-Null

Add-OptionalListArgument -Arguments $arguments -Name '-Applications' -Value $env:BUNDLE_APPLICATIONS
Add-OptionalListArgument -Arguments $arguments -Name '-DataServices' -Value $env:BUNDLE_DATA_SERVICES

Add-OptionalSwitch -Arguments $arguments -Name '-IncludeJenkins' -Value $env:BUNDLE_INCLUDE_JENKINS
Add-OptionalSwitch -Arguments $arguments -Name '-PrepareHelmRepos' -Value $env:BUNDLE_PREPARE_HELM_REPOS
Add-OptionalSwitch -Arguments $arguments -Name '-IncludeDeferredComponents' -Value $env:BUNDLE_INCLUDE_DEFERRED_COMPONENTS
Add-OptionalSwitch -Arguments $arguments -Name '-RequireBootstrapSecretsReady' -Value $env:BUNDLE_REQUIRE_BOOTSTRAP_SECRETS_READY
Add-OptionalSwitch -Arguments $arguments -Name '-RequireBootstrapStatus' -Value $env:BUNDLE_REQUIRE_BOOTSTRAP_STATUS
Add-OptionalSwitch -Arguments $arguments -Name '-CleanOutput' -Value $env:BUNDLE_CLEAN_OUTPUT
Add-OptionalSwitch -Arguments $arguments -Name '-OverwriteArchive' -Value $env:BUNDLE_OVERWRITE_ARCHIVE
Add-OptionalSwitch -Arguments $arguments -Name '-SkipRepositoryValidation' -Value $env:BUNDLE_SKIP_REPOSITORY_VALIDATION
Add-OptionalSwitch -Arguments $arguments -Name '-SkipTemplateValidation' -Value $env:BUNDLE_SKIP_TEMPLATE_VALIDATION
Add-OptionalSwitch -Arguments $arguments -Name '-SkipWorkstationValidation' -Value $env:BUNDLE_SKIP_WORKSTATION_VALIDATION
Add-OptionalSwitch -Arguments $arguments -Name '-SkipBundleValidation' -Value $env:BUNDLE_SKIP_BUNDLE_VALIDATION
Add-OptionalSwitch -Arguments $arguments -Name '-SkipArchive' -Value $env:BUNDLE_SKIP_ARCHIVE
Add-OptionalSwitch -Arguments $arguments -Name '-DeployBundle' -Value $env:BUNDLE_DEPLOY
Add-OptionalSwitch -Arguments $arguments -Name '-DeploymentDryRun' -Value $env:BUNDLE_DEPLOY_DRY_RUN

& $scriptPath @($arguments.ToArray())
'''
            }
        }
    }

    post {
        always {
            script {
                def archivePatterns = []
                if (params.BUNDLE_OUTPUT_PATH?.trim()) {
                    archivePatterns << "${params.BUNDLE_OUTPUT_PATH.replace('\\', '/')}/**"
                }
                if (!params.BUNDLE_SKIP_ARCHIVE && params.BUNDLE_ARCHIVE_PATH?.trim()) {
                    archivePatterns << params.BUNDLE_ARCHIVE_PATH.replace('\\', '/')
                }

                if (!archivePatterns.isEmpty()) {
                    archiveArtifacts artifacts: archivePatterns.join(','), allowEmptyArchive: true, fingerprint: true
                }
            }
        }
    }
}
