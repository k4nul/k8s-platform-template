# Deployment Environment Notes

This repository is intentionally generic. The default application layer uses public images, and the environment-specific work is focused on values files, hostnames, secrets, storage choices, and optional add-ons.

## What Users Are Expected To Edit

Primary files:

- `config/platform-values.env.example`
- `config/platform-values.dev.env`
- `config/platform-values.staging.env`
- `config/platform-values.prod.env`
- `config/service-runtime.env.example`

Typical edits:

- NFS server and export path
- Redis password
- Gateway or ingress hostnames
- ExternalDNS owner ID and provider
- Harbor, Longhorn, and Dashboard hostnames or TLS secret names
- Adminer default database host
- Local compose host ports

## Local Compose Examples

The `services/` directory is now compose-first and public-image-first:

- `services/nginx-web`
- `services/httpbin`
- `services/whoami`
- `services/adminer`

Each directory has its own `README.md` with the expected local command and the env vars it uses.

## Kubernetes Manifests

The Kubernetes examples now use common service ports:

- MySQL: `3306`
- PostgreSQL: `5432`
- HTTP services: `80`
- Adminer: `8080`

The default application manifests do not require a private image registry.
