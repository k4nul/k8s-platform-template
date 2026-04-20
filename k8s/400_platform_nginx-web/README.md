# nginx-web

Uses the public `nginx:1.28-alpine` image as a generic static web example.

Files:

- `config.yaml`: example landing page content rendered from `NGINX_WEB_MESSAGE`
- `nginx-web.yaml`: deployment using the official NGINX image
- `service.yaml`: internal ClusterIP service on port `80`

Adjust `NGINX_WEB_MESSAGE` in your values file or edit the ConfigMap content directly if you want a different landing page.
