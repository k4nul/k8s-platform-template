# Environment Presets

English | [한국어](README.ko.md)

This directory contains reusable environment presets that reduce repeated arguments for the validation, delivery, promotion, and values scaffold scripts.

## Included Presets

- `dev.psd1`: small development-friendly web-platform baseline
- `staging.psd1`: broader shared-services baseline for pre-production checks
- `prod.psd1`: production-oriented shared-services baseline

## Common Keys

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

Explicit script arguments still override preset values, so the preset acts as a shared default rather than a hard lock.
