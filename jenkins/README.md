# Jenkins

English | [한국어](README.ko.md)

This directory contains generic Jenkins automation for the repository itself.

## Main Jobs

- `repository-validation.Jenkinsfile`: validates repository structure and rendered assets
- `bundle-delivery.Jenkinsfile`: renders, validates, and archives a bundle
- `bundle-promotion.Jenkinsfile`: re-validates and optionally deploys an archived bundle
- `job-seed.Jenkinsfile`: generates Jenkins folders and pipeline jobs from the shared job plan

## Important Notes

- The default sample applications use public images, so per-service image build jobs are not required.
- `show-jenkins-job-plan.ps1` and `export-jenkins-job-dsl.ps1` will still generate the bundle-level validation, delivery, and promotion jobs.
- Service-level jobs appear only if a service actually has its own Jenkinsfile and the catalog marks it as such.
- Each Jenkinsfile starts with an agent-readiness preflight so missing tools such as `kubectl` or `helm` fail early with a clearer message.
- `job-seed.Jenkinsfile` now leaves the preset list blank by default, which means "use every preset currently found in `config/environments`".
- `job-seed.Jenkinsfile` uses `https://github.com/k4nul/k8s-platform-template.git` as the default SCM URL. If you fork or mirror this template, change `SEED_REPO_URL`.

## Useful Commands

```powershell
.\scripts\show-jenkins-job-plan.ps1 -EnvironmentPreset dev -Format markdown
.\scripts\export-jenkins-job-dsl.ps1 -EnvironmentPreset dev -OutputPath .\out\jenkins\seed-job-dsl.groovy
```

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
