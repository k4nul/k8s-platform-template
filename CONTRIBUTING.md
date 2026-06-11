# Contributing to Kubernetes Platform Template

This project is a reusable Kubernetes platform template. Keep public defaults,
example hostnames, and generated bundle behavior safe for a public repository.

## Local Setup

```powershell
pwsh -NoProfile -File scripts/validate-template.ps1
```

For end-to-end rendering behavior, use:

```powershell
pwsh -NoProfile -File scripts/invoke-repository-validation.ps1 -EnvironmentPreset dev
```

## Pull Request Checklist

- Do not commit rendered `out/` bundles, kubeconfigs, real secrets, or local env files.
- Keep public image defaults unless the change is explicitly about registry support.
- Update `config/`, `k8s/`, `services/`, or `scripts/` docs when their contracts change.
- Keep optional platform components opt-in and clearly documented.

## Secret and Cluster Policy

Use placeholders in examples. Real namespaces, hostnames, TLS material, registry
credentials, and cluster bootstrap secrets belong in local files or external
secret managers, not in this repository.
