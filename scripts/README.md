# Scripts

English | [한국어](README.ko.md)

This directory contains the operational entry points for the template.

Most useful commands:

- `validate-template.ps1`: validate repository structure and example assets
- `invoke-repository-validation.ps1`: run the main validation flow
- `invoke-bundle-delivery.ps1`: render, validate, and archive a bundle
- `invoke-bundle-promotion.ps1`: unpack and re-validate a delivered bundle
- `render-platform-assets.ps1`: render a bundle directly
- `show-platform-plan.ps1`: preview selected components
- `show-platform-values-plan.ps1`: preview required values
- `show-service-runtime-plan.ps1`: preview compose runtime variables
- `show-jenkins-job-plan.ps1`: preview the generic Jenkins job chain
