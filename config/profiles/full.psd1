@{
    Description = "Render the full repository, including every Kubernetes manifest and every service template."
    PrimaryUse = "Repository-wide audit, validation, and exploratory rendering mode that intentionally includes everything."
    RecommendedFor = @(
        "Repository maintenance and template audits",
        "Exploratory reviews when you want to inspect every component together",
        "Validation flows that should touch the broadest possible repository surface"
    )
    AvoidWhen = @(
        "You are preparing a real environment-specific bundle",
        "You want the smallest values set and least-privilege component selection"
    )
    ExampleApplications = @()
    ExampleDataServices = @()
    IncludeAllK8s = $true
    IncludeAllServices = $true
    K8sDirectories = @()
    ServiceDirectories = @()
}
