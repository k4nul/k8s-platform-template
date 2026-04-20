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
- `show-jenkins-job-plan.ps1`: preview the Jenkins job chain

### Validate

- `validate-template.ps1`: validate repository structure and example assets
- `invoke-repository-validation.ps1`: run the main validation flow
- `validate-platform-assets.ps1`: validate rendered assets directly
- `validate-workstation.ps1`: check local tools such as `kubectl` and `helm`

### Render And Deliver

- `render-platform-assets.ps1`: render a bundle directly
- `invoke-bundle-delivery.ps1`: render, validate, and archive a bundle
- `invoke-bundle-promotion.ps1`: unpack and re-validate a delivered bundle
- `new-platform-environment.ps1`: create a values file from a preset

## Typical Command Flow

```powershell
.\scripts\show-profile-catalog.ps1 -Format markdown
.\scripts\new-platform-environment.ps1 -EnvironmentPreset dev -EnvironmentName dev -Force
.\scripts\invoke-repository-validation.ps1 -EnvironmentPreset dev
.\scripts\invoke-bundle-delivery.ps1 -EnvironmentPreset dev
```

## When To Use Which Script

- Use `show-*` scripts when you are deciding what to include.
- Use `validate-*` scripts when you want confidence before delivery or deployment.
- Use `invoke-*` scripts when you want the higher-level workflow rather than a low-level helper.
- Use `render-platform-assets.ps1` when you want direct rendering without the full delivery flow.
