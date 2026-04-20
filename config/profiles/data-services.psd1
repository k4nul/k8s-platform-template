@{
    Description = "Render a shared data-services baseline with common relational databases and caches."
    PrimaryUse = "Shared in-cluster databases and caches that can be reused by multiple application bundles."
    RecommendedFor = @(
        "Platform teams standing up common stateful backends first",
        "Clusters that will host multiple application bundles over time",
        "Environments where databases and caches should be managed separately from edge and app layers"
    )
    AvoidWhen = @(
        "You need ingress, reverse proxy, or public exposure in the same starting profile",
        "You want an application-ready stack without additional component selection"
    )
    ExampleApplications = @()
    ExampleDataServices = @()
    IncludeAllK8s = $false
    IncludeAllServices = $false
    K8sDirectories = @(
        "100_namespace",
        "200_persistent-volume",
        "201_persistent-volume-claim",
        "301_platform_mysql",
        "301_platform_postgresql",
        "302_platform_redis",
        "303_platform_memcached"
    )
    ServiceDirectories = @()
}
