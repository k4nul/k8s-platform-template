# Profiles

English | [한국어](README.ko.md)

Profiles describe reusable bundle shapes. A profile decides the broad layout of the bundle before you add or remove specific applications and data services.

## Included Profiles

- `minimal-application`: base namespaces and storage only
- `developer-sandbox`: compact sandbox with common platform pieces
- `web-platform`: gateway-oriented public web stack
- `shared-services`: shared cluster baseline
- `full`: everything in the repository

## How To Choose One

Use:

```powershell
.\scripts\show-profile-catalog.ps1 -Format markdown
```

Choose based on the question you are trying to answer:

- "What is the smallest usable template?" -> `minimal-application`
- "What can I test quickly?" -> `developer-sandbox`
- "What should I use for a web-facing example stack?" -> `web-platform`
- "What should I use for cluster-wide shared components?" -> `shared-services`

## Important Note

Profiles do not have to be the final word. You can still add or remove applications and data services with command arguments after choosing a profile.
