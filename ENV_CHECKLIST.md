# Environment Checklist

Use this checklist before treating the repository as a real deployment source.

## Required Replacements

Replace every environment-specific placeholder before production rollout:

- values in `config/platform-values*.env`
- example domains under `example.com`
- example internal hosts such as `nfs.example.internal`
- example passwords such as `change-me-*`
- TLS secret names that do not exist in your cluster

## Decisions To Make Up Front

- storage strategy:
  - existing storage class
  - NFS-backed PV/PVC
  - Longhorn
- public traffic strategy:
  - internal-only ClusterIP
  - reverse proxy with `304_platform_nginx`
  - Gateway API with `309_platform_nginx-gateway-fabric`
- DNS automation strategy:
  - none
  - ExternalDNS
- data service strategy:
  - external managed database
  - in-cluster MySQL
  - in-cluster PostgreSQL
  - Redis and Memcached as supporting services

## Validation Commands

```powershell
.\scripts\validate-template.ps1
.\scripts\validate-workstation.ps1
.\scripts\invoke-repository-validation.ps1 -EnvironmentPreset dev
.\scripts\check-placeholders.ps1 -Path . -FailOnMatch
```

## Final Questions

You are ready to deploy when all answers are yes:

- Have all example domains and passwords been replaced?
- Do all referenced storage classes exist?
- Do all referenced TLS secrets exist or have a creation plan?
- Have you removed any sample applications you do not want to ship?
- Have you validated the selected bundle in a non-production cluster or namespace?
