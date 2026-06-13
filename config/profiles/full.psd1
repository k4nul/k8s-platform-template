@{
    Description = "Render every standard Kubernetes component directory and service template while keeping optional follow-up manifests manual."
    PrimaryUse = "Repository-wide audit, validation, and exploratory rendering mode for standard bundle contents."
    RecommendedFor = @(
        "Repository maintenance and template audits",
        "Exploratory reviews when you want to inspect every standard component together",
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
