# Jenkins

English | [한국어](README.ko.md)

This directory contains generic Jenkins automation for the repository itself. It is designed for repository-level workflows rather than company-specific application pipelines.

## Main Jobs

- `repository-validation.Jenkinsfile`: validates repository structure and rendered assets
- `bundle-delivery.Jenkinsfile`: renders, validates, and archives a bundle
- `bundle-promotion.Jenkinsfile`: re-validates and optionally deploys an archived bundle
- `job-seed.Jenkinsfile`: generates Jenkins folders and pipeline jobs from the shared job plan

## What You Need In Jenkins

The Jenkins agent should have:

- PowerShell or `pwsh`
- `git`
- `kubectl` for cluster-aware validation and manifest workflows
- `helm` for Helm-managed components

Each Jenkinsfile starts with an agent-readiness preflight so missing tools fail early with a clearer message.

## Typical Jenkins Setup Flow

1. Preview the repository-level job plan:

```powershell
.\scripts\show-jenkins-job-plan.ps1 -EnvironmentPreset dev -Format markdown
```

2. Generate Job DSL:

```powershell
.\scripts\export-jenkins-job-dsl.ps1 -EnvironmentPreset dev -OutputPath .\out\jenkins\seed-job-dsl.groovy
```

3. Review the generated DSL and SCM settings.
4. Apply the DSL in Jenkins.
5. Run `repository-validation` before enabling delivery or promotion for a team.

## Important Defaults

- The default sample applications use public images, so per-service image build jobs are not required.
- Service-level jobs appear only if a service actually has its own Jenkinsfile and the catalog marks it as such.
- `job-seed.Jenkinsfile` leaves the preset list blank by default, which means "use every preset currently found in `config/environments`".
- `job-seed.Jenkinsfile` uses `https://github.com/k4nul/k8s-platform-template.git` as the default SCM URL.

If you fork or mirror this template, change:

- `SEED_REPO_URL`
- `SEED_SCM_CREDENTIALS_ID`
- optional folder roots such as `SEED_JOB_ROOT`

## Custom Selection Example

If you want a custom selection instead of environment presets:

```powershell
.\scripts\export-jenkins-job-dsl.ps1 `
  -SelectionName sandbox `
  -Profile web-platform `
  -Applications nginx-web,httpbin,whoami `
  -DataServices redis `
  -RepoUrl https://github.com/k4nul/k8s-platform-template.git `
  -OutputPath .\out\jenkins\seed-job-dsl.groovy
```

See also:

- `JOB_BLUEPRINT.md`
- `scripts/show-jenkins-job-plan.ps1`
- `scripts/export-jenkins-job-dsl.ps1`
