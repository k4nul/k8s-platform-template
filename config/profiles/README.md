# Profiles

English | [한국어](README.ko.md)

Profiles describe reusable bundle shapes. A profile decides the broad layout of the bundle before you add or remove specific applications and data services.

## Included Profiles

- `minimal-application`: base namespaces and storage only
- `developer-sandbox`: compact sandbox with common platform pieces
- `data-services`: shared database and cache baseline
- `reverse-proxy-platform`: NGINX-centered edge stack
- `web-platform`: gateway-oriented public web stack
- `shared-services`: shared cluster baseline
- `full`: every standard component directory and service template; optional follow-up manifests stay manual

## How To Choose One

Use:

```powershell
.\scripts\show-profile-catalog.ps1 -Format markdown
```

Choose based on the question you are trying to answer:

- "What is the smallest usable template?" -> `minimal-application`
- "What can I test quickly?" -> `developer-sandbox`
- "What shared databases and caches are available?" -> `data-services`
- "What is the simpler reverse-proxy option?" -> `reverse-proxy-platform`
- "What should I use for a web-facing example stack?" -> `web-platform`
- "What should I use for cluster-wide shared components?" -> `shared-services`

## Important Note

Profiles do not have to be the final word. You can still add or remove applications and data services with command arguments after choosing a profile.

Each bundled profile is covered by `scripts/validate-render-matrix.ps1` with public default values. The representative applications and data services are declared in each profile file with `ValidationApplications` and `ValidationDataServices`, so profile ownership and validation coverage stay together.

Optional follow-up manifests, such as the Kubernetes Dashboard sample admin
user and the VPA example object, are listed in platform plans but are not copied
into generated bundles by default.
