# Quickstart

English | [한국어](QUICKSTART.ko.md)

This guide is for a first-time user who wants to clone the repository, understand the bundle model, edit a few values, and either run local examples or render a Kubernetes bundle.

## Prerequisites

Recommended tools:

- PowerShell or `pwsh`
- `git`
- `kubeconform` if you want rendered manifest schema validation without a live cluster
- `kubectl` if you want cluster-side validation or apply manifests
- `helm` if you want to validate or install Helm-managed components
- Docker if you want to run the local compose examples

You can still explore the repository without every tool installed, but some validation steps will be skipped.
For exact missing-tool behavior, see [docs/troubleshooting.md](docs/troubleshooting.md).

## 1. Review The Available Shapes

Compare the built-in bundle profiles and environment presets first:

```powershell
.\scripts\show-profile-catalog.ps1 -Format markdown
.\scripts\show-environment-preset-plan.ps1 -Format markdown
```

Good starting points:

- `minimal-application`: namespaces and storage only
- `developer-sandbox`: compact sandbox with common shared services
- `web-platform`: gateway-oriented public web stack with demo apps
- `shared-services`: shared cluster add-ons and optional examples

## 2. Generate A Values File You Can Edit

```powershell
.\scripts\new-platform-environment.ps1 `
  -EnvironmentPreset dev `
  -EnvironmentName dev `
  -Force
```

This creates a file such as `config/platform-values.dev.env`.

Edit that file before you go further. At minimum, replace:

- hostnames based on `example.com`
- storage settings such as NFS server and export path
- passwords and secret-like values

If you also want local compose examples, review:

- `config/service-runtime.env.example`

## 3. Preview What Will Be Included

```powershell
.\scripts\show-platform-plan.ps1 `
  -Profile web-platform `
  -Applications nginx-web,httpbin,whoami `
  -DataServices redis `
  -Format markdown

.\scripts\show-platform-values-plan.ps1 `
  -Profile web-platform `
  -Applications nginx-web,httpbin,whoami `
  -DataServices redis `
  -Format markdown
```

This step answers two questions before rendering:

- which directories and components will be included
- which values are expected from your env file

## 4. Validate The Repository

```powershell
.\scripts\validate-template.ps1
.\scripts\show-render-matrix.ps1 -Format markdown
.\scripts\show-validation-readiness.ps1 -Profile web-platform -Applications nginx-web,httpbin,whoami -DataServices redis -Format markdown
.\scripts\invoke-repository-validation.ps1 -EnvironmentPreset dev
```

Use `validate-template.ps1` for template-level sanity checks.

Use `show-render-matrix.ps1` to inspect the public-default environment and profile coverage without rendering every bundle.

Use `show-validation-readiness.ps1` to see which rendered-bundle checks are available on the current workstation.

Use `invoke-repository-validation.ps1` when you want the more realistic repository workflow, including workstation and rendered-asset checks. This command runs strict workstation validation by default, so install `kubectl` and `helm` first or intentionally pass `-SkipWorkstationValidation` for a repository-only run.
The preset validation path intentionally uses `config/platform-values.env.example` unless you pass `-ValuesFile`.
After editing `config/platform-values.dev.env`, validate the edited file explicitly:

```powershell
.\scripts\invoke-repository-validation.ps1 `
  -EnvironmentPreset dev `
  -ValuesFile config\platform-values.dev.env
```

See [docs/testing.md](docs/testing.md) for the public-default render matrix, schema validation fallback, CRD-backed resource behavior, and Kubernetes security baseline checks. See [docs/troubleshooting.md](docs/troubleshooting.md) when validation is blocked by workstation tools or generated-bundle readiness.

## 5. Render A Bundle

```powershell
.\scripts\invoke-bundle-delivery.ps1 -EnvironmentPreset dev
```

The rendered bundle will include:

- `k8s/`
- `services/`
- `DEPLOYMENT_BUNDLE.md`
- `bundle-manifest.json`
- `validate-bundle.ps1` and deployment helper scripts
- `CLUSTER_PREFLIGHT.md`
- `CLUSTER_SECRET_PLAN.md`
- `VALIDATION_READINESS.md`
- `PROFILE_CATALOG.md`
- `PLATFORM_PLAN.md`
- `PLATFORM_VALUES_PLAN.md`
- service build, config, dependency, and input plans
- `SERVICE_RUNTIME_PLAN.md`

Use `DEPLOYMENT_BUNDLE.md` as the bundle index. It lists the generated helpers, planning documents, and rollout commands for the selected profile and values file.

By default the output goes under `out/delivery/<environment>/`.

## 6. Choose Your Next Path

### Path A: Run A Local Example Only

```powershell
cd .\services\nginx-web
docker compose --env-file ..\..\config\service-runtime.env.example up -d
```

Repeat the same pattern in:

- `services/httpbin`
- `services/whoami`
- `services/adminer`

### Path B: Review Or Apply The Kubernetes Bundle

Typical order after rendering:

```powershell
.\out\delivery\dev\validate-bundle.ps1
.\out\delivery\dev\cluster-bootstrap\check-secret-templates.ps1
.\out\delivery\dev\cluster-bootstrap\status-secrets.ps1
.\out\delivery\dev\apply-manifests.ps1
.\out\delivery\dev\install-helm-components.ps1 -PrepareRepos
.\out\delivery\dev\status-bundle.ps1
```

Edit generated bootstrap secret templates before applying them. Use `status-secrets.ps1 -FailOnMissing` when the rollout should stop until namespaces and secrets are present.

If you only want the sample applications:

```powershell
kubectl apply -f .\out\delivery\dev\k8s\400_platform_nginx-web\
kubectl apply -f .\out\delivery\dev\k8s\400_platform_httpbin\
kubectl apply -f .\out\delivery\dev\k8s\400_platform_whoami\
```

## 7. Optional CI/CD Flow

If you want Jenkins jobs for the repository, use `../jenkins-pipeline-template`.

## 8. What To Read Next

- Repository overview: [README.md](README.md)
- Values and presets: [config/README.md](config/README.md)
- Manifests and rollout phases: [k8s/README.md](k8s/README.md)
- Local examples: [services/README.md](services/README.md)
- Scripts: [scripts/README.md](scripts/README.md)
- Validation troubleshooting: [docs/troubleshooting.md](docs/troubleshooting.md)
