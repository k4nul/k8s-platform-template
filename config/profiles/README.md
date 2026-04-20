# Profiles

English | [한국어](README.ko.md)

Profiles describe reusable bundle shapes.

Examples:

- `minimal-application`: base namespaces and storage only
- `developer-sandbox`: small sandbox with common platform pieces
- `web-platform`: gateway-oriented public web stack
- `shared-services`: internal platform baseline
- `full`: everything in the repository

Use:

```powershell
.\scripts\show-profile-catalog.ps1 -Format markdown
```

to compare them side by side before choosing one.
