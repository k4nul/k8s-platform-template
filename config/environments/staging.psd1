@{
    Description = "Generic staging preset for validating shared services and public demo applications before production rollout."
    ValuesFile = "config\platform-values.staging.env"
    Version = "0.0.0-staging"
    Profile = "shared-services"
    Applications = @(
        "nginx-web",
        "httpbin",
        "adminer"
    )
    DataServices = @(
        "postgresql",
        "redis"
    )
    IncludeJenkins = $false
    OutputPath = "out\delivery\staging"
    ArchivePath = "out\delivery\staging.zip"
    PromotionExtractPath = "out\promotion\staging"
}
