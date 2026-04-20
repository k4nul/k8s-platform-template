@{
    Services = @(
        @{
            Name = "adminer"
            SourceType = "public-image"
            BuildProfile = "public-image"
            PublicImage = "adminer:5.3.0-standalone"
            Notes = "Uses the official Adminer image directly, so no local Docker build or private registry is required."
        }
        @{
            Name = "httpbin"
            SourceType = "public-image"
            BuildProfile = "public-image"
            PublicImage = "mccutchen/go-httpbin:v2.15.0"
            Notes = "Uses the public HTTPBin-compatible image directly for API and ingress smoke tests."
        }
        @{
            Name = "nginx-web"
            SourceType = "public-image"
            BuildProfile = "public-image"
            PublicImage = "nginx:1.28-alpine"
            Notes = "Uses the official NGINX image directly for static web content examples."
        }
        @{
            Name = "whoami"
            SourceType = "public-image"
            BuildProfile = "public-image"
            PublicImage = "traefik/whoami:v1.10.4"
            Notes = "Uses the public whoami image directly for lightweight routing and header validation."
        }
    )
}
