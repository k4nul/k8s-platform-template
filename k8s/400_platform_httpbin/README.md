# httpbin

Uses the public `mccutchen/go-httpbin:v2.15.0` image for generic API and ingress testing.

Files:

- `httpbin.yaml`: deployment with HTTP readiness and liveness checks
- `service.yaml`: internal ClusterIP service on port `80`

Useful for testing load balancers, API gateways, and request rewriting without introducing a custom application image.
