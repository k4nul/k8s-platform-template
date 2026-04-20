# 301_platform_mysql

Public-image MySQL example using the official MySQL container image and the common port `3306`.

Files:

- `mysql.yaml`: StatefulSet
- `svc.yaml`: ClusterIP service
- `config.yaml`: MySQL configuration

Create the `mysql-sec` secret before deployment.
