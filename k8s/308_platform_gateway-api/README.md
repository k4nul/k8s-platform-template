# Gateway API Base Template

Use this directory when you want a modern, controller-agnostic traffic entry model for Kubernetes instead of relying only on legacy Ingress resources.

Install the standard Gateway API CRDs before applying these examples.

Included files:

- `gateway.yaml`: shared HTTP listener for the `platform` namespace
- `httproute-nginx-web.yaml`: example route for the NGINX demo site
- `httproute-httpbin.yaml`: example route for the HTTP test endpoint
- `httproute-whoami.yaml`: example route for the whoami test endpoint

What to replace:

- `gatewayClassName`
- example hostnames such as `nginx.example.com`
- backend services if you swap the sample applications for your own
