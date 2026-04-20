@{
    Description = "Render a simpler edge stack centered on NGINX plus optional DNS automation."
    PrimaryUse = "Public or internal HTTP stacks that want straightforward reverse-proxy patterns instead of a fuller Gateway API setup."
    RecommendedFor = @(
        "Teams that prefer a traditional reverse proxy entry point",
        "Bundles that want a light public edge without extra gateway controller complexity",
        "Static site or HTTP smoke-test workloads"
    )
    AvoidWhen = @(
        "You are standardizing on Gateway API",
        "You need the broadest shared-services platform baseline"
    )
    ExampleApplications = @(
        "nginx-web",
        "whoami"
    )
    ExampleDataServices = @()
    IncludeAllK8s = $false
    IncludeAllServices = $false
    K8sDirectories = @(
        "100_namespace",
        "304_platform_nginx",
        "306_platform_external-dns"
    )
    ServiceDirectories = @()
}
