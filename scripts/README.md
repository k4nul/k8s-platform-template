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

### Validate

- `validate-template.ps1`: validate repository structure and example assets
- `invoke-repository-validation.ps1`: run the main validation flow
- `validate-render-matrix.ps1`: render and validate public-default profile and environment combinations
- `validate-platform-assets.ps1`: validate rendered assets directly
- `validate-kubernetes-security-baseline.ps1`: review rendered Kubernetes YAML for risky defaults and baseline gaps
- `validate-workstation.ps1`: check local tools such as `kubectl`, `kubeconform`, and `helm`

Rendered manifest schema validation uses `kubeconform` when it is available and falls back to `kubectl apply --dry-run=client --validate=true`. This lets repository-only validation run without a live cluster dependency while preserving the `kubectl` path used by cluster workflows.

`validate-template.ps1` calls `validate-render-matrix.ps1` after the first smoke render. The matrix validates every bundled environment preset and each public profile shape with `config/platform-values.env.example`, so template maintainers can catch profile, preset, and default-value drift without writing rendered bundles into the repository.

See [../docs/testing.md](../docs/testing.md) for the command matrix, validator fallback rules, CRD-backed resource behavior, and Kubernetes security baseline findings.

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
.\scripts\invoke-repository-validation.ps1 -EnvironmentPreset dev
.\scripts\invoke-bundle-delivery.ps1 -EnvironmentPreset dev
```

## When To Use Which Script

- Use `show-*` scripts when you are deciding what to include.
- Use `validate-*` scripts when you want confidence before delivery or deployment.
- Use `invoke-*` scripts when you want the higher-level workflow rather than a low-level helper.
- Use `render-platform-assets.ps1` when you want direct rendering without the full delivery flow.
