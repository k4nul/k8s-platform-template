# Kubernetes Manifests

English | [한국어](README.ko.md)

This directory contains reusable Kubernetes manifests grouped by rollout phase and concern.

## Numbering Pattern

- `100_*`: base infrastructure
- `200_*`: storage
- `300_*`: shared services and cluster platform components
- `400_*` and `401_*`: application examples

The numbers are not just labels. They help show the intent and rough rollout order of the directories.

## Rollout Model

The repository-level plan uses broader phases such as:

- base infrastructure
- cluster add-ons
- shared services
- applications
- deferred post-controller resources

Some directories, such as Gateway API resources, are intentionally applied later even if their number is still in the `300_*` range.

## Recommended Way To Use These Manifests

Do not start by applying the raw repository directories directly unless you are intentionally using the repository as a source template.

The safer flow is:

1. edit values under `config/`
2. preview with `show-platform-plan.ps1`
3. render a bundle
4. review the rendered `out/` contents
5. apply from the rendered bundle

Example preview:

```powershell
.\scripts\show-platform-plan.ps1 -Format markdown
```

## What You Will Find Here

- shared infrastructure such as namespaces and storage
- platform services such as MySQL, PostgreSQL, Redis, Memcached, and NGINX
- optional add-on value scaffolds for components such as ExternalDNS, Harbor, Longhorn, Dashboard, and VPA
- public-image sample applications

Each component directory has its own `README.md` for local context.
