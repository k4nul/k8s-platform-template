# Service Examples

English | [한국어](README.ko.md)

This directory contains local Docker Compose examples that mirror the generic Kubernetes application examples in `k8s/`.

Use these examples when you want to:

- try a sample app locally before touching a cluster
- inspect the public images used by default
- verify ports and simple runtime behavior

## Design Rules

- public images first
- no private registry required by default
- no repository build step required for the sample services
- one service directory per example
- per-service `README.md` in every service folder

## Included Services

- `nginx-web`: static site example based on `nginx:1.28-alpine`
- `httpbin`: API test service based on `mccutchen/go-httpbin:v2.15.0`
- `whoami`: routing test service based on `traefik/whoami:v1.10.4`
- `adminer`: database UI based on `adminer:5.3.0-standalone`

## Run One Example

From a service directory:

```powershell
docker compose --env-file ..\..\config\service-runtime.env.example up -d
```

Example:

```powershell
cd .\services\nginx-web
docker compose --env-file ..\..\config\service-runtime.env.example up -d
```

## Stop And Clean Up

```powershell
docker compose down
```

## Shared Runtime Variables

Edit `config/service-runtime.env.example` to change:

- local host ports
- the default Adminer database target

If you want a generated summary of the runtime variables and compose expectations:

```powershell
.\scripts\show-service-runtime-plan.ps1 -Format markdown
```

## Relationship To `k8s/`

These compose examples are intentionally simple mirrors of the public-image Kubernetes examples.

They are useful for:

- content edits
- quick endpoint tests
- smoke testing before cluster rendering

They are not intended to represent full production parity with every Kubernetes deployment detail.
