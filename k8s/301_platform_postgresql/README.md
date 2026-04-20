# 301_platform_postgresql

Public-image PostgreSQL example using the official `postgres:16-alpine` image and the common port `5432`.

Files:

- `postgresql.yaml`: StatefulSet with readiness and liveness checks

Create the `postgresql-sec` secret before deployment.
