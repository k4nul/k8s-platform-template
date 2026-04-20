@{
    Description = "Render a lightweight developer sandbox with a reverse proxy, metrics, and a couple of public demo apps."
    PrimaryUse = "Small-team or local-cluster baseline for trying generic workloads without private images."
    RecommendedFor = @(
        "Docker Desktop, kind, k3d, or k3s test clusters",
        "Quick ingress and service discovery experiments",
        "Teams validating a generic platform skeleton before customizing it"
    )
    AvoidWhen = @(
        "You need a production-oriented shared services baseline",
        "You do not want MySQL or Redis inside the cluster"
    )
    ExampleApplications = @(
        "nginx-web",
        "httpbin",
        "whoami"
    )
    ExampleDataServices = @(
        "mysql",
        "redis"
    )
    IncludeAllK8s = $false
    IncludeAllServices = $false
    K8sDirectories = @(
        "100_namespace",
        "200_persistent-volume",
        "201_persistent-volume-claim",
        "301_platform_mysql",
        "302_platform_redis",
        "304_platform_nginx",
        "305_platform_metrics-server"
    )
    ServiceDirectories = @()
}
