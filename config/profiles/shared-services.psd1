@{
    Description = "Render a reusable internal platform baseline with storage, registry, admin, and autoscaling add-ons."
    PrimaryUse = "Broader internal platform foundation for organizations that want shared storage, registry, admin, and autoscaling building blocks."
    RecommendedFor = @(
        "Platform teams preparing a reusable internal cluster baseline",
        "Environments that need shared storage, registry, admin access, and scaling add-ons",
        "Organizations standardizing common platform services before onboarding applications"
    )
    AvoidWhen = @(
        "You want the lightest possible developer or application-only footprint",
        "You do not plan to operate Harbor, Longhorn, Dashboard, or VPA in-cluster"
    )
    ExampleApplications = @(
        "nginx-web",
        "adminer"
    )
    ExampleDataServices = @(
        "postgresql",
        "redis"
    )
    IncludeAllK8s = $false
    IncludeAllServices = $false
    K8sDirectories = @(
        "100_namespace",
        "305_platform_metrics-server",
        "306_platform_external-dns",
        "307_platform_harbor",
        "308_platform_gateway-api",
        "309_platform_nginx-gateway-fabric",
        "310_platform_longhorn",
        "311_platform_kubernetes-dashboard",
        "312_platform_vertical-pod-autoscaler"
    )
    ServiceDirectories = @()
}
