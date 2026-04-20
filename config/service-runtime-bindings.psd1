@{
    VariableOrder = @(
        "NGINX_WEB_HOST_PORT",
        "HTTPBIN_HOST_PORT",
        "WHOAMI_HOST_PORT",
        "ADMINER_HOST_PORT",
        "ADMINER_DEFAULT_SERVER"
    )

    Variables = @{
        "NGINX_WEB_HOST_PORT" = @{
            Description = "Host port used by the local nginx-web compose example."
            Example = "8080"
        }
        "HTTPBIN_HOST_PORT" = @{
            Description = "Host port used by the local httpbin compose example."
            Example = "8081"
        }
        "WHOAMI_HOST_PORT" = @{
            Description = "Host port used by the local whoami compose example."
            Example = "8082"
        }
        "ADMINER_HOST_PORT" = @{
            Description = "Host port used by the local Adminer compose example."
            Example = "8083"
        }
        "ADMINER_DEFAULT_SERVER" = @{
            Description = "Database host name shown by default in the Adminer login screen."
            Example = "postgresql"
        }
    }

    Services = @(
        @{
            Name = "adminer"
            ComposeServiceName = "adminer"
            PublicImage = "adminer:5.3.0-standalone"
            RequiredEnvVars = @("ADMINER_HOST_PORT", "ADMINER_DEFAULT_SERVER")
            ExposedPorts = @('${ADMINER_HOST_PORT}:8080')
            VolumeBindings = @()
            ContainerName = ""
            RequiresHostGateway = $false
            RestartPolicy = "always"
            RequiredComposeStrings = @(
                'image: adminer:5.3.0-standalone',
                '${ADMINER_HOST_PORT:?ADMINER_HOST_PORT must be set}:8080',
                'ADMINER_DEFAULT_SERVER: ${ADMINER_DEFAULT_SERVER:?ADMINER_DEFAULT_SERVER must be set}',
                'restart: always'
            )
            Notes = "Public Adminer image that can be pointed at an external or in-stack database."
        }
        @{
            Name = "httpbin"
            ComposeServiceName = "httpbin"
            PublicImage = "mccutchen/go-httpbin:v2.15.0"
            RequiredEnvVars = @("HTTPBIN_HOST_PORT")
            ExposedPorts = @('${HTTPBIN_HOST_PORT}:8080')
            VolumeBindings = @()
            ContainerName = ""
            RequiresHostGateway = $false
            RestartPolicy = "always"
            RequiredComposeStrings = @(
                'image: mccutchen/go-httpbin:v2.15.0',
                '${HTTPBIN_HOST_PORT:?HTTPBIN_HOST_PORT must be set}:8080',
                'restart: always'
            )
            Notes = "Public HTTP endpoint used for request and ingress validation."
        }
        @{
            Name = "nginx-web"
            ComposeServiceName = "nginx-web"
            PublicImage = "nginx:1.28-alpine"
            RequiredEnvVars = @("NGINX_WEB_HOST_PORT")
            ExposedPorts = @('${NGINX_WEB_HOST_PORT}:80')
            VolumeBindings = @(
                "./site -> /usr/share/nginx/html:ro"
            )
            ContainerName = ""
            RequiresHostGateway = $false
            RestartPolicy = "always"
            RequiredComposeStrings = @(
                'image: nginx:1.28-alpine',
                '${NGINX_WEB_HOST_PORT:?NGINX_WEB_HOST_PORT must be set}:80',
                './site:/usr/share/nginx/html:ro',
                'restart: always'
            )
            Notes = "Public NGINX image that serves the example static site from the local services/nginx-web/site directory."
        }
        @{
            Name = "whoami"
            ComposeServiceName = "whoami"
            PublicImage = "traefik/whoami:v1.10.4"
            RequiredEnvVars = @("WHOAMI_HOST_PORT")
            ExposedPorts = @('${WHOAMI_HOST_PORT}:80')
            VolumeBindings = @()
            ContainerName = ""
            RequiresHostGateway = $false
            RestartPolicy = "always"
            RequiredComposeStrings = @(
                'image: traefik/whoami:v1.10.4',
                '${WHOAMI_HOST_PORT:?WHOAMI_HOST_PORT must be set}:80',
                'restart: always'
            )
            Notes = "Public whoami image that helps validate routing and request metadata."
        }
    )
}
