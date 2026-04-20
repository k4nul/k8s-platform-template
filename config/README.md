# Config

English | [한국어](README.ko.md)

This directory contains the editable configuration surface of the template.

Main areas:

- `platform-values*.env`: environment-specific values for rendered Kubernetes assets
- `service-runtime.env.example`: local compose env vars for the public-image examples
- `environments/`: reusable presets such as `dev`, `staging`, and `prod`
- `profiles/`: reusable bundle shapes
- `*.psd1`: catalogs used by planning and validation scripts

Most adopters will edit the `.env` files first and only then customize the deeper catalog files if they want to change the structure of the template itself.
