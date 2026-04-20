# Kubernetes Dashboard Helm Template

Use this directory when you want a general-purpose web UI for browsing cluster resources.

## Install Example

```powershell
helm repo add kubernetes-dashboard https://kubernetes.github.io/dashboard/
helm repo update

helm upgrade --install kubernetes-dashboard kubernetes-dashboard/kubernetes-dashboard `
  --namespace kubernetes-dashboard `
  --create-namespace `
  -f .\k8s\311_platform_kubernetes-dashboard\values.yaml
```

## Access Example

```powershell
kubectl -n kubernetes-dashboard port-forward svc/kubernetes-dashboard-kong-proxy 8443:443
```

Kubernetes Dashboard currently supports logging in with a bearer token.

If you use the sample admin manifest in this directory, retrieve a token with:

```powershell
kubectl -n kubernetes-dashboard create token admin-user
```

## Notes

- The sample admin user is intentionally high privilege and should be limited or removed in real environments.
- The chart already bundles Kong and can optionally bundle metrics-server, cert-manager, or nginx ingress, but this template assumes those are managed separately.
- This template enables ingress but does not force any single ingress controller.
