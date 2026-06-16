# Dependency Plan

Last reviewed: 2026-06-16

This project is a PowerShell-first Kubernetes template. It does not have a
language package manifest or lockfile today, so dependency planning focuses on
toolchain prerequisites, public container image tags, Helm chart references,
Kubernetes manifest APIs, and generated-artifact hygiene.

## Dependency Inventory

| Area | Repository files | Current dependency indicators |
| --- | --- | --- |
| PowerShell validation and rendering | `scripts/*.ps1`, `tests/*.Tests.ps1` | Requires PowerShell or `pwsh`; scripts use repository-local helpers and PowerShell data files |
| Kubernetes schema validation | `scripts/validate-rendered-bundle.ps1`, `scripts/validate-platform-assets.ps1` | Prefers `kubeconform`; falls back to `kubectl apply --dry-run=client --validate=true`; non-strict mode warns when both are absent |
| Workstation validation | `scripts/validate-workstation.ps1`, `scripts/invoke-repository-validation.ps1` | Strict repository validation requires `kubectl` and `helm`; `git`, `docker`, `python`, and `kubeconform` are optional readiness tools |
| Helm chart scaffolds | `config/helm-releases.psd1`, `k8s/*/values.yaml` | ExternalDNS, Harbor, NGINX Gateway Fabric, Longhorn, Kubernetes Dashboard, and disabled VPA scaffold entries; chart references are not version-pinned in the repository |
| Public service images | `config/service-builds.psd1`, `config/service-runtime-bindings.psd1`, `services/*/docker-compose.yaml`, `k8s/400_*/*.yaml` | `adminer:5.3.0-standalone`, `mccutchen/go-httpbin:v2.15.0`, `nginx:1.28-alpine`, `traefik/whoami:v1.10.4` |
| Platform images | `k8s/**/*.yaml` | Public tags for MySQL, PostgreSQL, Redis, Memcached, Metrics Server, NGINX, and related platform examples |
| Generated outputs and local secrets | `.gitignore`, delivery and rendering scripts | `out/`, `.kube/`, `secrets/`, `cluster-bootstrap/`, local env files, and private agent files are intentionally untracked |

There are no checked-in dependency lockfiles, vendored packages, package manager
manifests, or generated rendered bundles in this template.

## Toolchain And Runtime Constraints

- Keep the default validation path repository-local and public. Do not require a
  live cluster, private registry, or private image default for template checks.
- Keep `validate-template.ps1` as the lightweight phase gate for public defaults.
- Automation and cron shells must expose `pwsh` on `PATH` before dependency
  readiness can be scored. An immediate exit 127 from the template gate means
  PowerShell was not found, not that Kubernetes manifests failed validation.
- Use `invoke-repository-validation.ps1 -EnvironmentPreset dev` when the
  workstation has the stricter `kubectl` and `helm` prerequisites available.
- Use `show-validation-readiness.ps1` before treating missing Kubernetes tools as
  template defects. Its grouped requirement summary treats `kubeconform or
  kubectl` as one schema-validator requirement and reports `helm` separately.
- Do not commit rendered `out/` bundles, kubeconfigs, secrets, generated local
  env files, or private agent files.

## Staged Upgrade Plan

### Stage 1: Dependency Inventory Hygiene

Scope:

- Confirm `pwsh` is discoverable in the automation shell before interpreting
  template validation status.
- Keep this document current when public image tags, Helm chart entries, or
  workstation tool assumptions change.
- Cross-check public image references across `config/service-builds.psd1`,
  `config/service-runtime-bindings.psd1`, `services/*/docker-compose.yaml`, and
  matching Kubernetes manifests.
- Confirm `.gitignore` still excludes generated bundles and local secret-bearing
  files.

Validation:

```bash
command -v pwsh
pwsh -NoProfile -File scripts/validate-template.ps1
```

### Stage 2: Public Image Tag Review

Scope:

- Review public image tags in one coherent batch.
- Update matching service catalog, runtime binding, Docker Compose, Kubernetes
  manifest, and documentation references together.
- Keep public image defaults public and generic.

Validation:

```bash
pwsh -NoProfile -File scripts/validate-template.ps1
pwsh -NoProfile -File scripts/show-service-build-plan.ps1 -Format markdown
pwsh -NoProfile -File scripts/show-service-runtime-plan.ps1 -Format markdown
```

### Stage 3: Helm Chart Source Review

Scope:

- Review enabled chart references in `config/helm-releases.psd1` and their values
  files as one Helm-maintenance batch.
- Keep the VPA scaffold disabled until a supported chart reference is selected
  for the target environment.
- Do not run chart updates that require private repositories or live cluster
  state as part of generic template validation.

Validation:

```bash
pwsh -NoProfile -File scripts/validate-template.ps1
pwsh -NoProfile -File scripts/invoke-repository-validation.ps1 -EnvironmentPreset dev
```

If `helm`, `kubectl`, or a schema validator is missing, first run:

```bash
pwsh -NoProfile -File scripts/show-validation-readiness.ps1 -Profile web-platform -Applications nginx-web,httpbin,whoami -DataServices redis -Format markdown
```

### Stage 4: Offline Schema Validator Enablement

Scope:

- Install or expose `kubeconform` on the validation host before changing
  manifests, because it is the preferred repository-only schema validator and
  does not require live cluster access.
- Keep `kubectl` as the fallback path for workstations that already use
  Kubernetes client tooling.
- Record validator versions in the run evidence; do not commit downloaded
  binaries, caches, or generated schema output.

Validation:

```bash
pwsh -NoProfile -File scripts/show-validation-readiness.ps1 -Profile web-platform -Applications nginx-web,httpbin,whoami -DataServices redis -Format markdown
pwsh -NoProfile -File scripts/validate-template.ps1 -SchemaValidator kubeconform
```

If `kubeconform` is unavailable but `kubectl` is installed:

```bash
pwsh -NoProfile -File scripts/validate-template.ps1 -SchemaValidator kubectl
```

### Stage 5: Strict Helm And Security Gate Hardening

Scope:

- Install or expose `helm` before treating Helm values validation as a template
  defect.
- Review whether enabled chart references should become version-pinned after a
  Helm source review proves the expected chart versions and values schemas.
- Investigate whether high-severity security baseline findings from optional
  admin examples should become explicit documented exceptions or stricter
  profile-specific gates.

Validation:

```bash
pwsh -NoProfile -File scripts/validate-template.ps1
pwsh -NoProfile -File scripts/validate-render-matrix.ps1 -FailOnHighSecurityBaselineFinding
```

## Likely Breaking Changes To Investigate

- Container image tag upgrades can change entrypoints, exposed ports, default
  users, health behavior, or environment variable names.
- Helm chart upgrades can change values schemas, CRD requirements, namespace
  assumptions, and generated resource names.
- Kubernetes API upgrades can deprecate or remove manifest versions used by raw
  YAML examples.
- Stricter schema validation can fail CRD-backed resources unless those CRDs are
  available to the selected validator.
- Security baseline hardening can require environment-specific exceptions for
  dashboard, admin, storage, or registry components.

## Test Areas After Each Stage

- Template gate: `validate-template.ps1`.
- Render matrix: `validate-render-matrix.ps1`.
- Service image consistency: `validate-service-builds.ps1` and
  `validate-service-runtime.ps1`.
- Public values and profile selection: `validate-platform-values.ps1` and
  `validate-platform-selection.ps1`.
- Rendered bundle validation: `validate-platform-assets.ps1` for the selected
  profile and values file.
- Workstation readiness: `validate-workstation.ps1 -Strict` before full
  repository validation.

## Security Or Maintenance Risk Indicators

- Missing `kubeconform`, `kubectl`, or `helm` means validation coverage is
  reduced or blocked depending on strictness.
- Missing `pwsh` blocks every repository validation lane before Kubernetes
  manifests are read. Treat `pwsh: command not found` or exit 127 as an
  automation environment issue and rerun after exposing PowerShell on `PATH`.
- Public image tags should be reviewed as upgrade candidates; current
  vulnerability status requires external verification and is not inferred from
  repository files.
- Enabled Helm chart references are tagless/versionless in repository metadata;
  this is an upgrade-planning risk indicator until chart versions and values
  schema compatibility are reviewed with `helm` available.
- The current validation host reported repository-only validation availability:
  `kubectl`, `kubeconform`, and `helm` were missing for the selected
  `web-platform` bundle.
- Optional admin manifests and chart scaffolds can surface high-severity review
  findings that may need profile-specific policy decisions.
- Any future lockfile, rendered bundle, kubeconfig, or generated secret file
  checked into Git should be treated as an artifact-hygiene blocker.

## Suggested Larger Upgrade Or Hygiene Packages

1. Public image tag refresh across service catalogs, Compose files, Kubernetes
   manifests, and docs.
2. Helm chart source and values compatibility review for every enabled release.
3. Automation shell readiness lane that verifies `pwsh` is on `PATH` before
   recurring progress scoring runs `validate-template.ps1`.
4. Strict schema-validator installation lane, with documented `kubeconform` and
   `kubectl` verification outputs.
5. Helm chart version-pin review and values compatibility lane after `helm` is
   available on the validation host.
6. Security baseline exception and hardening policy for optional admin and
   dashboard resources.
7. Kubernetes API compatibility review for all raw YAML manifests.

## Changes Made And Validation

The 2026-06-16 dependency-plan pass refreshed this dependency plan with current
validator readiness evidence, an explicit automation-shell `pwsh` readiness
gate, and a staged offline schema-validator package. It did not change runtime
dependencies, public image defaults, Helm chart references, lockfiles, rendered
bundles, or generated artifacts.

Validation commands:

```bash
command -v pwsh
pwsh -NoProfile -File scripts/validate-template.ps1
pwsh -NoProfile -File scripts/show-validation-readiness.ps1 -Profile web-platform -Applications nginx-web,httpbin,whoami -DataServices redis -Format markdown
pwsh -NoProfile -File scripts/validate-workstation.ps1 -Strict
pwsh -NoProfile -File scripts/show-service-build-plan.ps1 -Format markdown
pwsh -NoProfile -File scripts/show-service-runtime-plan.ps1 -Format markdown
pwsh -NoProfile -File scripts/show-service-dependency-plan.ps1 -Format markdown
```

`command -v pwsh` resolved to `/home/k4nul/.local/bin/pwsh` in this worktree.
`validate-template.ps1` completed successfully. It emitted expected non-strict
warnings because `kubeconform`, `kubectl`, and `helm` were not installed.
`show-validation-readiness.ps1` reported `repository-only-validation-available`
for the selected `web-platform` bundle and listed `kubectl`, `kubeconform`, and
`helm` as missing required tools. `validate-workstation.ps1 -Strict` failed with
missing required tools: `helm`, `kubectl`. The service build, runtime, and
dependency plan helpers completed successfully with all public services in the
`public-image` build profile and dependency-plan status counts of `ready=4`,
`attention=0`, `error=0`, `uncatalogued=0`.

## Current Automated Phase State

The `schema-security-baseline` transition validation command passed, and the
project phase metadata now records `template-maintenance` with no pending
transition command. Select a new `next_phase` and transition validation command
before routing another phase-transition.
