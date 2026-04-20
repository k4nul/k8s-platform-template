# Generic Kubernetes And Jenkins Platform Template

English | [한국어](README.ko.md)

This repository is a public, reusable template for teams that want to assemble a Kubernetes platform bundle without inheriting company-specific services, private image assumptions, or fixed legacy port conventions.

It combines:

- generic Kubernetes manifests
- editable environment values
- public-image application examples
- optional Jenkins automation for validation, bundle delivery, promotion, and job seeding

## Who This Repository Is For

This template is a good fit if you want:

- a starting point for a new internal platform repository
- reusable example manifests for cluster add-ons and simple apps
- a PowerShell-first workflow for validation and bundle rendering
- a public repository that other teams can fork and adapt

It is less suitable if you want:

- a single production-ready opinionated platform with one exact stack
- a Helm-only repository with no raw manifests
- a language-specific application starter

## What You Get Out Of The Box

### Public-Image Application Examples

- `nginx-web`: static site example using `nginx:1.28-alpine`
- `httpbin`: HTTP test endpoint using `mccutchen/go-httpbin:v2.15.0`
- `whoami`: request inspector using `traefik/whoami:v1.10.4`
- `adminer`: database UI using `adminer:5.3.0-standalone`

### Shared Platform Components

- `301_platform_mysql`: MySQL
- `301_platform_postgresql`: PostgreSQL
- `302_platform_redis`: Redis
- `303_platform_memcached`: Memcached
- `304_platform_nginx`: reverse proxy
- `305_platform_metrics-server`: metrics API
- `306_platform_external-dns`: DNS automation values scaffold
- `307_platform_harbor`: internal registry values scaffold
- `308_platform_gateway-api`: Gateway and HTTPRoute examples
- `309_platform_nginx-gateway-fabric`: Gateway controller values scaffold
- `310_platform_longhorn`: storage values scaffold
- `311_platform_kubernetes-dashboard`: dashboard values scaffold
- `312_platform_vertical-pod-autoscaler`: VPA values scaffold

## Start Here

If this is your first visit, follow this order:

1. Read the quick start: [QUICKSTART.md](QUICKSTART.md)
2. Review available profiles:

```powershell
.\scripts\show-profile-catalog.ps1 -Format markdown
.\scripts\show-environment-preset-plan.ps1 -Format markdown
```

3. Generate a values file you can edit:

```powershell
.\scripts\new-platform-environment.ps1 `
  -EnvironmentPreset dev `
  -EnvironmentName dev `
  -Force
```

4. Validate the repository before customizing too much:

```powershell
.\scripts\validate-template.ps1
```

5. Render a bundle when you are ready:

```powershell
.\scripts\invoke-bundle-delivery.ps1 -EnvironmentPreset dev
```

## Common Workflows

### I Just Want To Explore The Template

```powershell
.\scripts\show-profile-catalog.ps1 -Format markdown
.\scripts\show-platform-plan.ps1 -Profile web-platform -Applications nginx-web,httpbin,whoami -DataServices redis -Format markdown
```

### I Want To Run A Local Example With Docker Compose

```powershell
cd .\services\nginx-web
docker compose --env-file ..\..\config\service-runtime.env.example up -d
```

See [services/README.md](services/README.md) for the local examples.

### I Want A Kubernetes Bundle I Can Review Or Apply

```powershell
.\scripts\invoke-repository-validation.ps1 -EnvironmentPreset dev
.\scripts\invoke-bundle-delivery.ps1 -EnvironmentPreset dev
```

The rendered bundle will include `k8s/`, `services/`, planning documents, readiness documents, and optional Jenkins assets under `out/`.

### I Want Jenkins Jobs For The Repository

Start here:

```powershell
.\scripts\show-jenkins-job-plan.ps1 -EnvironmentPreset dev -Format markdown
.\scripts\export-jenkins-job-dsl.ps1 -EnvironmentPreset dev -OutputPath .\out\jenkins\seed-job-dsl.groovy
```

See [jenkins/README.md](jenkins/README.md) for the Jenkins workflow.

## What You Usually Edit First

Most adopters only need to edit a small part of the repository first:

- `config/platform-values.<env>.env`: hostnames, storage, passwords, and bundle values
- `config/service-runtime.env.example`: local Docker Compose host ports
- `config/environments/*.psd1`: reusable defaults for validation, delivery, and promotion

You normally do not need to edit the deeper `*.psd1` catalogs unless you are maintaining the template itself.

## Repository Map

- [config/README.md](config/README.md): editable values, presets, and catalogs
- [k8s/README.md](k8s/README.md): manifest layout, numbering, and rollout phases
- [services/README.md](services/README.md): local Docker Compose examples
- [scripts/README.md](scripts/README.md): main entry-point scripts
- [jenkins/README.md](jenkins/README.md): Jenkins jobs and Job DSL flow

## Important Defaults

- Public images are used by default, so a private registry is not required unless you introduce your own private images.
- Example hostnames use `example.com` and should be replaced.
- Old `31500` range ports were replaced with common service ports such as `80`, `8080`, `3306`, and `5432`.
- Jenkins service-image jobs are optional and are not generated by default for these public-image examples.
- The repository is PowerShell-first. The main entry points assume `pwsh` or Windows PowerShell.

## Documentation Map

- Start quickly: [QUICKSTART.md](QUICKSTART.md)
- Deployment environment notes: [DEPLOYMENT_ENV.md](DEPLOYMENT_ENV.md)
- Environment checklist: [ENV_CHECKLIST.md](ENV_CHECKLIST.md)
- Operations notes: [OPERATIONS_RUNBOOK.md](OPERATIONS_RUNBOOK.md)

## Public Repository Expectations

If you fork this repository for your own organization, plan to replace at least:

- domain names such as `example.com`
- secrets and passwords in generated env files
- Jenkins SCM settings if you use the seed job
- any optional platform components you do not plan to support
