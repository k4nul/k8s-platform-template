@{
    Releases = @(
        @{
            Name = "external-dns"
            K8sDirectory = "306_platform_external-dns"
            Enabled = $true
            Namespace = "platform"
            Chart = "external-dns/external-dns"
            RepoName = "external-dns"
            RepoUrl = "https://kubernetes-sigs.github.io/external-dns/"
            ValuesRelativePath = "k8s\306_platform_external-dns\values.yaml"
        },
        @{
            Name = "harbor"
            K8sDirectory = "307_platform_harbor"
            Enabled = $true
            Namespace = "platform"
            Chart = "harbor/harbor"
            RepoName = "harbor"
            RepoUrl = "https://helm.goharbor.io"
            ValuesRelativePath = "k8s\307_platform_harbor\values.yaml"
        },
        @{
            Name = "ngf"
            K8sDirectory = "309_platform_nginx-gateway-fabric"
            Enabled = $true
            Namespace = "nginx-gateway"
            Chart = "oci://ghcr.io/nginx/charts/nginx-gateway-fabric"
            RepoName = ""
            RepoUrl = ""
            ValuesRelativePath = "k8s\309_platform_nginx-gateway-fabric\values.yaml"
        },
        @{
            Name = "longhorn"
            K8sDirectory = "310_platform_longhorn"
            Enabled = $true
            Namespace = "longhorn-system"
            Chart = "longhorn/longhorn"
            RepoName = "longhorn"
            RepoUrl = "https://charts.longhorn.io"
            ValuesRelativePath = "k8s\310_platform_longhorn\values.yaml"
        },
        @{
            Name = "kubernetes-dashboard"
            K8sDirectory = "311_platform_kubernetes-dashboard"
            Enabled = $true
            Namespace = "kubernetes-dashboard"
            Chart = "kubernetes-dashboard/kubernetes-dashboard"
            RepoName = "kubernetes-dashboard"
            RepoUrl = "https://kubernetes.github.io/dashboard/"
            ValuesRelativePath = "k8s\311_platform_kubernetes-dashboard\values.yaml"
        },
        @{
            Name = "vertical-pod-autoscaler"
            K8sDirectory = "312_platform_vertical-pod-autoscaler"
            Enabled = $false
            Namespace = "kube-system"
            Chart = ""
            RepoName = ""
            RepoUrl = ""
            ValuesRelativePath = "k8s\312_platform_vertical-pod-autoscaler\values.yaml"
            Notes = "Fill in the supported VPA chart reference for your environment before enabling Helm validation."
        }
    )
}
