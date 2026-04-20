# Kubernetes Manifests

English | [한국어](README.ko.md)

This directory contains reusable Kubernetes manifests grouped by rollout phase and concern.

Naming pattern:

- `100_*`: base infrastructure
- `200_*`: storage
- `300_*`: shared services
- `400_*` and `401_*`: application examples

Use:

```powershell
.\scripts\show-platform-plan.ps1 -Format markdown
```

to see which directories are selected by a profile or application list before rendering a bundle.
