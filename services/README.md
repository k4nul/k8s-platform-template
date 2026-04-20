# Service Examples

English | [한국어](README.ko.md)

This directory contains local Docker Compose examples that mirror the generic Kubernetes application examples.

## Design Rules

- public images first
- no private registry required by default
- no repository build step required for the sample services
- per-service `README.md` in every service folder

## Included Services

- `nginx-web`: static site example based on `nginx:1.28-alpine`
- `httpbin`: API test service based on `mccutchen/go-httpbin:v2.15.0`
- `whoami`: routing test service based on `traefik/whoami:v1.10.4`
- `adminer`: database UI based on `adminer:5.3.0-standalone`

## Common Usage

```powershell
docker compose --env-file ..\config\service-runtime.env.example up -d
```

## Common Env File

Edit `config/service-runtime.env.example` to change:

- local host ports
- the default Adminer database target

Use `scripts/show-service-runtime-plan.ps1 -Format markdown` when you want a generated summary of the runtime variables and compose expectations.
