# NGINX Gateway Fabric Helm Template

Use this directory when you want to implement Gateway API with NGINX as the data plane.

## Install Example

Install Gateway API CRDs first. Then install NGINX Gateway Fabric from the official OCI Helm registry:

```powershell
helm upgrade --install ngf oci://ghcr.io/nginx/charts/nginx-gateway-fabric `
  --namespace nginx-gateway `
  --create-namespace `
  -f .\k8s\309_platform_nginx-gateway-fabric\values.yaml
```

## What To Replace

- `gatewayClassName`
- control plane and data plane replica counts
- resource requests and limits
- any namespace watching restrictions

## Notes

- The values template disables product telemetry by default.
- If you later choose NGINX Plus, review the official JWT and private registry requirements before changing the image settings.
- Pair this directory with the `k8s/308_platform_gateway-api` examples for actual `Gateway` and `HTTPRoute` resources.
