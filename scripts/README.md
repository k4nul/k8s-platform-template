# Scripts

English | [한국어](README.ko.md)

This directory contains the main entry-point scripts for inspecting, validating, rendering, and packaging the template.

## Most Useful Commands

### Inspect The Template

- `show-profile-catalog.ps1`: compare profiles
- `show-environment-preset-plan.ps1`: compare environment presets
- `show-platform-plan.ps1`: preview selected components
- `show-platform-values-plan.ps1`: preview required values
- `show-service-runtime-plan.ps1`: preview compose runtime variables

### Readiness And Preflight

- `show-validation-readiness.ps1`: report local tool readiness, selected bundle characteristics, and recommended validation commands
- `show-cluster-preflight.ps1`: report cluster-side namespace, storage, CRD, and Helm source expectations before deployment
- `show-cluster-secret-plan.ps1`: report required secret names, keys, and example bootstrap commands

Rendered bundles also include `VALIDATION_READINESS.md`, `CLUSTER_PREFLIGHT.md`, and `CLUSTER_SECRET_PLAN.md` for the selected profile and values file.

`show-validation-readiness.ps1 -Format json` includes both the raw missing tool
list and grouped requirement fields. In particular, rendered schema validation is
reported as the single requirement `kubeconform or kubectl`, because either tool
satisfies the repository-local schema-validation path.

### Validate

- `validate-template.ps1`: validate repository structure and example assets
- `invoke-repository-validation.ps1`: run the main validation flow
- `validate-render-matrix.ps1`: render and validate public-default profile and environment combinations
- `validate-platform-assets.ps1`: validate rendered assets directly
- `validate-kubernetes-security-baseline.ps1`: review rendered Kubernetes YAML for risky defaults and baseline gaps
- `validate-workstation.ps1`: check local tools such as `kubectl`, `kubeconform`, and `helm`

Rendered manifest schema validation uses `kubeconform` when it is available and falls back to `kubectl apply --dry-run=client --validate=true`. When neither external validator is installed, non-strict validation warns and still runs a built-in structural preflight for rendered YAML `apiVersion`, `kind`, and `metadata.name`. This lets repository-only validation run without a live cluster dependency while preserving the `kubectl` path used by cluster workflows. Use `-SchemaValidator kubeconform` or `-SchemaValidator kubectl` on the template, repository, matrix, or platform-asset validation commands when CI needs to pin a specific validator.

`validate-template.ps1` checks required repository files, runs the lightweight PowerShell test suite, validates service catalogs and public values, performs one public smoke render, validates the rendered smoke bundle, and then calls `validate-render-matrix.ps1`. The matrix validates every bundled environment preset and each public profile shape with `config/platform-values.env.example`, so template maintainers can catch profile, preset, and default-value drift without writing rendered bundles into the repository.

The render matrix is assembled in `render-matrix-catalog.ps1` and covered by lightweight PowerShell tests. Non-strict rendered schema validation may skip the external schema tool when neither `kubeconform` nor `kubectl` is installed, but the structural preflight still runs; strict validation is expected to fail until one of those tools is available.

`invoke-repository-validation.ps1` is broader than the template gate. It runs template validation, strict workstation validation, and rendered bundle validation for one preset. Strict workstation validation uses `validate-workstation.ps1 -Strict`, whose default required tools are `kubectl` and `helm`; use `show-validation-readiness.ps1` first when you need to understand which checks are blocked on the current machine and whether a blocked schema check needs one validator tool or a specific missing tool.

The completed phase transition from `schema-security-baseline` to
`template-maintenance` used the template validation command, which remains the
maintenance gate:

```bash
env PATH="$HOME/.local/bin:$PATH" pwsh -NoProfile -File scripts/validate-template.ps1
```

When that command passes, the public profile and environment render matrix,
rendered schema validator wiring, and Kubernetes security baseline checks are
healthy enough for `template-maintenance`. Keep using
`invoke-repository-validation.ps1` for delivery readiness, because it adds strict
workstation and selected rendered-bundle checks on top of the template gate.

See [../docs/testing.md](../docs/testing.md) for the command matrix, validator fallback rules, CRD-backed resource behavior, and Kubernetes security baseline findings. See [../docs/troubleshooting.md](../docs/troubleshooting.md) for common missing-tool and generated-bundle validation failures.

### Render And Deliver

- `render-platform-assets.ps1`: render a bundle directly
- `invoke-bundle-delivery.ps1`: render, validate, and archive a bundle
- `invoke-bundle-promotion.ps1`: unpack and re-validate a delivered bundle
- `new-platform-environment.ps1`: create a values file from a preset

## Typical Command Flow

```powershell
.\scripts\show-profile-catalog.ps1 -Format markdown
.\scripts\new-platform-environment.ps1 -EnvironmentPreset dev -EnvironmentName dev -Force
.\scripts\validate-render-matrix.ps1
.\scripts\show-validation-readiness.ps1 -Profile web-platform -Applications nginx-web,httpbin,whoami -DataServices redis -Format markdown
.\scripts\invoke-repository-validation.ps1 -EnvironmentPreset dev
.\scripts\invoke-bundle-delivery.ps1 -EnvironmentPreset dev
```

## When To Use Which Script

- Use `show-*` scripts when you are deciding what to include.
- Use `validate-*` scripts when you want confidence before delivery or deployment.
- Use `invoke-*` scripts when you want the higher-level workflow rather than a low-level helper.
- Use `render-platform-assets.ps1` when you want direct rendering without the full delivery flow.
