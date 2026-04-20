@{
    Services = @(
        @{
            Name = "adminer"
            Category = "public-image"
            ImageName = "adminer:5.3.0-standalone"
            BuildTagStrategy = "none"
            RequiresMode = $false
            UsesCacheToggle = $false
            UsesModeBuildArg = $false
            ComposeUpdate = "manual"
            RequiresRegistry = $false
            HasJenkinsfile = $false
            OptionalEnvVars = @()
            RequiredFiles = @(
                "README.md",
                "docker-compose.yaml"
            )
            ArtifactInputs = @(
                "Uses the public Adminer image directly. Add a Jenkins wrapper only if you want a compose-based smoke test job."
            )
            RequiredJenkinsStrings = @()
            Notes = "Compose-first public image example with no repository build step."
        }
        @{
            Name = "httpbin"
            Category = "public-image"
            ImageName = "mccutchen/go-httpbin:v2.15.0"
            BuildTagStrategy = "none"
            RequiresMode = $false
            UsesCacheToggle = $false
            UsesModeBuildArg = $false
            ComposeUpdate = "manual"
            RequiresRegistry = $false
            HasJenkinsfile = $false
            OptionalEnvVars = @()
            RequiredFiles = @(
                "README.md",
                "docker-compose.yaml"
            )
            ArtifactInputs = @(
                "Uses the public HTTPBin-compatible image directly. Add a Jenkins wrapper only if you want a pull-and-health-check job."
            )
            RequiredJenkinsStrings = @()
            Notes = "Compose-first public image example with no repository build step."
        }
        @{
            Name = "nginx-web"
            Category = "public-image"
            ImageName = "nginx:1.28-alpine"
            BuildTagStrategy = "none"
            RequiresMode = $false
            UsesCacheToggle = $false
            UsesModeBuildArg = $false
            ComposeUpdate = "manual"
            RequiresRegistry = $false
            HasJenkinsfile = $false
            OptionalEnvVars = @()
            RequiredFiles = @(
                "README.md",
                "docker-compose.yaml",
                "site\\index.html"
            )
            ArtifactInputs = @(
                "Uses the public NGINX image directly. Local customization happens by editing services/nginx-web/site/index.html."
            )
            RequiredJenkinsStrings = @()
            Notes = "Compose-first public image example with no repository build step."
        }
        @{
            Name = "whoami"
            Category = "public-image"
            ImageName = "traefik/whoami:v1.10.4"
            BuildTagStrategy = "none"
            RequiresMode = $false
            UsesCacheToggle = $false
            UsesModeBuildArg = $false
            ComposeUpdate = "manual"
            RequiresRegistry = $false
            HasJenkinsfile = $false
            OptionalEnvVars = @()
            RequiredFiles = @(
                "README.md",
                "docker-compose.yaml"
            )
            ArtifactInputs = @(
                "Uses the public whoami image directly. Add a Jenkins wrapper only if you want a pull-and-response test job."
            )
            RequiredJenkinsStrings = @()
            Notes = "Compose-first public image example with no repository build step."
        }
    )
}
