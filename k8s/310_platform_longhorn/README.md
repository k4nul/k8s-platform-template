# Longhorn Helm Template

Use this directory when you want Kubernetes-native distributed block storage on clusters that do not already provide a suitable storage layer.

## Install Example

```powershell
helm repo add longhorn https://charts.longhorn.io
helm repo update

helm upgrade --install longhorn longhorn/longhorn `
  --namespace longhorn-system `
  --create-namespace `
  -f .\k8s\310_platform_longhorn\values.yaml
```

## What To Replace

- replica counts to match your node count
- ingress host, class, and TLS secret
- `defaultDataPath` if you mount storage on a dedicated path

## Notes

- Longhorn requires Kubernetes `>= 1.25`, `open-iscsi`, and a running `iscsid` daemon on every node.
- RWX workloads also require an NFSv4 client on each node.
- Longhorn UI access through ingress often needs large upload limits; the included annotations follow the official guidance for that.
- If your cluster already has a production-grade storage platform, keep this component optional.
