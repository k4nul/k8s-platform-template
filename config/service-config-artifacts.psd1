@{
    Services = @(
        @{
            Name = "adminer"
            Notes = "No repository-managed JSON or INI artifacts are required because the container is configured with environment variables."
            ConfigArtifacts = @()
        }
        @{
            Name = "httpbin"
            Notes = "No repository-managed JSON or INI artifacts are required because the public image is used as-is."
            ConfigArtifacts = @()
        }
        @{
            Name = "nginx-web"
            Notes = "No repository-managed JSON or INI artifacts are required. Static example content is stored as plain HTML under services/nginx-web/site."
            ConfigArtifacts = @()
        }
        @{
            Name = "whoami"
            Notes = "No repository-managed JSON or INI artifacts are required because the public image is used as-is."
            ConfigArtifacts = @()
        }
    )
}
