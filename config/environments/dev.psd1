@{
    Description = "Generic development preset for a small public-facing sandbox built from public container images."
    ValuesFile = "config\platform-values.dev.env"
    Version = "0.0.0-dev"
    Profile = "web-platform"
    Applications = @(
        "nginx-web",
        "httpbin",
        "whoami"
    )
    DataServices = @(
        "redis"
    )
    IncludeJenkins = $false
    OutputPath = "out\delivery\dev"
    ArchivePath = "out\delivery\dev.zip"
    PromotionExtractPath = "out\promotion\dev"
}
