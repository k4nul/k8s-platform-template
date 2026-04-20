pipeline {
    agent any

    options {
        timestamps()
        disableConcurrentBuilds()
    }

    parameters {
        string(name: 'SEED_ENVIRONMENT_PRESETS', defaultValue: '', description: 'Optional comma-separated preset names from config/environments. Leave blank to use every preset found there, or define a custom selection below.')
        string(name: 'SEED_SELECTION_NAME', defaultValue: '', description: 'Optional custom selection name used when you generate jobs without an environment preset.')
        string(name: 'SEED_PROFILE', defaultValue: '', description: 'Optional bundle profile override when you want a custom selection instead of the preset defaults.')
        string(name: 'SEED_APPLICATIONS', defaultValue: '', description: 'Optional comma-separated application templates for a custom selection.')
        string(name: 'SEED_DATA_SERVICES', defaultValue: '', description: 'Optional comma-separated data services for a custom selection.')
        string(name: 'SEED_VALUES_FILE', defaultValue: '', description: 'Optional values file override for a custom selection.')
        string(name: 'SEED_DOCKER_REGISTRY', defaultValue: '', description: 'Optional registry override for a custom selection.')
        string(name: 'SEED_VERSION', defaultValue: '', description: 'Optional version override for a custom selection.')
        string(name: 'SEED_BUNDLE_OUTPUT_PATH', defaultValue: '', description: 'Optional bundle output path override for a custom selection.')
        string(name: 'SEED_ARCHIVE_PATH', defaultValue: '', description: 'Optional bundle archive path override for a custom selection.')
        string(name: 'SEED_PROMOTION_EXTRACT_PATH', defaultValue: '', description: 'Optional promotion extract path override for a custom selection.')
        string(name: 'SEED_REPO_URL', defaultValue: 'https://github.com/k4nul/k8s-platform-template.git', description: 'Repository URL used by the generated SCM-backed pipeline jobs. Change this if you fork or mirror the template.')
        string(name: 'SEED_BRANCH_SPEC', defaultValue: '*/main', description: 'Git branch spec used by the generated SCM-backed pipeline jobs.')
        string(name: 'SEED_SCM_CREDENTIALS_ID', defaultValue: '', description: 'Optional Jenkins credentials ID used for SCM checkout in the generated jobs.')
        string(name: 'SEED_JOB_ROOT', defaultValue: 'platform', description: 'Root Jenkins folder for validation, delivery, and promotion jobs.')
        string(name: 'SEED_SERVICE_JOB_ROOT', defaultValue: 'services', description: 'Root Jenkins folder for service image jobs.')
        string(name: 'SEED_OUTPUT_PATH', defaultValue: 'out/jenkins/seed-job-dsl.groovy', description: 'Workspace-relative path where the generated Job DSL Groovy file will be written.')
        booleanParam(name: 'SEED_INCLUDE_JENKINS', defaultValue: false, description: 'Include Jenkins-related bundle components in the generated bundle job parameter defaults.')
        booleanParam(name: 'SEED_SKIP_SERVICE_JOBS', defaultValue: false, description: 'Skip service image pipeline job generation and only generate the bundle job chain.')
        booleanParam(name: 'SEED_USE_LIGHTWEIGHT_CHECKOUT', defaultValue: true, description: 'Enable lightweight checkout on the generated SCM-backed pipeline jobs.')
        booleanParam(name: 'SEED_APPLY_JOB_DSL', defaultValue: false, description: 'Apply the generated Job DSL immediately by using the Jenkins Job DSL plugin.')
        choice(name: 'SEED_REMOVED_JOB_ACTION', choices: ['IGNORE', 'DISABLE', 'DELETE'], description: 'Behavior for previously generated jobs that are missing from the refreshed DSL when SEED_APPLY_JOB_DSL is enabled.')
    }

    environment {
        SEED_ENVIRONMENT_PRESETS = "${params.SEED_ENVIRONMENT_PRESETS}"
        SEED_SELECTION_NAME = "${params.SEED_SELECTION_NAME}"
        SEED_PROFILE = "${params.SEED_PROFILE}"
        SEED_APPLICATIONS = "${params.SEED_APPLICATIONS}"
        SEED_DATA_SERVICES = "${params.SEED_DATA_SERVICES}"
        SEED_VALUES_FILE = "${params.SEED_VALUES_FILE}"
        SEED_DOCKER_REGISTRY = "${params.SEED_DOCKER_REGISTRY}"
        SEED_VERSION = "${params.SEED_VERSION}"
        SEED_BUNDLE_OUTPUT_PATH = "${params.SEED_BUNDLE_OUTPUT_PATH}"
        SEED_ARCHIVE_PATH = "${params.SEED_ARCHIVE_PATH}"
        SEED_PROMOTION_EXTRACT_PATH = "${params.SEED_PROMOTION_EXTRACT_PATH}"
        SEED_REPO_URL = "${params.SEED_REPO_URL}"
        SEED_BRANCH_SPEC = "${params.SEED_BRANCH_SPEC}"
        SEED_SCM_CREDENTIALS_ID = "${params.SEED_SCM_CREDENTIALS_ID}"
        SEED_JOB_ROOT = "${params.SEED_JOB_ROOT}"
        SEED_SERVICE_JOB_ROOT = "${params.SEED_SERVICE_JOB_ROOT}"
        SEED_OUTPUT_PATH = "${params.SEED_OUTPUT_PATH}"
        SEED_INCLUDE_JENKINS = "${params.SEED_INCLUDE_JENKINS}"
        SEED_SKIP_SERVICE_JOBS = "${params.SEED_SKIP_SERVICE_JOBS}"
        SEED_USE_LIGHTWEIGHT_CHECKOUT = "${params.SEED_USE_LIGHTWEIGHT_CHECKOUT}"
        SEED_APPLY_JOB_DSL = "${params.SEED_APPLY_JOB_DSL}"
        SEED_REMOVED_JOB_ACTION = "${params.SEED_REMOVED_JOB_ACTION}"
    }

    stages {
        stage('Seed Preflight') {
            steps {
                pwsh '''
$scriptPath = Join-Path $env:WORKSPACE 'scripts\\validate-workstation.ps1'
& $scriptPath `
    -ProfileName 'job seed generation agent' `
    -RequiredTools @() `
    -OptionalTools @('git') `
    -Strict
'''
            }
        }

        stage('Generate Job DSL') {
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

function Add-OptionalStringArgument {
    param(
        [System.Collections.Generic.List[string]]$Arguments,
        [string]$Name,
        [string]$Value
    )

    if (-not $Value) {
        return
    }

    $Arguments.Add($Name) | Out-Null
    $Arguments.Add($Value) | Out-Null
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

$scriptPath = Join-Path $env:WORKSPACE 'scripts\\export-jenkins-job-dsl.ps1'
$arguments = [System.Collections.Generic.List[string]]::new()
$arguments.Add('-RepoRoot') | Out-Null
$arguments.Add($env:WORKSPACE) | Out-Null
$arguments.Add('-OutputPath') | Out-Null
$arguments.Add($env:SEED_OUTPUT_PATH) | Out-Null
$arguments.Add('-BranchSpec') | Out-Null
$arguments.Add($env:SEED_BRANCH_SPEC) | Out-Null
$arguments.Add('-JobRoot') | Out-Null
$arguments.Add($env:SEED_JOB_ROOT) | Out-Null
$arguments.Add('-ServiceJobRoot') | Out-Null
$arguments.Add($env:SEED_SERVICE_JOB_ROOT) | Out-Null
$arguments.Add('-UseLightweightCheckout') | Out-Null
$arguments.Add($env:SEED_USE_LIGHTWEIGHT_CHECKOUT) | Out-Null

Add-OptionalListArgument -Arguments $arguments -Name '-EnvironmentPreset' -Value $env:SEED_ENVIRONMENT_PRESETS
Add-OptionalListArgument -Arguments $arguments -Name '-Applications' -Value $env:SEED_APPLICATIONS
Add-OptionalListArgument -Arguments $arguments -Name '-DataServices' -Value $env:SEED_DATA_SERVICES
Add-OptionalStringArgument -Arguments $arguments -Name '-SelectionName' -Value $env:SEED_SELECTION_NAME
Add-OptionalStringArgument -Arguments $arguments -Name '-Profile' -Value $env:SEED_PROFILE
Add-OptionalStringArgument -Arguments $arguments -Name '-ValuesFile' -Value $env:SEED_VALUES_FILE
Add-OptionalStringArgument -Arguments $arguments -Name '-DockerRegistry' -Value $env:SEED_DOCKER_REGISTRY
Add-OptionalStringArgument -Arguments $arguments -Name '-Version' -Value $env:SEED_VERSION
Add-OptionalStringArgument -Arguments $arguments -Name '-BundleOutputPath' -Value $env:SEED_BUNDLE_OUTPUT_PATH
Add-OptionalStringArgument -Arguments $arguments -Name '-ArchivePath' -Value $env:SEED_ARCHIVE_PATH
Add-OptionalStringArgument -Arguments $arguments -Name '-PromotionExtractPath' -Value $env:SEED_PROMOTION_EXTRACT_PATH
Add-OptionalStringArgument -Arguments $arguments -Name '-RepoUrl' -Value $env:SEED_REPO_URL
Add-OptionalStringArgument -Arguments $arguments -Name '-ScmCredentialsId' -Value $env:SEED_SCM_CREDENTIALS_ID
Add-OptionalSwitch -Arguments $arguments -Name '-IncludeJenkins' -Value $env:SEED_INCLUDE_JENKINS
Add-OptionalSwitch -Arguments $arguments -Name '-SkipServiceJobs' -Value $env:SEED_SKIP_SERVICE_JOBS

& $scriptPath @($arguments.ToArray())
'''
            }
        }

        stage('Apply Job DSL') {
            when {
                expression { return params.SEED_APPLY_JOB_DSL }
            }
            steps {
                script {
                    jobDsl(
                        targets: params.SEED_OUTPUT_PATH.replace('\\', '/'),
                        removedJobAction: params.SEED_REMOVED_JOB_ACTION,
                        removedViewAction: 'IGNORE',
                        lookupStrategy: 'JENKINS_ROOT'
                    )
                }
            }
        }
    }

    post {
        always {
            archiveArtifacts artifacts: params.SEED_OUTPUT_PATH.replace('\\', '/'), allowEmptyArchive: true, fingerprint: true
        }
    }
}
