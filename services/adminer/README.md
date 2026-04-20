# adminer

Runs the public `adminer:5.3.0-standalone` image with no local build step.

Use it like this:

```powershell
docker compose --env-file ..\..\config\service-runtime.env.example up -d
```

Edit `ADMINER_DEFAULT_SERVER` in `config/service-runtime.env.example` to point at your MySQL or PostgreSQL host.
