# Harbor Helm Template

Use this directory when you want a private container and artifact registry that can be shared by many teams and applications.

## What To Replace

- `externalURL`
- `harborAdminPassword`
- ingress host names and ingress class
- storage classes and PVC sizes
- TLS secret names or expose mode

## Helm Install Example

```powershell
helm repo add harbor https://helm.goharbor.io
helm repo update

helm upgrade --install harbor harbor/harbor `
  --namespace platform `
  --create-namespace `
  -f .\k8s\307_platform_harbor\values.yaml
```

## Notes

- This template keeps Harbor self-contained with internal database and Redis enabled by default.
- For larger environments, move Harbor to an external PostgreSQL and Redis deployment, or tune the chart values to match your platform standards.
- If your cluster already uses a shared ingress controller and cert-manager, plug those values into the template before rollout.
