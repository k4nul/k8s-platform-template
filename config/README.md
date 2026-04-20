# Config

English | [한국어](README.ko.md)

This directory is the main editing surface of the template. If you are adapting the repository for your own environment, you will usually start here before changing manifests or scripts.

## Edit These Files First

### 1. `platform-values*.env`

Use these files to set:

- hostnames
- storage configuration
- passwords and secret-like values
- bundle-level options referenced by Kubernetes manifests

Examples:

- `config/platform-values.env.example`
- `config/platform-values.dev.env`
- `config/platform-values.staging.env`
- `config/platform-values.prod.env`

### 2. `service-runtime.env.example`

Use this file for local Docker Compose examples:

- host ports
- default Adminer target

### 3. `environments/*.psd1`

Use environment presets when you want repeatable defaults for:

- validation
- bundle delivery
- promotion
- default output paths

See [environments/README.md](environments/README.md).

### 4. `profiles/*.psd1`

Use profiles when you want to change the shape of the bundle itself:

- which Kubernetes directories are included
- which service directories are included
- which profile description is shown in plans

See [profiles/README.md](profiles/README.md).

## What The `*.psd1` Catalogs Do

The PowerShell data files in this directory are mostly for template maintainers rather than first-time adopters.

They define things such as:

- service build assumptions
- runtime bindings
- pipeline metadata
- platform values catalog
- secret catalog

If you only want to use the repository, you usually do not need to edit them immediately.

## Recommended Editing Order

1. Create or copy a `platform-values.<env>.env` file
2. Replace example hostnames and passwords
3. Adjust `service-runtime.env.example` if you want local compose runs
4. Render or validate a bundle
5. Only then change profiles or catalogs if the overall template shape needs to change
