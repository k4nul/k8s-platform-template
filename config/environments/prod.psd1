@{
    Description = "Generic production preset for a reusable shared-services baseline with public-image workloads."
    ValuesFile = "config\platform-values.prod.env"
    Version = "1.0.0"
    Profile = "shared-services"
    Applications = @(
        "nginx-web",
        "whoami"
    )
    DataServices = @(
        "postgresql",
        "redis"
    )
    IncludeJenkins = $false
    OutputPath = "out\delivery\prod"
    ArchivePath = "out\delivery\prod.zip"
    PromotionExtractPath = "out\promotion\prod"
}
