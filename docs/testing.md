# Validation and Testing

This repository validates rendered platform bundles rather than application unit tests. The normal checks use public defaults, render into temporary directories, and avoid live cluster dependencies unless you intentionally run cluster-side apply or deployment helpers.

## Tooling Expectations

- PowerShell or `pwsh` is required for the repository scripts. On Linux and macOS, install `pwsh` before running the validation commands.
- `kubeconform` is the preferred rendered manifest schema validator because it does not require a live cluster.
- `kubectl` is the fallback schema validator and is also used by generated apply, status, and destroy helpers.
- `helm` is required when the selected profile includes Helm-managed platform components.
- `docker`, `git`, and `python` are useful for local examples and debugging, but they are not the core Kubernetes validation path.

Check the local machine with:

```powershell
.\scripts\validate-workstation.ps1
.\scripts\show-validation-readiness.ps1 -Profile web-platform -Applications nginx-web,httpbin,whoami -DataServices redis -Format markdown
```

`show-validation-readiness.ps1` is the bundle-specific readiness view. It tells you which checks are available on the current machine and which checks are blocked for the selected profile.

`invoke-repository-validation.ps1` runs `validate-workstation.ps1 -Strict` unless you pass `-SkipWorkstationValidation`. The default strict workstation profile requires `kubectl` and `helm`, even when `validate-template.ps1` can still complete with non-strict schema and Helm warnings. Use the skip switch only when you are intentionally doing repository-only validation on a machine that is not prepared for cluster or Helm workflows.

Environment presets use `ValidationValuesFile` for repository validation when it is defined. The bundled presets point that field at `config/platform-values.env.example` so public validation is independent from site-specific values.
After editing a generated values file, pass it explicitly:

```powershell
.\scripts\invoke-repository-validation.ps1 `
  -EnvironmentPreset dev `
  -ValuesFile config\platform-values.dev.env
```

## Command Matrix

| Command | Use it for | Repository writes |
| --- | --- | --- |
| `.\scripts\validate-template.ps1` | Template structure, catalogs, one smoke render, rendered-asset validation, and the public-default render matrix | No tracked writes; temporary render output is removed |
| `.\scripts\validate-render-matrix.ps1` | Public-default coverage for every bundled environment preset and profile | No tracked writes; each render uses temporary output |
| `.\scripts\show-validation-readiness.ps1 -Profile web-platform -Applications nginx-web,httpbin,whoami -DataServices redis -Format markdown` | Workstation readiness, selected bundle characteristics, blocked checks, and recommended validation commands | No tracked writes |
| `.\scripts\invoke-repository-validation.ps1 -EnvironmentPreset dev` | Full repository workflow for the `dev` preset, including template, workstation, and rendered bundle checks | No tracked writes |
| `.\scripts\validate-platform-assets.ps1 -Profile web-platform -Applications nginx-web,httpbin,whoami -DataServices redis` | One selected profile, application set, and data-service set | No tracked writes; `-KeepRenderedOutput` leaves temporary rendered output for inspection |
| `.\scripts\invoke-bundle-delivery.ps1 -EnvironmentPreset dev` | Render, validate, and archive a reviewable delivery bundle | Writes under `out/`; do not commit rendered bundles |

Use `validate-template.ps1` as the lightweight repository gate before changing shared manifests, catalogs, profiles, or documentation that describes validation behavior. Use `invoke-repository-validation.ps1` before delivery or promotion.

## Validation Layers

Use these layers in order when you are bringing up a workstation or reviewing a template change:

| Layer | Command | What it proves |
| --- | --- | --- |
| Template gate | `.\scripts\validate-template.ps1` | Required repository files exist, catalog tests pass, one public smoke bundle renders, rendered assets validate non-strictly, and the public-default render matrix completes |
| Readiness report | `.\scripts\show-validation-readiness.ps1 -Profile <profile> -Format markdown` | The selected bundle's tool requirements, CRD-backed resource notes, Helm needs, and recommended validation command for this workstation |
| Repository workflow | `.\scripts\invoke-repository-validation.ps1 -EnvironmentPreset dev` | Template validation, strict workstation validation, and rendered bundle validation for one environment preset |
| Delivery validation | `.\scripts\invoke-bundle-delivery.ps1 -EnvironmentPreset dev` followed by the generated `validate-bundle.ps1` | The reviewable `out/` bundle and its generated helper scripts can validate the rendered files before apply |

The current phase gate for profile render validation is the template gate. It should pass before moving on to broader schema and security baseline work.

## Public-Default Render Matrix

`validate-template.ps1` calls `validate-render-matrix.ps1` after its smoke render. The matrix is intentionally public and generic:

- Environment preset entries come from `config/environments/*.psd1`.
- Each bundled environment preset points `ValidationValuesFile` at `config/platform-values.env.example`.
- Profile entries cover every file under `config/profiles/*.psd1`.
- The matrix fails if a profile exists in `config/profiles/` but is missing from the scripted profile matrix.
- The combined matrix is built by `scripts/render-matrix-catalog.ps1` and is covered by tests so the validator and test suite use the same environment/profile ordering.

The bundled preset coverage is:

| Preset | Profile | Applications | Data services |
| --- | --- | --- | --- |
| `dev` | `web-platform` | `nginx-web`, `httpbin`, `whoami` | `redis` |
| `staging` | `shared-services` | `nginx-web`, `httpbin`, `adminer` | `postgresql`, `redis` |
| `prod` | `shared-services` | `nginx-web`, `whoami` | `postgresql`, `redis` |

The profile matrix adds representative application and data-service combinations for every profile under `config/profiles/`. `scripts/render-matrix-catalog.ps1` fails if a profile file is added or removed without updating the matrix.

| Profile | Applications | Data services |
| --- | --- | --- |
| `minimal-application` | `nginx-web`, `whoami` | none |
| `developer-sandbox` | `nginx-web`, `httpbin`, `whoami` | `mysql`, `redis` |
| `data-services` | none | `mysql`, `postgresql`, `redis` |
| `reverse-proxy-platform` | `nginx-web`, `whoami` | none |
| `web-platform` | `nginx-web`, `httpbin`, `whoami` | `redis` |
| `shared-services` | `nginx-web`, `adminer` | `postgresql`, `redis` |
| `full` | `nginx-web`, `httpbin`, `whoami`, `adminer` | `mysql`, `postgresql`, `redis` |

Optional follow-up manifests are intentionally excluded from generated bundles
during matrix validation. The source files remain available for manual review,
but public-default renders should not package high-privilege samples such as the
Kubernetes Dashboard admin user.

## Rendered Manifest Schema Validation

Rendered YAML validation is handled by `scripts/validate-rendered-bundle.ps1`, usually through `validate-platform-assets.ps1`.

Selection behavior:

- `kubeconform` is used first when it is installed.
- If `kubeconform` is unavailable, `kubectl apply --dry-run=client --validate=true` is used when `kubectl` is installed.
- If neither validator is installed, non-strict validation warns and skips rendered manifest schema validation.
- Strict validation fails when no schema validator is available.

CRD-backed resources are skipped by default because public repository validation should not require cluster-installed CRDs. Add `-ValidateCrdBackedResources` only after the required CRDs are available to the selected validator.

The rendered-bundle validator tests cover the no-validator path directly: default template validation may skip schema validation with a warning, while `-Strict` must fail until `kubeconform` or `kubectl` is available.

## Kubernetes Security Baseline

`validate-platform-assets.ps1` also runs `scripts/validate-kubernetes-security-baseline.ps1` against the rendered bundle. The baseline is a review gate, not a replacement for cluster admission policy.

It reports:

- high-severity defaults such as privileged containers, host namespace access, `hostPath` volumes, and `cluster-admin` bindings
- medium-severity gaps such as missing resources, pod or container `securityContext`, readiness probes, liveness probes, mutable `latest` tags, and skipped TLS verification
- low-severity review items such as external Service exposure and missing NetworkPolicy coverage

By default the script reports findings without failing the run. Use `-FailOnHighSecurityBaselineFinding` with `validate-render-matrix.ps1` or `validate-platform-assets.ps1` when high-severity findings should block the validation command.

## Troubleshooting

If repository validation fails at the workstation step, run:

```powershell
.\scripts\validate-workstation.ps1 -Strict
```

Install the missing required tools for the selected validation workflow, then rerun `invoke-repository-validation.ps1`.
For a repository-only check on a workstation without `kubectl` or `helm`, use `validate-template.ps1` and `show-validation-readiness.ps1` first, or run `invoke-repository-validation.ps1 -SkipWorkstationValidation` only when that narrower validation scope is intentional.

If rendered manifest validation is skipped, install `kubeconform` for repository-only schema checks or `kubectl` for the dry-run fallback.

If CRD-backed resources are skipped, leave them skipped for generic public validation. Enable `-ValidateCrdBackedResources` only in an environment where the related CRDs are available.

If security baseline findings appear, review the rendered file paths before editing templates. Some add-ons may need an explicit exception or an environment-specific hardening decision rather than a generic template default.

If placeholder checks fail, replace environment-specific values in `config/platform-values.<env>.env` or generated bootstrap secret files. Do not commit real secrets, kubeconfigs, or rendered `out/` bundles.
Run placeholder scans against a customized values file or rendered bundle, not as a public-default repository validation gate.

For common validation failures and the exact layer where they happen, see [troubleshooting.md](troubleshooting.md).
