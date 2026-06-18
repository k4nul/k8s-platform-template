# Environment Presets

English | [한국어](README.ko.md)

This directory contains reusable environment presets that reduce repeated arguments for validation, delivery, promotion, and values scaffold scripts.

## Included Presets

- `dev.psd1`: development-friendly web-platform baseline
- `staging.psd1`: broader shared-services baseline for pre-production checks
- `prod.psd1`: production-oriented shared-services baseline

## What A Preset Usually Controls

- `ValuesFile`: default values file path
- `ValidationValuesFile`: optional public-default values file for clean repository validation
- `DockerRegistry`: optional registry host used only when you introduce private images
- `Version`: default image tag or validation tag
- `Profile`: default bundle profile
- `Applications`: default application selection
- `DataServices`: default data service selection
- `OutputPath`: default rendered bundle output path for delivery workflows
- `ArchivePath`: default ZIP archive path for delivery or promotion workflows
- `PromotionExtractPath`: default extraction path for promotion workflows
- `RenderedPath`: optional default rendered bundle path for repository validation workflows

## How To Use A Preset

Example:

```powershell
.\scripts\invoke-repository-validation.ps1 -EnvironmentPreset dev
.\scripts\invoke-bundle-delivery.ps1 -EnvironmentPreset dev
```

Presets act as shared defaults, not hard locks. Explicit script arguments still override preset values.

That means you can start from `dev` and still override:

- profile
- application list
- data service list
- output paths

without editing the preset file immediately.

## Validation Matrix

Template validation includes every `config/environments/*.psd1` file as an environment matrix entry, but the template gate passes an explicit public values file so every entry uses `config/platform-values.env.example`.

When you run `validate-render-matrix.ps1` directly, environment values resolve in this order: an explicit `-ValuesFile` override, `ValidationValuesFile`, `ValuesFile`, then `config/platform-values.env.example`.

The bundled presets point `ValidationValuesFile` at `config/platform-values.env.example`, which keeps public validation independent from local `platform-values.<env>.env` files that may contain site-specific hostnames, storage paths, or secret placeholders.

After editing a generated environment values file, pass it explicitly:

```powershell
.\scripts\invoke-repository-validation.ps1 `
  -EnvironmentPreset dev `
  -ValuesFile config\platform-values.dev.env
```

Run the full render matrix directly with:

```powershell
.\scripts\validate-render-matrix.ps1
```

That command validates environment preset entries first, then every profile entry
under `config/profiles/`.

Inspect the same matrix without rendering bundles with:

```powershell
.\scripts\show-render-matrix.ps1 -Format markdown
```

For the full validation flow and the difference between template validation, repository validation, and delivery validation, see [../../docs/testing.md](../../docs/testing.md).
