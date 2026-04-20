# httpbin

Runs the public `mccutchen/go-httpbin:v2.15.0` image with no local build step.

Use it like this:

```powershell
docker compose --env-file ..\..\config\service-runtime.env.example up -d
```

This is useful for checking reverse proxies, API gateways, and request headers locally.
