@{
    Values = @(
        @{
            Name = "SHARED_STORAGE_NFS_SERVER"
            Category = "shared-storage"
            Sensitive = $false
            Description = "Hostname or IP address of the NFS server that backs the shared storage persistent volume."
        }
        @{
            Name = "SHARED_STORAGE_NFS_PATH"
            Category = "shared-storage"
            Sensitive = $false
            Description = "Exported path on the NFS server used for the shared storage persistent volume."
        }
        @{
            Name = "PLATFORM_STORAGE_CLASS"
            Category = "shared-storage"
            Sensitive = $false
            Description = "Default storage class used by optional Helm-managed platform components that request persistent volumes."
        }
        @{
            Name = "REDIS_PASSWORD"
            Category = "shared-platform"
            Sensitive = $true
            Description = "Password rendered into the Redis Kubernetes secret."
        }
        @{
            Name = "EXTERNAL_DNS_PROVIDER"
            Category = "shared-platform"
            Sensitive = $false
            Description = "Provider name passed to the ExternalDNS chart."
        }
        @{
            Name = "EXTERNAL_DNS_OWNER_ID"
            Category = "shared-platform"
            Sensitive = $false
            Description = "TXT owner identifier used by ExternalDNS to avoid record conflicts."
        }
        @{
            Name = "BASE_DOMAIN"
            Category = "shared-platform"
            Sensitive = $false
            Description = "Base domain filtered by ExternalDNS."
        }
        @{
            Name = "NGINX_WEB_MESSAGE"
            Category = "applications"
            Sensitive = $false
            Description = "Welcome message rendered into the nginx-web example page."
        }
        @{
            Name = "NGINX_WEB_HOST"
            Category = "edge"
            Sensitive = $false
            Description = "Hostname routed to the nginx-web example through the Gateway API route."
        }
        @{
            Name = "HTTPBIN_HOST"
            Category = "edge"
            Sensitive = $false
            Description = "Hostname routed to the httpbin example through the Gateway API route."
        }
        @{
            Name = "WHOAMI_HOST"
            Category = "edge"
            Sensitive = $false
            Description = "Hostname routed to the whoami example through the Gateway API route."
        }
        @{
            Name = "ADMINER_DEFAULT_SERVER"
            Category = "applications"
            Sensitive = $false
            Description = "Database host pre-filled by the Adminer deployment."
        }
        @{
            Name = "HARBOR_HOST"
            Category = "registry"
            Sensitive = $false
            Description = "Ingress hostname used by Harbor."
        }
        @{
            Name = "HARBOR_EXTERNAL_URL"
            Category = "registry"
            Sensitive = $false
            Description = "Public external URL advertised by Harbor."
        }
        @{
            Name = "HARBOR_ADMIN_PASSWORD"
            Category = "registry"
            Sensitive = $true
            Description = "Admin password configured for the Harbor chart."
        }
        @{
            Name = "HARBOR_SECRET_KEY"
            Category = "registry"
            Sensitive = $true
            Description = "Secret key used by Harbor for internal signing and encryption flows."
        }
        @{
            Name = "HARBOR_TLS_SECRET"
            Category = "registry"
            Sensitive = $false
            Description = "Kubernetes TLS secret name referenced by the Harbor ingress."
        }
        @{
            Name = "LONGHORN_HOST"
            Category = "storage-platform"
            Sensitive = $false
            Description = "Ingress hostname used by the Longhorn UI."
        }
        @{
            Name = "LONGHORN_TLS_SECRET"
            Category = "storage-platform"
            Sensitive = $false
            Description = "Kubernetes TLS secret name referenced by the Longhorn ingress."
        }
        @{
            Name = "LONGHORN_BASIC_AUTH_SECRET"
            Category = "storage-platform"
            Sensitive = $false
            Description = "Kubernetes secret resource name that stores the Longhorn ingress basic-auth credentials."
        }
        @{
            Name = "DASHBOARD_HOST"
            Category = "cluster-admin"
            Sensitive = $false
            Description = "Ingress hostname used by the Kubernetes Dashboard chart."
        }
        @{
            Name = "DASHBOARD_TLS_SECRET"
            Category = "cluster-admin"
            Sensitive = $false
            Description = "Kubernetes TLS secret name referenced by the Kubernetes Dashboard ingress."
        }
    )
}
