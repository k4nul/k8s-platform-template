# Quickstart

English | [한국어](QUICKSTART.ko.md)

## 1. Pick A Profile

Review the built-in bundle shapes first:

```powershell
.\scripts\show-profile-catalog.ps1 -Format markdown
.\scripts\show-environment-preset-plan.ps1 -Format markdown
```

Common starting points:

- `minimal-application`: base namespaces and storage only
- `developer-sandbox`: small sandbox with MySQL, Redis, NGINX, and metrics
- `web-platform`: Gateway API, DNS automation, metrics, and public demo apps
- `shared-services`: shared cluster add-ons plus optional app examples

## 2. Prepare Editable Values

Generate an environment file from a preset:

```powershell
.\scripts\new-platform-environment.ps1 `
  -EnvironmentPreset dev `
  -EnvironmentName dev `
  -Force
```

Then edit:

- `config/platform-values.dev.env`
- `config/service-runtime.env.example` if you want local compose examples too

## 3. Preview The Selected Bundle

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

## 4. Validate

```powershell
.\scripts\validate-template.ps1
.\scripts\invoke-repository-validation.ps1 -EnvironmentPreset dev
```

## 5. Render A Bundle

```powershell
.\scripts\invoke-bundle-delivery.ps1 -EnvironmentPreset dev
```

The rendered bundle will contain:

- `k8s/`
- `services/`
- `DEPLOYMENT_BUNDLE.md`
- `CLUSTER_PREFLIGHT.md`
- `CLUSTER_SECRET_PLAN.md`
- `PLATFORM_VALUES_PLAN.md`
- `SERVICE_RUNTIME_PLAN.md`
- `jenkins/JOB_PLAN.md`
- `jenkins/seed-job-dsl.groovy`

## 6. Apply In A Real Cluster

Typical order:

```powershell
.\out\delivery\dev\cluster-bootstrap\status-secrets.ps1
.\out\delivery\dev\apply-manifests.ps1
.\out\delivery\dev\install-helm-components.ps1 -PrepareRepos
.\out\delivery\dev\status-bundle.ps1
```

If you want only the sample apps:

```powershell
kubectl apply -f .\out\delivery\dev\k8s\400_platform_nginx-web\
kubectl apply -f .\out\delivery\dev\k8s\400_platform_httpbin\
kubectl apply -f .\out\delivery\dev\k8s\400_platform_whoami\
```

## 7. Run Local Compose Examples

```powershell
cd .\services\nginx-web
docker compose --env-file ..\..\config\service-runtime.env.example up -d
```

Repeat the same pattern in:

- `services/httpbin`
- `services/whoami`
- `services/adminer`
