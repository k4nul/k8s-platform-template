# Operations Runbook

This runbook captures the recommended operator flow for validating, packaging, promoting, and deploying the reusable Kubernetes bundles in this repository.

## 1. Choose A Preset

Start by reviewing the shared environment presets:

```powershell
.\scripts\show-environment-preset-plan.ps1 -Format markdown
```

The built-in presets live under `config\environments\`:

- `dev`: small development-oriented web platform baseline
- `staging`: broader shared-services validation baseline
- `prod`: production-oriented shared-services baseline

If none of them match your environment, copy one of the preset files and adjust the values, applications, data services, archive path, and promotion extract path.

## 2. Generate Or Refresh Values

Create a filtered values file from the preset:

```powershell
.\scripts\new-platform-environment.ps1 `
  -EnvironmentName dev `
  -EnvironmentPreset dev `
  -Force
```

Then replace placeholders with real values before treating the environment as deployable.

## 3. Run Repository-Level Validation

Validate repository structure, workstation tooling, and rendered bundle dry-runs through the shared validation entry point:

```powershell
.\scripts\invoke-repository-validation.ps1 -EnvironmentPreset dev
```

Use this step before delivery packaging or after changing shared templates, catalogs, or preset files.

## 4. Build A Delivery Artifact

Render the bundle, validate it inside the output directory, and archive it:

```powershell
.\scripts\invoke-bundle-delivery.ps1 -EnvironmentPreset dev
```

This step produces:

- a rendered bundle directory, such as `out\delivery\dev`
- a ZIP archive, such as `out\delivery\dev.zip`

Keep deployment disabled here unless you intentionally want the delivery job itself to touch a cluster.

## 5. Prepare Bootstrap Assets

Before any real deployment, edit the generated bootstrap YAML files inside the rendered bundle:

- `cluster-bootstrap\secrets\...`
- `cluster-bootstrap\namespaces\...`

Then validate and apply them:

```powershell
.\out\delivery\dev\cluster-bootstrap\check-secret-templates.ps1
.\out\delivery\dev\cluster-bootstrap\apply-secrets.ps1
.\out\delivery\dev\cluster-bootstrap\status-secrets.ps1 -FailOnMissing
```

Use `-RequireBootstrapSecretsReady` or `-RequireBootstrapStatus` on the validation and promotion flows when you want those checks enforced automatically.

## 6. Promote The Archived Bundle

Promote the archived bundle without re-rendering it:

```powershell
.\scripts\invoke-bundle-promotion.ps1 -EnvironmentPreset dev
```

This step unpacks the ZIP archive into the configured promotion directory, validates the extracted bundle again, and can optionally run the generated deployment helper.

Promotion is the recommended point to connect environment-specific approval, change-management, or artifact-traceability controls.

## 7. Dry-Run Deployment First

If the promotion workflow will drive cluster operations, start with dry-run deployment:

```powershell
.\scripts\invoke-bundle-promotion.ps1 `
  -EnvironmentPreset prod `
  -DeployBundle `
  -DeploymentDryRun
```

Switch off `-DeploymentDryRun` only after:

- the target cluster context is confirmed
- bootstrap prerequisites are green
- chart repositories and CRDs are ready
- the rendered bundle contents are approved

## 8. Live Deployment

You can deploy either from the promotion workflow or from the extracted bundle directly:

```powershell
.\out\promotion\prod\deploy-bundle.ps1 -PrepareHelmRepos
```

Or, if you want the promotion wrapper to drive it:

```powershell
.\scripts\invoke-bundle-promotion.ps1 `
  -EnvironmentPreset prod `
  -DeployBundle
```

Use `-IncludeDeferredComponents` only after the required controllers are healthy.

## 9. Status And Rollback

Inspect the deployed bundle:

```powershell
.\out\promotion\prod\status-bundle.ps1
```

Remove the deployed bundle in reverse order if you need to roll back the full stack:

```powershell
.\out\promotion\prod\destroy-bundle.ps1
```

For partial rollback, use the generated helpers with explicit phase or release selections instead of deleting the whole bundle.

## 10. Jenkins Mapping

Recommended Jenkins flow:

1. `repository-validation.Jenkinsfile`: repository and render validation
2. `bundle-delivery.Jenkinsfile`: render, validate, and archive a bundle artifact
3. `bundle-promotion.Jenkinsfile`: unpack, validate, and optionally deploy the archived bundle

Pass the same preset name through all three jobs so the local workflow and CI workflow stay aligned.
Generate the recommended folder structure and shared service job list first with `.\scripts\show-jenkins-job-plan.ps1 -Format markdown`, then use `jenkins\JOB_BLUEPRINT.md` to map that plan into real Jenkins folders, triggers, and approval gates.
If you want Jenkins to create those folders and SCM-backed pipeline jobs automatically, generate Job DSL with `.\scripts\export-jenkins-job-dsl.ps1` or run `jenkins\job-seed.Jenkinsfile` with the Jenkins Job DSL plugin enabled.
