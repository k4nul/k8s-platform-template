# ExternalDNS Helm Template

Use this directory when you want Kubernetes Services or Ingress resources to create and update DNS records automatically.

## What To Replace

- `provider.name` in `values.yaml`
- `domainFilters`
- `txtOwnerId`
- `env` or `extraArgs` with the credentials and provider-specific flags required by your DNS platform

## Helm Install Example

```powershell
helm repo add external-dns https://kubernetes-sigs.github.io/external-dns/
helm repo update

helm upgrade --install external-dns external-dns/external-dns `
  --namespace platform `
  --create-namespace `
  -f .\k8s\306_platform_external-dns\values.yaml
```

## Notes

- The values file is intentionally provider-agnostic and starts with placeholders.
- By default it is scoped to the `platform` namespace and watches `Service` and `Ingress` resources.
- If you use Gateway API sources, review RBAC and namespace scope requirements before enabling them.
