# nginx-web

Runs the public `nginx:1.28-alpine` image with a bind-mounted local static site.

Use it like this:

```powershell
docker compose --env-file ..\..\config\service-runtime.env.example up -d
```

Edit `site/index.html` for local content changes, or adjust `NGINX_WEB_HOST_PORT` in `config/service-runtime.env.example` if port `8080` is already in use.
