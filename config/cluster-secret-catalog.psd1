@{
    Secrets = @(
        @{
            MatchName = "mysql-sec"
            SecretType = "Opaque"
            TemplateType = "opaque"
            Description = "MySQL credentials consumed by the in-cluster MySQL StatefulSet."
            RequiredKeys = @(
                "MYSQL_ROOT_PASSWORD",
                "MYSQL_USER",
                "MYSQL_PASSWORD"
            )
            ExampleValues = @{
                MYSQL_ROOT_PASSWORD = "change-me-mysql-root-password"
                MYSQL_USER = "platform_app"
                MYSQL_PASSWORD = "change-me-mysql-app-password"
            }
            CreationHint = "Create this secret before applying the MySQL StatefulSet if you include the MySQL component."
            ExampleCommand = "kubectl create secret generic <name> -n <namespace> --from-literal=MYSQL_ROOT_PASSWORD=change-me-mysql-root-password --from-literal=MYSQL_USER=platform_app --from-literal=MYSQL_PASSWORD=change-me-mysql-app-password"
        }
        @{
            MatchName = "postgresql-sec"
            SecretType = "Opaque"
            TemplateType = "opaque"
            Description = "PostgreSQL credentials consumed by the in-cluster PostgreSQL StatefulSet."
            RequiredKeys = @(
                "POSTGRES_DB",
                "POSTGRES_USER",
                "POSTGRES_PASSWORD"
            )
            ExampleValues = @{
                POSTGRES_DB = "platform_db"
                POSTGRES_USER = "platform_app"
                POSTGRES_PASSWORD = "change-me-postgresql-password"
            }
            CreationHint = "Create this secret before applying the PostgreSQL StatefulSet if you include the PostgreSQL component."
            ExampleCommand = "kubectl create secret generic <name> -n <namespace> --from-literal=POSTGRES_DB=platform_db --from-literal=POSTGRES_USER=platform_app --from-literal=POSTGRES_PASSWORD=change-me-postgresql-password"
        }
        @{
            MatchValueKey = "HARBOR_TLS_SECRET"
            SecretType = "kubernetes.io/tls"
            TemplateType = "tls"
            Description = "TLS certificate referenced by the Harbor ingress."
            RequiredKeys = @(
                "tls.crt",
                "tls.key"
            )
            CreationHint = "Use kubectl create secret tls if you already have the Harbor certificate and private key."
            ExampleCommand = "kubectl create secret tls <name> -n <namespace> --cert=path/to/tls.crt --key=path/to/tls.key"
        }
        @{
            MatchValueKey = "LONGHORN_TLS_SECRET"
            SecretType = "kubernetes.io/tls"
            TemplateType = "tls"
            Description = "TLS certificate referenced by the Longhorn ingress."
            RequiredKeys = @(
                "tls.crt",
                "tls.key"
            )
            CreationHint = "Use kubectl create secret tls if you already have the Longhorn certificate and private key."
            ExampleCommand = "kubectl create secret tls <name> -n <namespace> --cert=path/to/tls.crt --key=path/to/tls.key"
        }
        @{
            MatchValueKey = "LONGHORN_BASIC_AUTH_SECRET"
            SecretType = "Opaque"
            TemplateType = "basic-auth"
            Description = "Basic-auth credentials referenced by the Longhorn ingress annotations."
            RequiredKeys = @(
                "auth"
            )
            ExampleValues = @{
                auth = "admin:{HTPASSWD_OUTPUT}"
            }
            CreationHint = "Create the auth file with htpasswd output and store it under the 'auth' key."
            ExampleCommand = "kubectl create secret generic <name> -n <namespace> --from-file=auth=path/to/auth"
        }
        @{
            MatchValueKey = "DASHBOARD_TLS_SECRET"
            SecretType = "kubernetes.io/tls"
            TemplateType = "tls"
            Description = "TLS certificate referenced by the Kubernetes Dashboard ingress."
            RequiredKeys = @(
                "tls.crt",
                "tls.key"
            )
            CreationHint = "Use kubectl create secret tls if you already have the Dashboard certificate and private key."
            ExampleCommand = "kubectl create secret tls <name> -n <namespace> --cert=path/to/tls.crt --key=path/to/tls.key"
        }
    )
}
