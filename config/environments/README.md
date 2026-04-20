# Environment Presets

English | [한국어](README.ko.md)

This directory contains reusable environment presets that reduce repeated arguments for validation, delivery, promotion, and values scaffold scripts.

## Included Presets

- `dev.psd1`: development-friendly web-platform baseline
- `staging.psd1`: broader shared-services baseline for pre-production checks
- `prod.psd1`: production-oriented shared-services baseline

## What A Preset Usually Controls

- `ValuesFile`: default values file path
- `DockerRegistry`: optional registry host used only when you introduce private images
- `Version`: default image tag or validation tag
- `Profile`: default bundle profile
- `Applications`: default application selection
- `DataServices`: default data service selection
- `IncludeJenkins`: whether the selected bundle should include Jenkins components
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
