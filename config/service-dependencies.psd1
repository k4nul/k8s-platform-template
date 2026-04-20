@{
    Services = @(
        @{
            Name = "adminer"
            RequiredK8sDirectories = @()
            RecommendedK8sDirectories = @()
            CompatibleDataServices = @(
                "mysql",
                "postgresql"
            )
            RelatedApplications = @()
            Notes = "Database administration UI that is most useful when MySQL or PostgreSQL is part of the selected bundle or available externally."
        }
        @{
            Name = "httpbin"
            RequiredK8sDirectories = @()
            RecommendedK8sDirectories = @(
                "308_platform_gateway-api",
                "309_platform_nginx-gateway-fabric"
            )
            CompatibleDataServices = @()
            RelatedApplications = @(
                "nginx-web",
                "whoami"
            )
            Notes = "Stateless HTTP test endpoint that pairs well with ingress, gateway, and reverse-proxy validation flows."
        }
        @{
            Name = "nginx-web"
            RequiredK8sDirectories = @()
            RecommendedK8sDirectories = @(
                "308_platform_gateway-api",
                "309_platform_nginx-gateway-fabric"
            )
            CompatibleDataServices = @()
            RelatedApplications = @(
                "httpbin",
                "whoami"
            )
            Notes = "Static web example that benefits from gateway routing and DNS automation when exposed beyond internal cluster access."
        }
        @{
            Name = "whoami"
            RequiredK8sDirectories = @()
            RecommendedK8sDirectories = @(
                "308_platform_gateway-api",
                "309_platform_nginx-gateway-fabric"
            )
            CompatibleDataServices = @()
            RelatedApplications = @(
                "nginx-web",
                "httpbin"
            )
            Notes = "Lightweight request inspector that is useful for connectivity, load balancer, and reverse-proxy validation."
        }
    )
}
