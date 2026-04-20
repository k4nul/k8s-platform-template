# whoami

Runs the public `traefik/whoami:v1.10.4` image with no local build step.

Use it like this:

```powershell
docker compose --env-file ..\..\config\service-runtime.env.example up -d
```

This is useful for validating routing rules, forwarded headers, and source IP handling.
