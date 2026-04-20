@{
    Description = "Render a minimal application baseline with namespaces and shared storage only."
    PrimaryUse = "Small application bundles that want to add only the workloads and data services they actually need."
    RecommendedFor = @(
        "Learning or lab environments",
        "Teams that prefer to opt into applications one by one",
        "Bundles that rely mostly on external managed services"
    )
    AvoidWhen = @(
        "You want a ready-made public web stack",
        "You need cluster add-ons such as metrics or ingress automation from the start"
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
        "200_persistent-volume",
        "201_persistent-volume-claim"
    )
    ServiceDirectories = @()
}
