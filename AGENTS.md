schema_version: "1.0"
project:
  id: "k8s-platform-template"
  type: "devops.template.kubernetes"
  status: "active"
scope:
  owns:
    - "k8s/"
    - "services/"
    - "config/platform-values*.env"
    - "config/profiles/"
    - "config/environments/"
    - "cluster bundle rendering scripts"
  excludes:
    jenkins:
      repository: "../jenkins-pipeline-template"
      patterns:
        - "Jenkinsfile"
        - "Job DSL"
        - "Jenkins controller manifests"
        - "service pipeline catalog"
    docker:
      repository: "../docker-build-template"
      patterns:
        - "Dockerfile template maintenance"
        - "buildx image publishing"
    cloud:
      repository: "../cloud-infra-template"
      patterns:
        - "Terraform modules"
        - "VPC/IAM/network infrastructure"
instructions:
  edit_policy:
    preserve_template_shape: true
    prefer_existing_powershell_helpers: true
    keep_public_image_defaults: true
    avoid_private_environment_assumptions: true
  generated_output:
    default_root: "out/"
    commit_generated_bundles: false
  validation:
    required:
      - command: "pwsh -NoProfile -File scripts/validate-template.ps1"
        when: "template scripts or catalogs change"
    optional:
      - command: "pwsh -NoProfile -File scripts/invoke-repository-validation.ps1 -EnvironmentPreset dev"
        when: "bundle rendering behavior changes"
automation:
  enabled: true
  entrypoints:
    validate: "scripts/validate-template.ps1"
    render: "scripts/render-platform-assets.ps1"
    deliver: "scripts/invoke-bundle-delivery.ps1"
