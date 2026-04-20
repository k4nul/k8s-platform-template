Set-StrictMode -Version Latest

function Get-PlatformProfileDefinitions {
    param(
        [string]$ProfileDirectory = (Join-Path $PSScriptRoot "..\config\profiles")
    )

    $resolvedDirectory = (Resolve-Path -Path $ProfileDirectory).Path
    $profiles = [ordered]@{}

    Get-ChildItem -Path $resolvedDirectory -Filter *.psd1 -File | Sort-Object BaseName | ForEach-Object {
        $profileName = $_.BaseName
        $profiles[$profileName] = Import-PowerShellDataFile -Path $_.FullName
    }

    return $profiles
}

function Get-PlatformApplicationCatalog {
    return [ordered]@{
        "adminer" = @{
            K8sDirectory = "401_platform_adminer"
            ServiceDirectory = "adminer"
        }
        "httpbin" = @{
            K8sDirectory = "400_platform_httpbin"
            ServiceDirectory = "httpbin"
        }
        "nginx-web" = @{
            K8sDirectory = "400_platform_nginx-web"
            ServiceDirectory = "nginx-web"
        }
        "whoami" = @{
            K8sDirectory = "400_platform_whoami"
            ServiceDirectory = "whoami"
        }
    }
}

function Get-PlatformDataServiceCatalog {
    return [ordered]@{
        "memcached" = "303_platform_memcached"
        "mysql" = "301_platform_mysql"
        "postgresql" = "301_platform_postgresql"
        "redis" = "302_platform_redis"
    }
}

function Get-PlatformK8sComponentCatalog {
    return [ordered]@{
        "100_metallb" = @{
            Delivery = "raw"
            PhaseId = "phase-a"
            PhaseName = "Phase A: Base Infrastructure"
            Description = "LoadBalancer support for bare-metal or local clusters."
            Notes = "Apply before workloads that expose LoadBalancer services."
        }
        "100_namespace" = @{
            Delivery = "raw"
            PhaseId = "phase-a"
            PhaseName = "Phase A: Base Infrastructure"
            Description = "Shared namespaces used by the platform workloads."
            Notes = ""
        }
        "200_persistent-volume" = @{
            Delivery = "raw"
            PhaseId = "phase-a"
            PhaseName = "Phase A: Base Infrastructure"
            Description = "Static storage definitions such as NFS-backed persistent volumes."
            Notes = ""
        }
        "201_persistent-volume-claim" = @{
            Delivery = "raw"
            PhaseId = "phase-a"
            PhaseName = "Phase A: Base Infrastructure"
            Description = "Persistent volume claims for shared and database storage."
            Notes = ""
        }
        "300_jenkins" = @{
            Delivery = "raw"
            PhaseId = "phase-c"
            PhaseName = "Phase C: Shared Services"
            Description = "Jenkins deployment and service resources."
            Notes = ""
        }
        "301_platform_mysql" = @{
            Delivery = "raw"
            PhaseId = "phase-c"
            PhaseName = "Phase C: Shared Services"
            Description = "MySQL service for relational application workloads."
            Notes = ""
        }
        "301_platform_postgresql" = @{
            Delivery = "raw"
            PhaseId = "phase-c"
            PhaseName = "Phase C: Shared Services"
            Description = "PostgreSQL service for relational application workloads."
            Notes = ""
        }
        "302_platform_redis" = @{
            Delivery = "raw"
            PhaseId = "phase-c"
            PhaseName = "Phase C: Shared Services"
            Description = "Redis cache and session store with a rendered secret."
            Notes = ""
        }
        "303_platform_memcached" = @{
            Delivery = "raw"
            PhaseId = "phase-c"
            PhaseName = "Phase C: Shared Services"
            Description = "Memcached service for lightweight in-memory caching."
            Notes = ""
        }
        "304_platform_nginx" = @{
            Delivery = "raw"
            PhaseId = "phase-c"
            PhaseName = "Phase C: Shared Services"
            Description = "Generic reverse proxy and edge service template."
            Notes = ""
        }
        "305_platform_metrics-server" = @{
            Delivery = "raw"
            PhaseId = "phase-b"
            PhaseName = "Phase B: Cluster Add-ons"
            Description = "Metrics API add-on for autoscaling and kubectl top."
            Notes = ""
        }
        "306_platform_external-dns" = @{
            Delivery = "helm"
            PhaseId = "phase-b"
            PhaseName = "Phase B: Cluster Add-ons"
            Description = "ExternalDNS chart values for DNS record automation."
            Notes = ""
        }
        "307_platform_harbor" = @{
            Delivery = "helm"
            PhaseId = "phase-b"
            PhaseName = "Phase B: Cluster Add-ons"
            Description = "Harbor chart values for an internal artifact registry."
            Notes = ""
        }
        "308_platform_gateway-api" = @{
            Delivery = "deferred-raw"
            PhaseId = "phase-e"
            PhaseName = "Phase E: Deferred Post-controller Resources"
            Description = "Gateway and HTTPRoute example resources."
            Notes = "Apply after Gateway API CRDs and your selected controller are ready."
        }
        "309_platform_nginx-gateway-fabric" = @{
            Delivery = "helm"
            PhaseId = "phase-b"
            PhaseName = "Phase B: Cluster Add-ons"
            Description = "NGINX Gateway Fabric chart values."
            Notes = ""
        }
        "310_platform_longhorn" = @{
            Delivery = "helm"
            PhaseId = "phase-b"
            PhaseName = "Phase B: Cluster Add-ons"
            Description = "Longhorn chart values for distributed block storage."
            Notes = "Confirm node prerequisites such as open-iscsi before installation."
        }
        "311_platform_kubernetes-dashboard" = @{
            Delivery = "helm"
            PhaseId = "phase-b"
            PhaseName = "Phase B: Cluster Add-ons"
            Description = "Kubernetes Dashboard chart values."
            Notes = "Optional sample admin manifest remains manual."
        }
        "312_platform_vertical-pod-autoscaler" = @{
            Delivery = "helm"
            PhaseId = "phase-b"
            PhaseName = "Phase B: Cluster Add-ons"
            Description = "Vertical Pod Autoscaler chart values."
            Notes = "Optional example VPA manifest remains manual."
        }
        "400_platform_httpbin" = @{
            Delivery = "raw"
            PhaseId = "phase-d"
            PhaseName = "Phase D: Applications"
            Description = "HTTPBin-compatible deployment and service."
            Notes = ""
        }
        "400_platform_nginx-web" = @{
            Delivery = "raw"
            PhaseId = "phase-d"
            PhaseName = "Phase D: Applications"
            Description = "NGINX static web deployment, service, and editable landing page."
            Notes = ""
        }
        "400_platform_whoami" = @{
            Delivery = "raw"
            PhaseId = "phase-d"
            PhaseName = "Phase D: Applications"
            Description = "Traefik whoami deployment and service."
            Notes = ""
        }
        "401_platform_adminer" = @{
            Delivery = "raw"
            PhaseId = "phase-d"
            PhaseName = "Phase D: Applications"
            Description = "Adminer deployment and service for MySQL or PostgreSQL access."
            Notes = ""
        }
    }
}

function Get-PlatformOptionalManifestCatalog {
    return [ordered]@{
        "311_platform_kubernetes-dashboard\sample-admin-user.yaml" = "Optional high-privilege dashboard access manifest. Use only for controlled testing."
        "312_platform_vertical-pod-autoscaler\example-nginx-web-vpa.yaml" = "Optional example VPA object. Apply only after the VPA components are installed."
    }
}

function Expand-PlatformSelectionValues {
    param(
        [string[]]$Values
    )

    $expandedValues = New-Object System.Collections.Generic.List[string]

    foreach ($value in @($Values)) {
        if (-not $value) {
            continue
        }

        foreach ($item in ($value -split ",")) {
            $trimmedItem = $item.Trim()
            if ($trimmedItem) {
                $expandedValues.Add($trimmedItem) | Out-Null
            }
        }
    }

    return @($expandedValues | Sort-Object -Unique)
}

function Resolve-PlatformSelection {
    param(
        [string]$Profile = "full",
        [string[]]$Applications = @(),
        [string[]]$DataServices = @(),
        [switch]$IncludeJenkins
    )

    $profiles = Get-PlatformProfileDefinitions
    if (-not $profiles.Contains($Profile)) {
        throw "Unknown profile '$Profile'. Available profiles: $($profiles.Keys -join ', ')"
    }

    $applicationCatalog = Get-PlatformApplicationCatalog
    $dataServiceCatalog = Get-PlatformDataServiceCatalog
    $profileDefinition = $profiles[$Profile]
    $normalizedApplications = Expand-PlatformSelectionValues -Values $Applications
    $normalizedDataServices = Expand-PlatformSelectionValues -Values $DataServices

    $k8sDirectories = New-Object System.Collections.Generic.List[string]
    $serviceDirectories = New-Object System.Collections.Generic.List[string]

    foreach ($directory in @($profileDefinition.K8sDirectories)) {
        if ($directory) {
            $k8sDirectories.Add($directory) | Out-Null
        }
    }

    foreach ($directory in @($profileDefinition.ServiceDirectories)) {
        if ($directory) {
            $serviceDirectories.Add($directory) | Out-Null
        }
    }

    foreach ($serviceName in $normalizedDataServices) {
        if (-not $dataServiceCatalog.Contains($serviceName)) {
            throw "Unknown data service '$serviceName'. Available data services: $($dataServiceCatalog.Keys -join ', ')"
        }

        $k8sDirectories.Add($dataServiceCatalog[$serviceName]) | Out-Null
    }

    foreach ($applicationName in $normalizedApplications) {
        if (-not $applicationCatalog.Contains($applicationName)) {
            throw "Unknown application '$applicationName'. Available applications: $($applicationCatalog.Keys -join ', ')"
        }

        $applicationDefinition = $applicationCatalog[$applicationName]
        if ($applicationDefinition.K8sDirectory) {
            $k8sDirectories.Add($applicationDefinition.K8sDirectory) | Out-Null
        }

        if ($applicationDefinition.ServiceDirectory) {
            $serviceDirectories.Add($applicationDefinition.ServiceDirectory) | Out-Null
        }
    }

    if ($IncludeJenkins) {
        $k8sDirectories.Add("300_jenkins") | Out-Null
    }

    return [PSCustomObject]@{
        Profile = $Profile
        Description = $profileDefinition.Description
        Applications = @($normalizedApplications)
        DataServices = @($normalizedDataServices)
        IncludeAllK8s = [bool]$profileDefinition.IncludeAllK8s
        IncludeAllServices = [bool]$profileDefinition.IncludeAllServices
        K8sDirectories = @($k8sDirectories | Sort-Object -Unique)
        ServiceDirectories = @($serviceDirectories | Sort-Object -Unique)
        AvailableProfiles = @($profiles.Keys)
        AvailableApplications = @($applicationCatalog.Keys)
        AvailableDataServices = @($dataServiceCatalog.Keys)
    }
}
