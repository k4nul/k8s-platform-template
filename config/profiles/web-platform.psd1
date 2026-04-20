@{
    Description = "Render a web-facing platform baseline with ingress, DNS, metrics, and public demo applications."
    PrimaryUse = "Public web platform baseline built around Gateway API style routing, DNS automation, and metrics."
    RecommendedFor = @(
        "Internet-facing web or API bundles",
        "Teams standardizing on Gateway API and controller-based routing",
        "Application stacks that want metrics and DNS automation from the start"
    )
    AvoidWhen = @(
        "A simpler NGINX reverse proxy is enough",
        "You only need shared data services or an internal platform foundation"
    )
    ExampleApplications = @(
        "nginx-web",
        "httpbin",
        "whoami"
    )
    ExampleDataServices = @(
        "redis"
    )
    IncludeAllK8s = $false
    IncludeAllServices = $false
    K8sDirectories = @(
        "100_namespace",
        "200_persistent-volume",
        "201_persistent-volume-claim",
        "305_platform_metrics-server",
        "306_platform_external-dns",
        "308_platform_gateway-api",
        "309_platform_nginx-gateway-fabric"
    )
    ServiceDirectories = @()
}
