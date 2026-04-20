param(
    [string]$RepoRoot,
    [string]$HelmConfigFile,
    [string]$ValuesFile,
    [string]$Profile = "full",
    [string[]]$Applications = @(),
    [string[]]$DataServices = @(),
    [switch]$IncludeJenkins,
    [ValidateSet("text", "markdown", "json")]
    [string]$Format = "text",
    [string]$OutputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "platform-values-catalog.ps1")

function Normalize-YamlScalarValue {
    param(
        [string]$Value
    )

    if (-not $Value) {
        return ""
    }

    $normalized = ($Value -replace '\s+#.*$', '').Trim()
    if ($normalized -match '^&[A-Za-z0-9_-]+\s+(.+)$') {
        $normalized = $Matches[1].Trim()
    }

    if ($normalized -match '^\*[A-Za-z0-9_-]+$') {
        return ""
    }

    if (
        ($normalized.StartsWith('"') -and $normalized.EndsWith('"')) -or
        ($normalized.StartsWith("'") -and $normalized.EndsWith("'"))
    ) {
        $normalized = $normalized.Substring(1, $normalized.Length - 2)
    }

    return $normalized.Trim()
}

function Test-MeaningfulScalarValue {
    param(
        [string]$Value
    )

    if (-not $Value) {
        return $false
    }

    return $Value -notin @("null", "~", "''", '""')
}

function Get-TextList {
    param(
        [object[]]$Values,
        [string]$Empty = "none"
    )

    $items = @($Values | Where-Object { $_ } | Sort-Object -Unique)
    if ($items.Count -gt 0) {
        return ($items -join ", ")
    }

    return $Empty
}

function Get-YamlDocumentBlocks {
    param(
        [string]$Content
    )

    $normalized = $Content -replace "`r`n?", "`n"
    return @(
        $normalized -split "(?m)^---\s*$" |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ }
    )
}

function Get-YamlDocumentMetadata {
    param(
        [string]$Document
    )

    $apiVersion = ""
    $kind = ""
    $name = ""
    $namespace = ""

    $apiVersionMatch = [regex]::Match($Document, '(?m)^apiVersion:\s*(.+)$')
    if ($apiVersionMatch.Success) {
        $apiVersion = Normalize-YamlScalarValue -Value $apiVersionMatch.Groups[1].Value
    }

    $kindMatch = [regex]::Match($Document, '(?m)^kind:\s*(.+)$')
    if ($kindMatch.Success) {
        $kind = Normalize-YamlScalarValue -Value $kindMatch.Groups[1].Value
    }

    $metadataMatch = [regex]::Match($Document, '(?ms)^metadata:\s*\r?\n(?<body>(?:[ \t].*(?:\r?\n|$))*)')
    if ($metadataMatch.Success) {
        $metadataBody = $metadataMatch.Groups["body"].Value

        $nameMatch = [regex]::Match($metadataBody, '(?m)^\s*name:\s*(.+)$')
        if ($nameMatch.Success) {
            $name = Normalize-YamlScalarValue -Value $nameMatch.Groups[1].Value
        }

        $namespaceMatch = [regex]::Match($metadataBody, '(?m)^\s*namespace:\s*(.+)$')
        if ($namespaceMatch.Success) {
            $namespace = Normalize-YamlScalarValue -Value $namespaceMatch.Groups[1].Value
        }
    }

    return [PSCustomObject]@{
        ApiVersion = $apiVersion
        Kind = $kind
        Name = $name
        Namespace = $namespace
    }
}

function Get-NamespaceReferencesFromContent {
    param(
        [string]$Content
    )

    return @(
        [regex]::Matches($Content, '(?m)^\s*namespace:\s*(.+)$') |
            ForEach-Object { Normalize-YamlScalarValue -Value $_.Groups[1].Value } |
            Where-Object { Test-MeaningfulScalarValue -Value $_ } |
            Sort-Object -Unique
    )
}

function Get-StorageClassReferencesFromContent {
    param(
        [string]$Content,
        [string]$Directory,
        [string]$RelativePath
    )

    $entries = New-Object System.Collections.Generic.List[object]
    $patterns = @(
        '(?m)^\s*storageClassName:\s*(.+)$',
        '(?m)^\s*storageClass:\s*(.+)$'
    )

    foreach ($pattern in $patterns) {
        foreach ($match in [regex]::Matches($Content, $pattern)) {
            $name = Normalize-YamlScalarValue -Value $match.Groups[1].Value
            if (-not (Test-MeaningfulScalarValue -Value $name)) {
                continue
            }

            $entries.Add([PSCustomObject]@{
                Name = $name
                Directory = $Directory
                SourcePath = $RelativePath
            }) | Out-Null
        }
    }

    return $entries.ToArray()
}

function Get-DocumentSecretReferenceEntries {
    param(
        [string]$Document,
        [string]$Directory,
        [string]$RelativePath,
        [string]$DefaultNamespace
    )

    $entries = New-Object System.Collections.Generic.List[object]
    $lines = $Document -split "`r?`n"
    $context = ""
    $contextIndent = -1

    foreach ($line in $lines) {
        $trimmed = $line.Trim()
        $indent = ([regex]::Match($line, '^\s*')).Value.Length

        if ($context -eq "imagePullSecrets") {
            if ($indent -lt $contextIndent -or ($indent -eq $contextIndent -and $trimmed -notmatch '^-+\s*name\s*:')) {
                $context = ""
                $contextIndent = -1
            }
        }
        elseif ($context -and $indent -le $contextIndent) {
            $context = ""
            $contextIndent = -1
        }

        if (-not $trimmed) {
            continue
        }

        if ($line -match '^\s*(?:[A-Za-z0-9\.\-]+/)?auth-secret:\s*(.+)$') {
            $name = Normalize-YamlScalarValue -Value $Matches[1]
            if (Test-MeaningfulScalarValue -Value $name) {
                $entries.Add([PSCustomObject]@{
                    Name = $name
                    Namespace = $DefaultNamespace
                    Directory = $Directory
                    SourcePath = $RelativePath
                    Description = "Referenced by manifest annotations or ingress settings."
                    ValueKey = ""
                    Key = ("{0}|{1}" -f $DefaultNamespace, $name)
                }) | Out-Null
            }
            continue
        }

        if ($line -match '^\s*(secretName|existingSecret|existingSecretName):\s*(.+)$') {
            $name = Normalize-YamlScalarValue -Value $Matches[2]
            if (Test-MeaningfulScalarValue -Value $name) {
                $entries.Add([PSCustomObject]@{
                    Name = $name
                    Namespace = $DefaultNamespace
                    Directory = $Directory
                    SourcePath = $RelativePath
                    Description = "Referenced directly by the rendered manifest."
                    ValueKey = ""
                    Key = ("{0}|{1}" -f $DefaultNamespace, $name)
                }) | Out-Null
            }
            continue
        }

        if ($line -match '^\s*(imagePullSecrets|secretKeyRef|secretRef)\s*:\s*$') {
            $context = $Matches[1]
            $contextIndent = $indent
            continue
        }

        if ($context -eq "imagePullSecrets" -and $line -match '^\s*-\s*name:\s*(.+)$') {
            $name = Normalize-YamlScalarValue -Value $Matches[1]
            if (Test-MeaningfulScalarValue -Value $name) {
                $entries.Add([PSCustomObject]@{
                    Name = $name
                    Namespace = $DefaultNamespace
                    Directory = $Directory
                    SourcePath = $RelativePath
                    Description = "Referenced by the rendered manifest."
                    ValueKey = ""
                    Key = ("{0}|{1}" -f $DefaultNamespace, $name)
                }) | Out-Null
            }
            continue
        }

        if (($context -eq "secretKeyRef" -or $context -eq "secretRef") -and $indent -gt $contextIndent -and $line -match '^\s*name:\s*(.+)$') {
            $name = Normalize-YamlScalarValue -Value $Matches[1]
            if (Test-MeaningfulScalarValue -Value $name) {
                $entries.Add([PSCustomObject]@{
                    Name = $name
                    Namespace = $DefaultNamespace
                    Directory = $Directory
                    SourcePath = $RelativePath
                    Description = "Referenced by the rendered manifest."
                    ValueKey = ""
                    Key = ("{0}|{1}" -f $DefaultNamespace, $name)
                }) | Out-Null
            }
        }
    }

    return $entries.ToArray()
}

function Get-BuiltInApiGroups {
    return @(
        "admissionregistration.k8s.io",
        "apiextensions.k8s.io",
        "apiregistration.k8s.io",
        "apps",
        "autoscaling",
        "batch",
        "certificates.k8s.io",
        "coordination.k8s.io",
        "discovery.k8s.io",
        "events.k8s.io",
        "extensions",
        "networking.k8s.io",
        "node.k8s.io",
        "policy",
        "rbac.authorization.k8s.io",
        "scheduling.k8s.io",
        "storage.k8s.io"
    )
}

function Get-CrdNameForKind {
    param(
        [string]$Kind,
        [string]$ApiGroup
    )

    switch ($Kind.ToLowerInvariant()) {
        "gateway" { return "gateways.$ApiGroup" }
        "gatewayclass" { return "gatewayclasses.$ApiGroup" }
        "httproute" { return "httproutes.$ApiGroup" }
        "ipaddresspool" { return "ipaddresspools.$ApiGroup" }
        "l2advertisement" { return "l2advertisements.$ApiGroup" }
        "verticalpodautoscaler" { return "verticalpodautoscalers.$ApiGroup" }
        default { return ("{0}s.{1}" -f $Kind.ToLowerInvariant(), $ApiGroup) }
    }
}

function Get-CustomApiRequirementEntriesFromDocument {
    param(
        [string]$Document,
        [string]$Directory,
        [string]$RelativePath
    )

    $metadata = Get-YamlDocumentMetadata -Document $Document
    if (-not $metadata.ApiVersion -or -not $metadata.Kind) {
        return @()
    }

    if ($metadata.ApiVersion -notmatch '^([^/]+)/') {
        return @()
    }

    $apiGroup = $Matches[1]
    if ((Get-BuiltInApiGroups) -contains $apiGroup) {
        return @()
    }

    $crdName = Get-CrdNameForKind -Kind $metadata.Kind -ApiGroup $apiGroup
    return @(
        [PSCustomObject]@{
            ApiGroup = $apiGroup
            Kind = $metadata.Kind
            CrdName = $crdName
            Directory = $Directory
            SourcePath = $RelativePath
            Key = $crdName
        }
    )
}

function Invoke-ExternalCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Command,

        [string[]]$Arguments = @()
    )

    $output = & $Command @Arguments 2>&1 | Out-String
    return [PSCustomObject]@{
        Success = ($LASTEXITCODE -eq 0)
        Output = $output.Trim()
    }
}

function Get-PlatformClusterPreflightCatalog {
    return [ordered]@{
        "306_platform_external-dns" = @{
            ExternalSecrets = @()
            ManualChecks = @(
                "Confirm ExternalDNS provider credentials and DNS zone permissions outside this repository before install."
            )
        }
        "307_platform_harbor" = @{
            ExternalSecrets = @(
                @{
                    Namespace = "platform"
                    ValueKey = "HARBOR_TLS_SECRET"
                    Description = "TLS secret referenced by the Harbor ingress."
                }
            )
            ManualChecks = @(
                "Confirm the selected storage class can provision Harbor PVCs for registry, database, Redis, jobservice, and Trivy."
            )
        }
        "308_platform_gateway-api" = @{
            ExternalSecrets = @()
            ManualChecks = @(
                "Apply the deferred Gateway API example manifests only after the required CRDs and controller are ready."
            )
        }
        "309_platform_nginx-gateway-fabric" = @{
            ExternalSecrets = @()
            ManualChecks = @(
                "Review the gateway exposure model and service type for the selected Gateway controller before install."
            )
        }
        "310_platform_longhorn" = @{
            ExternalSecrets = @(
                @{
                    Namespace = "longhorn-system"
                    ValueKey = "LONGHORN_TLS_SECRET"
                    Description = "TLS secret referenced by the Longhorn ingress."
                }
                @{
                    Namespace = "longhorn-system"
                    ValueKey = "LONGHORN_BASIC_AUTH_SECRET"
                    Description = "Basic-auth secret referenced by the Longhorn ingress annotations."
                }
            )
            ManualChecks = @(
                "Confirm Longhorn node prerequisites such as open-iscsi, iscsid, and the intended disk layout before installation."
            )
        }
        "311_platform_kubernetes-dashboard" = @{
            ExternalSecrets = @(
                @{
                    Namespace = "kubernetes-dashboard"
                    ValueKey = "DASHBOARD_TLS_SECRET"
                    Description = "TLS secret referenced by the Dashboard ingress."
                }
            )
            ManualChecks = @(
                "Keep the sample cluster-admin dashboard user disabled outside controlled testing."
            )
        }
        "312_platform_vertical-pod-autoscaler" = @{
            ExternalSecrets = @()
            ManualChecks = @(
                "Fill in a supported VPA chart reference before enabling Helm validation or Helm installation for this component."
            )
        }
    }
}

function Get-SelectedHelmReleaseEntries {
    param(
        [object[]]$Releases,
        [string[]]$SelectedK8sDirectories
    )

    return @(
        $Releases | Where-Object {
            $_.Enabled -and $_.ValuesRelativePath -and $_.Chart -and $_.K8sDirectory -in $SelectedK8sDirectories
        } | Sort-Object Name
    )
}

function Get-SkippedHelmReleaseEntries {
    param(
        [object[]]$Releases,
        [string[]]$SelectedK8sDirectories
    )

    return @(
        $Releases | Where-Object {
            $_.K8sDirectory -in $SelectedK8sDirectories -and (
                -not $_.Enabled -or -not $_.Chart
            )
        } | Sort-Object Name
    )
}

function Get-PreflightCommandLine {
    param(
        [string]$ValuesFile,
        [string]$Profile,
        [string[]]$Applications,
        [string[]]$DataServices,
        [bool]$IncludeJenkins,
        [string]$Format
    )

    $parts = New-Object System.Collections.Generic.List[string]
    $parts.Add(".\scripts\show-cluster-preflight.ps1") | Out-Null
    $parts.Add("-ValuesFile") | Out-Null
    $parts.Add($ValuesFile) | Out-Null
    $parts.Add("-Profile") | Out-Null
    $parts.Add($Profile) | Out-Null

    if (@($Applications).Count -gt 0) {
        $parts.Add("-Applications") | Out-Null
        $parts.Add(($Applications -join ",")) | Out-Null
    }

    if (@($DataServices).Count -gt 0) {
        $parts.Add("-DataServices") | Out-Null
        $parts.Add(($DataServices -join ",")) | Out-Null
    }

    if ($IncludeJenkins) {
        $parts.Add("-IncludeJenkins") | Out-Null
    }

    $parts.Add("-Format") | Out-Null
    $parts.Add($Format) | Out-Null

    return ($parts -join " ")
}

if (-not $PSBoundParameters.ContainsKey("RepoRoot") -or -not $RepoRoot) {
    $RepoRoot = Join-Path $PSScriptRoot ".."
}

if (-not $PSBoundParameters.ContainsKey("HelmConfigFile") -or -not $HelmConfigFile) {
    $HelmConfigFile = Join-Path $PSScriptRoot "..\config\helm-releases.psd1"
}

if (-not $PSBoundParameters.ContainsKey("ValuesFile") -or -not $ValuesFile) {
    $ValuesFile = Join-Path $PSScriptRoot "..\config\platform-values.env.example"
}

$root = (Resolve-Path -Path $RepoRoot).Path
$resolvedValuesFile = (Resolve-Path -Path $ValuesFile).Path
$resolvedHelmConfig = (Resolve-Path -Path $HelmConfigFile).Path
$planData = Get-PlatformValuePlanData `
    -RepoRoot $root `
    -Profile $Profile `
    -Applications $Applications `
    -DataServices $DataServices `
    -IncludeJenkins:$IncludeJenkins `
    -ValuesFile $resolvedValuesFile
$selection = $planData.Selection
$effectiveK8sDirectories = @($planData.K8sDirectories)
$effectiveServiceDirectories = @($planData.ServiceDirectories)
$envMap = Get-EnvFileEntryMap -Path $resolvedValuesFile
$replacementMap = Get-TemplateReplacementMap -ValuesFile $resolvedValuesFile
$helmConfig = Import-PowerShellDataFile -Path $resolvedHelmConfig
$helmReleases = Get-SelectedHelmReleaseEntries -Releases $helmConfig.Releases -SelectedK8sDirectories $effectiveK8sDirectories
$skippedHelmReleases = Get-SkippedHelmReleaseEntries -Releases $helmConfig.Releases -SelectedK8sDirectories $effectiveK8sDirectories
$preflightCatalog = Get-PlatformClusterPreflightCatalog

$namespaceObservations = New-Object System.Collections.Generic.List[object]
$createdNamespaceObservations = New-Object System.Collections.Generic.List[object]
$createdSecretObservations = New-Object System.Collections.Generic.List[object]
$secretRequirementObservations = New-Object System.Collections.Generic.List[object]
$storageClassObservations = New-Object System.Collections.Generic.List[object]
$crdObservations = New-Object System.Collections.Generic.List[object]
$manualChecks = New-Object System.Collections.Generic.List[string]

foreach ($directory in $effectiveK8sDirectories) {
    $directoryRoot = Join-Path $root ("k8s\{0}" -f $directory)
    if (-not (Test-Path -Path $directoryRoot -PathType Container)) {
        continue
    }

    foreach ($file in Get-ChildItem -Path $directoryRoot -Recurse -File | Where-Object {
        $_.Extension.ToLowerInvariant() -in @(".yaml", ".yml")
    }) {
        $relativePath = Get-RelativePathCompat -BasePath $root -TargetPath $file.FullName
        $content = Get-Content -Path $file.FullName -Raw
        $expandedContent = Expand-TemplateContent -Content $content -ReplacementMap $replacementMap

        foreach ($namespaceName in @(Get-NamespaceReferencesFromContent -Content $expandedContent)) {
            $namespaceObservations.Add([PSCustomObject]@{
                Namespace = $namespaceName
                Directory = $directory
                SourcePath = $relativePath
                Description = "Referenced by rendered manifests."
            }) | Out-Null
        }

        foreach ($storageEntry in @(Get-StorageClassReferencesFromContent -Content $expandedContent -Directory $directory -RelativePath $relativePath)) {
            $storageClassObservations.Add($storageEntry) | Out-Null
        }

        if ($file.Name -eq "values.yaml") {
            continue
        }

        foreach ($document in @(Get-YamlDocumentBlocks -Content $expandedContent)) {
            $metadata = Get-YamlDocumentMetadata -Document $document
            $defaultNamespace = if ($metadata.Namespace) { $metadata.Namespace } else { "default" }

            if ($metadata.Kind -eq "Namespace" -and (Test-MeaningfulScalarValue -Value $metadata.Name)) {
                $createdNamespaceObservations.Add([PSCustomObject]@{
                    Namespace = $metadata.Name
                    Directory = $directory
                    SourcePath = $relativePath
                }) | Out-Null

                $namespaceObservations.Add([PSCustomObject]@{
                    Namespace = $metadata.Name
                    Directory = $directory
                    SourcePath = $relativePath
                    Description = "Created by the bundle."
                }) | Out-Null
            }

            if ($metadata.Kind -eq "Secret" -and (Test-MeaningfulScalarValue -Value $metadata.Name)) {
                $createdSecretObservations.Add([PSCustomObject]@{
                    Namespace = $defaultNamespace
                    Name = $metadata.Name
                    Directory = $directory
                    SourcePath = $relativePath
                    Key = ("{0}|{1}" -f $defaultNamespace, $metadata.Name)
                }) | Out-Null
            }

            foreach ($secretEntry in @(Get-DocumentSecretReferenceEntries -Document $document -Directory $directory -RelativePath $relativePath -DefaultNamespace $defaultNamespace)) {
                $secretRequirementObservations.Add($secretEntry) | Out-Null
            }

            foreach ($crdEntry in @(Get-CustomApiRequirementEntriesFromDocument -Document $document -Directory $directory -RelativePath $relativePath)) {
                $crdObservations.Add($crdEntry) | Out-Null
            }
        }
    }

    if ($preflightCatalog.Contains($directory)) {
        foreach ($secretDefinition in @($preflightCatalog[$directory].ExternalSecrets)) {
            $secretName = if ($envMap.Contains($secretDefinition.ValueKey)) {
                $envMap[$secretDefinition.ValueKey]
            }
            else {
                "[missing:{0}]" -f $secretDefinition.ValueKey
            }

            $sourcePath = "k8s\{0}\values.yaml" -f $directory
            $secretRequirementObservations.Add([PSCustomObject]@{
                Name = $secretName
                Namespace = $secretDefinition.Namespace
                Directory = $directory
                SourcePath = $sourcePath
                Description = $secretDefinition.Description
                ValueKey = $secretDefinition.ValueKey
                Key = ("{0}|{1}" -f $secretDefinition.Namespace, $secretName)
            }) | Out-Null
        }

        foreach ($note in @($preflightCatalog[$directory].ManualChecks)) {
            if ($note) {
                $manualChecks.Add($note) | Out-Null
            }
        }
    }
}

foreach ($release in $helmReleases) {
    if ($release.Namespace) {
        $namespaceObservations.Add([PSCustomObject]@{
            Namespace = $release.Namespace
            Directory = $release.K8sDirectory
            SourcePath = $release.ValuesRelativePath
            Description = ("Helm release namespace for {0}" -f $release.Name)
        }) | Out-Null
    }
}

foreach ($release in $skippedHelmReleases) {
    $notes = if ($release.Notes) { $release.Notes } else { "Release is disabled or missing chart information." }
    $manualChecks.Add(("Helm release '{0}' is not fully configured yet. {1}" -f $release.Name, $notes)) | Out-Null
}

$kubectlCommand = Get-Command kubectl -ErrorAction SilentlyContinue
$helmCommand = Get-Command helm -ErrorAction SilentlyContinue

$clusterAccess = [ordered]@{
    KubectlInstalled = ($null -ne $kubectlCommand)
    HelmInstalled = ($null -ne $helmCommand)
    CurrentContext = ""
    ClusterReachable = $false
    ClusterMessage = ""
    HelmRepoQuerySucceeded = $false
    HelmRepoQueryMessage = ""
}

if ($clusterAccess.KubectlInstalled) {
    $contextResult = Invoke-ExternalCommand -Command "kubectl" -Arguments @("config", "current-context")
    if ($contextResult.Success) {
        $clusterAccess.CurrentContext = $contextResult.Output
    }

    $clusterProbe = Invoke-ExternalCommand -Command "kubectl" -Arguments @("get", "namespace", "default", "-o", "name")
    if ($clusterProbe.Success) {
        $clusterAccess.ClusterReachable = $true
        $clusterAccess.ClusterMessage = "Current context is reachable."
    }
    elseif ($clusterAccess.CurrentContext) {
        $clusterAccess.ClusterMessage = if ($clusterProbe.Output) {
            $clusterProbe.Output
        }
        else {
            "kubectl is installed, but the current context could not be reached."
        }
    }
    else {
        $clusterAccess.ClusterMessage = "kubectl is installed, but no active context could be resolved."
    }
}
else {
    $clusterAccess.ClusterMessage = "kubectl is not installed on this workstation."
}

$helmRepoItems = @()
if ($clusterAccess.HelmInstalled) {
    $helmRepoResult = Invoke-ExternalCommand -Command "helm" -Arguments @("repo", "list", "-o", "json")
    if ($helmRepoResult.Success) {
        $clusterAccess.HelmRepoQuerySucceeded = $true
        if ($helmRepoResult.Output) {
            $helmRepoItems = @($helmRepoResult.Output | ConvertFrom-Json)
        }
    }
    else {
        $clusterAccess.HelmRepoQueryMessage = if ($helmRepoResult.Output) {
            $helmRepoResult.Output
        }
        else {
            "Unable to query configured Helm repositories."
        }
    }
}
else {
    $clusterAccess.HelmRepoQueryMessage = "helm is not installed on this workstation."
}

$namespaceCache = @{}
$secretCache = @{}
$storageClassCache = @{}
$crdCache = @{}

function Test-ClusterNamespaceExists {
    param([string]$Name)

    if ($namespaceCache.ContainsKey($Name)) {
        return [bool]$namespaceCache[$Name]
    }

    $result = Invoke-ExternalCommand -Command "kubectl" -Arguments @("get", "namespace", $Name, "-o", "name")
    $exists = $result.Success
    $namespaceCache[$Name] = $exists
    return $exists
}

function Test-ClusterSecretExists {
    param(
        [string]$Namespace,
        [string]$Name
    )

    $key = "{0}|{1}" -f $Namespace, $Name
    if ($secretCache.ContainsKey($key)) {
        return [bool]$secretCache[$key]
    }

    $result = Invoke-ExternalCommand -Command "kubectl" -Arguments @("get", "secret", $Name, "-n", $Namespace, "-o", "name")
    $exists = $result.Success
    $secretCache[$key] = $exists
    return $exists
}

function Test-ClusterStorageClassExists {
    param([string]$Name)

    if ($storageClassCache.ContainsKey($Name)) {
        return [bool]$storageClassCache[$Name]
    }

    $result = Invoke-ExternalCommand -Command "kubectl" -Arguments @("get", "storageclass", $Name, "-o", "name")
    $exists = $result.Success
    $storageClassCache[$Name] = $exists
    return $exists
}

function Test-ClusterCrdExists {
    param([string]$Name)

    if ($crdCache.ContainsKey($Name)) {
        return [bool]$crdCache[$Name]
    }

    $result = Invoke-ExternalCommand -Command "kubectl" -Arguments @("get", "crd", $Name, "-o", "name")
    $exists = $result.Success
    $crdCache[$Name] = $exists
    return $exists
}

$systemNamespaces = @("default", "kube-system", "kube-public", "kube-node-lease")
$createdNamespaceMap = @{}
foreach ($item in $createdNamespaceObservations) {
    $createdNamespaceMap[$item.Namespace] = $true
}

$helmManagedNamespaceMap = @{}
foreach ($release in $helmReleases) {
    if ($release.Namespace) {
        $helmManagedNamespaceMap[$release.Namespace] = $true
    }
}

$namespaceEntries = @()
foreach ($group in @($namespaceObservations | Group-Object Namespace | Sort-Object Name)) {
    $items = @($group.Group)
    $namespaceName = $group.Name
    if (-not $namespaceName) {
        continue
    }

    $provisioning = if ($createdNamespaceMap.ContainsKey($namespaceName)) {
        "bundle-managed-raw"
    }
    elseif ($systemNamespaces -contains $namespaceName) {
        "pre-existing-system"
    }
    elseif ($helmManagedNamespaceMap.ContainsKey($namespaceName)) {
        "bundle-managed-helm"
    }
    else {
        "pre-existing"
    }

    $requiredBeforeDeploy = $provisioning -in @("pre-existing", "pre-existing-system")
    $clusterStatus = "unknown"
    if ($clusterAccess.ClusterReachable) {
        $exists = Test-ClusterNamespaceExists -Name $namespaceName
        if ($exists) {
            $clusterStatus = "present"
        }
        elseif ($requiredBeforeDeploy) {
            $clusterStatus = "missing"
        }
        else {
            $clusterStatus = "absent-but-bundle-managed"
        }
    }
    elseif (-not $requiredBeforeDeploy) {
        $clusterStatus = "bundle-managed"
    }

    $namespaceEntries += [PSCustomObject]@{
        Namespace = $namespaceName
        Provisioning = $provisioning
        RequiredBeforeDeploy = [bool]$requiredBeforeDeploy
        ClusterStatus = $clusterStatus
        Directories = @($items | Select-Object -ExpandProperty Directory | Sort-Object -Unique)
        SourcePaths = @($items | Select-Object -ExpandProperty SourcePath | Sort-Object -Unique)
        Descriptions = @($items | Select-Object -ExpandProperty Description | Where-Object { $_ } | Sort-Object -Unique)
    }
}

$createdSecretMap = @{}
foreach ($item in $createdSecretObservations) {
    $createdSecretMap[$item.Key] = $true
}

$secretEntries = @()
foreach ($group in @($secretRequirementObservations | Group-Object Key | Sort-Object Name)) {
    $items = @($group.Group)
    if ($items.Count -eq 0) {
        continue
    }

    $firstItem = $items[0]
    $isBundleManaged = $createdSecretMap.ContainsKey($group.Name)
    $clusterStatus = "unknown"
    if ($clusterAccess.ClusterReachable) {
        $exists = Test-ClusterSecretExists -Namespace $firstItem.Namespace -Name $firstItem.Name
        if ($exists) {
            $clusterStatus = "present"
        }
        elseif ($isBundleManaged) {
            $clusterStatus = "absent-but-bundle-managed"
        }
        else {
            $clusterStatus = "missing"
        }
    }
    elseif ($isBundleManaged) {
        $clusterStatus = "bundle-managed"
    }

    $secretEntries += [PSCustomObject]@{
        Namespace = $firstItem.Namespace
        Name = $firstItem.Name
        Provisioning = if ($isBundleManaged) { "bundle-managed" } else { "pre-existing" }
        RequiredBeforeDeploy = [bool](-not $isBundleManaged)
        ClusterStatus = $clusterStatus
        Directories = @($items | Select-Object -ExpandProperty Directory | Sort-Object -Unique)
        SourcePaths = @($items | Select-Object -ExpandProperty SourcePath | Sort-Object -Unique)
        Descriptions = @($items | Select-Object -ExpandProperty Description | Where-Object { $_ } | Sort-Object -Unique)
        ValueKeys = @($items | Select-Object -ExpandProperty ValueKey | Where-Object { $_ } | Sort-Object -Unique)
    }
}

$storageClassEntries = @()
foreach ($group in @($storageClassObservations | Group-Object Name | Sort-Object Name)) {
    $items = @($group.Group)
    $storageClassName = $group.Name
    if (-not $storageClassName) {
        continue
    }

    $clusterStatus = "unknown"
    if ($clusterAccess.ClusterReachable) {
        $clusterStatus = if (Test-ClusterStorageClassExists -Name $storageClassName) { "present" } else { "missing" }
    }

    $storageClassEntries += [PSCustomObject]@{
        Name = $storageClassName
        ClusterStatus = $clusterStatus
        Directories = @($items | Select-Object -ExpandProperty Directory | Sort-Object -Unique)
        SourcePaths = @($items | Select-Object -ExpandProperty SourcePath | Sort-Object -Unique)
    }
}

$crdEntries = @()
foreach ($group in @($crdObservations | Group-Object Key | Sort-Object Name)) {
    $items = @($group.Group)
    $firstItem = $items[0]
    $clusterStatus = "unknown"
    if ($clusterAccess.ClusterReachable) {
        $clusterStatus = if (Test-ClusterCrdExists -Name $firstItem.CrdName) { "present" } else { "missing" }
    }

    $crdEntries += [PSCustomObject]@{
        CrdName = $firstItem.CrdName
        ApiGroup = $firstItem.ApiGroup
        Kinds = @($items | Select-Object -ExpandProperty Kind | Sort-Object -Unique)
        ClusterStatus = $clusterStatus
        Directories = @($items | Select-Object -ExpandProperty Directory | Sort-Object -Unique)
        SourcePaths = @($items | Select-Object -ExpandProperty SourcePath | Sort-Object -Unique)
    }
}

$helmReleaseEntries = @()
foreach ($release in $helmReleases) {
    $sourceType = if ($release.Chart -like "oci://*") { "oci" } else { "repo" }
    $repoStatus = "unknown"
    if (-not $clusterAccess.HelmInstalled) {
        $repoStatus = "unknown"
    }
    elseif ($sourceType -eq "oci") {
        $repoStatus = "not-required"
    }
    elseif ($clusterAccess.HelmRepoQuerySucceeded) {
        $configuredRepo = @($helmRepoItems | Where-Object {
            $_.name -eq $release.RepoName -and $_.url -eq $release.RepoUrl
        })
        $repoStatus = if ($configuredRepo.Count -gt 0) { "configured" } else { "missing" }
    }

    $helmReleaseEntries += [PSCustomObject]@{
        Name = $release.Name
        Namespace = $release.Namespace
        Chart = $release.Chart
        SourceType = $sourceType
        RepoName = $release.RepoName
        RepoUrl = $release.RepoUrl
        RepoStatus = $repoStatus
        K8sDirectory = $release.K8sDirectory
        ValuesPath = $release.ValuesRelativePath
    }
}

$missingRequiredNamespaces = @($namespaceEntries | Where-Object { $_.RequiredBeforeDeploy -and $_.ClusterStatus -eq "missing" })
$missingRequiredSecrets = @($secretEntries | Where-Object { $_.RequiredBeforeDeploy -and $_.ClusterStatus -eq "missing" })
$missingStorageClasses = @($storageClassEntries | Where-Object { $_.ClusterStatus -eq "missing" })
$missingCrds = @($crdEntries | Where-Object { $_.ClusterStatus -eq "missing" })
$missingHelmRepos = @($helmReleaseEntries | Where-Object { $_.RepoStatus -eq "missing" })

$overallStatus = if (-not $clusterAccess.KubectlInstalled) {
    "repository-only-preflight"
}
elseif (-not $clusterAccess.ClusterReachable) {
    "cluster-unreachable"
}
elseif (
    @($missingRequiredNamespaces).Count -gt 0 -or
    @($missingRequiredSecrets).Count -gt 0 -or
    @($missingStorageClasses).Count -gt 0 -or
    @($missingCrds).Count -gt 0
) {
    "cluster-preflight-blocked"
}
else {
    "cluster-preflight-ready"
}

$manualCheckItems = @($manualChecks | Sort-Object -Unique)
$applicationsText = Get-TextList -Values $selection.Applications
$dataServicesText = Get-TextList -Values $selection.DataServices
$serviceDirectoriesText = Get-TextList -Values $effectiveServiceDirectories
$namespaceText = Get-TextList -Values @($namespaceEntries | Select-Object -ExpandProperty Namespace)
$secretText = Get-TextList -Values @(
    $secretEntries |
        Where-Object { $_.RequiredBeforeDeploy } |
        ForEach-Object { "{0}/{1}" -f $_.Namespace, $_.Name }
)
$storageClassText = Get-TextList -Values @($storageClassEntries | Select-Object -ExpandProperty Name)
$crdText = Get-TextList -Values @($crdEntries | Select-Object -ExpandProperty CrdName)
$helmReleaseText = Get-TextList -Values @($helmReleaseEntries | Select-Object -ExpandProperty Name)
$currentContextText = if ($clusterAccess.CurrentContext) { $clusterAccess.CurrentContext } else { "none" }
$kubectlInstalledText = if ($clusterAccess.KubectlInstalled) { "yes" } else { "no" }
$helmInstalledText = if ($clusterAccess.HelmInstalled) { "yes" } else { "no" }
$helmInstalledDetailsText = if ($clusterAccess.HelmInstalled) {
    "Helm client is available."
}
else {
    $clusterAccess.HelmRepoQueryMessage
}
$helmRepoQueryStatusText = if ($clusterAccess.HelmRepoQuerySucceeded) {
    "available"
}
elseif ($clusterAccess.HelmInstalled) {
    "unavailable"
}
else {
    "skipped"
}
$helmRepoQueryDetailsText = if ($clusterAccess.HelmRepoQuerySucceeded) {
    "Configured Helm repositories were loaded."
}
else {
    $clusterAccess.HelmRepoQueryMessage
}
$recommendedSecretPlanCommand = Get-PreflightCommandLine `
    -ValuesFile $resolvedValuesFile `
    -Profile $selection.Profile `
    -Applications $selection.Applications `
    -DataServices $selection.DataServices `
    -IncludeJenkins ([bool]$IncludeJenkins) `
    -Format "markdown"
$recommendedSecretPlanCommand = $recommendedSecretPlanCommand.Replace("show-cluster-preflight.ps1", "show-cluster-secret-plan.ps1")
$recommendedPreflightCommand = Get-PreflightCommandLine `
    -ValuesFile $resolvedValuesFile `
    -Profile $selection.Profile `
    -Applications $selection.Applications `
    -DataServices $selection.DataServices `
    -IncludeJenkins ([bool]$IncludeJenkins) `
    -Format "markdown"

$recommendedReadinessCommand = @(
    ".\scripts\show-validation-readiness.ps1",
    "-ValuesFile",
    $resolvedValuesFile,
    "-Profile",
    $selection.Profile
)
if (@($selection.Applications).Count -gt 0) {
    $recommendedReadinessCommand += @("-Applications", ($selection.Applications -join ","))
}
if (@($selection.DataServices).Count -gt 0) {
    $recommendedReadinessCommand += @("-DataServices", ($selection.DataServices -join ","))
}
if ($IncludeJenkins) {
    $recommendedReadinessCommand += "-IncludeJenkins"
}
$recommendedReadinessCommand += @("-Format", "markdown")
$recommendedReadinessCommandText = $recommendedReadinessCommand -join " "

$recommendedValidationCommand = @(
    ".\scripts\validate-platform-assets.ps1",
    "-ValuesFile",
    $resolvedValuesFile,
    "-Profile",
    $selection.Profile
)
if (@($selection.Applications).Count -gt 0) {
    $recommendedValidationCommand += @("-Applications", ($selection.Applications -join ","))
}
if (@($selection.DataServices).Count -gt 0) {
    $recommendedValidationCommand += @("-DataServices", ($selection.DataServices -join ","))
}
if ($IncludeJenkins) {
    $recommendedValidationCommand += "-IncludeJenkins"
}
if (@($helmReleaseEntries).Count -gt 0) {
    $recommendedValidationCommand += "-PrepareHelmRepos"
}
$recommendedValidationCommandText = $recommendedValidationCommand -join " "

switch ($Format) {
    "json" {
        $document = ([ordered]@{
            GeneratedAt = (Get-Date).ToString("s")
            RepoRoot = $root
            ValuesFile = $resolvedValuesFile
            Profile = $selection.Profile
            Description = $selection.Description
            Applications = @($selection.Applications)
            DataServices = @($selection.DataServices)
            IncludeJenkins = [bool]$IncludeJenkins
            ServiceDirectories = @($effectiveServiceDirectories)
            OverallStatus = $overallStatus
            ClusterAccess = $clusterAccess
            NamespaceEntries = @($namespaceEntries)
            SecretEntries = @($secretEntries)
            StorageClassEntries = @($storageClassEntries)
            CrdEntries = @($crdEntries)
            HelmReleaseEntries = @($helmReleaseEntries)
            SkippedHelmReleases = @($skippedHelmReleases | ForEach-Object {
                [PSCustomObject]@{
                    Name = $_.Name
                    K8sDirectory = $_.K8sDirectory
                    Enabled = [bool]$_.Enabled
                    Chart = if ($_.Chart) { $_.Chart } else { "" }
                    Notes = if ($_.Notes) { $_.Notes } else { "" }
                }
            })
            MissingRequiredNamespaces = @($missingRequiredNamespaces | Select-Object -ExpandProperty Namespace)
            MissingRequiredSecrets = @($missingRequiredSecrets | ForEach-Object { "{0}/{1}" -f $_.Namespace, $_.Name })
            MissingStorageClasses = @($missingStorageClasses | Select-Object -ExpandProperty Name)
            MissingCrds = @($missingCrds | Select-Object -ExpandProperty CrdName)
            MissingHelmRepos = @($missingHelmRepos | Select-Object -ExpandProperty Name)
            ManualChecks = @($manualCheckItems)
            RecommendedCommands = @(
                $recommendedSecretPlanCommand,
                $recommendedPreflightCommand,
                $recommendedReadinessCommandText,
                $recommendedValidationCommandText
            )
        } | ConvertTo-Json -Depth 10)
    }
    "markdown" {
        $lines = @(
            "# Cluster Preflight",
            "",
            "This report reflects the selected bundle, the provided values file, and the current cluster and Helm client state on this workstation. Re-run it against the target cluster before rollout.",
            "",
            "## Summary",
            "",
            ("- Profile: " + $selection.Profile),
            ("- Description: " + $selection.Description),
            ("- Applications: " + $applicationsText),
            ("- Data services: " + $dataServicesText),
            ("- Include Jenkins: " + [string]([bool]$IncludeJenkins)),
            ("- Values file: " + $resolvedValuesFile),
            ("- Service directories: " + $serviceDirectoriesText),
            ("- Overall status: " + $overallStatus),
            ("- Current kubectl context: " + $currentContextText),
            ("- Cluster reachable: " + [string]$clusterAccess.ClusterReachable),
            ("- Required namespaces: " + $namespaceText),
            ("- Pre-existing secrets required: " + $secretText),
            ("- Storage classes referenced: " + $storageClassText),
            ("- Custom resources requiring CRDs: " + $crdText),
            ("- Helm releases: " + $helmReleaseText),
            ""
        )

        $lines += "## Access Status"
        $lines += ""
        $lines += "| Check | Result | Details |"
        $lines += "| --- | --- | --- |"
        $lines += ("| kubectl installed | {0} | {1} |" -f $kubectlInstalledText, $clusterAccess.ClusterMessage)
        $lines += ("| Helm installed | {0} | {1} |" -f $helmInstalledText, $helmInstalledDetailsText)
        $lines += ("| Helm repo query | {0} | {1} |" -f $helmRepoQueryStatusText, $helmRepoQueryDetailsText)

        if (@($namespaceEntries).Count -gt 0) {
            $lines += ""
            $lines += "## Namespace Checks"
            $lines += ""
            $lines += "| Namespace | Provisioning | Required Before Deploy | Cluster Status | Sources |"
            $lines += "| --- | --- | --- | --- | --- |"
            foreach ($entry in $namespaceEntries) {
                $lines += ("| {0} | {1} | {2} | {3} | {4} |" -f $entry.Namespace, $entry.Provisioning, [string]$entry.RequiredBeforeDeploy, $entry.ClusterStatus, (Get-TextList -Values $entry.SourcePaths))
            }
        }

        if (@($secretEntries).Count -gt 0) {
            $lines += ""
            $lines += "## Secret Checks"
            $lines += ""
            $lines += "| Namespace | Secret | Provisioning | Cluster Status | Source Values Keys | Sources |"
            $lines += "| --- | --- | --- | --- | --- | --- |"
            foreach ($entry in $secretEntries) {
                $lines += ("| {0} | {1} | {2} | {3} | {4} | {5} |" -f $entry.Namespace, $entry.Name, $entry.Provisioning, $entry.ClusterStatus, (Get-TextList -Values $entry.ValueKeys), (Get-TextList -Values $entry.SourcePaths))
            }
        }

        if (@($storageClassEntries).Count -gt 0) {
            $lines += ""
            $lines += "## Storage Class Checks"
            $lines += ""
            $lines += "| Storage Class | Cluster Status | Sources |"
            $lines += "| --- | --- | --- |"
            foreach ($entry in $storageClassEntries) {
                $lines += ("| {0} | {1} | {2} |" -f $entry.Name, $entry.ClusterStatus, (Get-TextList -Values $entry.SourcePaths))
            }
        }

        if (@($crdEntries).Count -gt 0) {
            $lines += ""
            $lines += "## Custom Resource Checks"
            $lines += ""
            $lines += "| CRD | API Group | Kinds | Cluster Status | Sources |"
            $lines += "| --- | --- | --- | --- | --- |"
            foreach ($entry in $crdEntries) {
                $lines += ("| {0} | {1} | {2} | {3} | {4} |" -f $entry.CrdName, $entry.ApiGroup, (Get-TextList -Values $entry.Kinds), $entry.ClusterStatus, (Get-TextList -Values $entry.SourcePaths))
            }
        }

        if (@($helmReleaseEntries).Count -gt 0) {
            $lines += ""
            $lines += "## Helm Source Checks"
            $lines += ""
            $lines += "| Release | Namespace | Chart | Repo Status | Repo |"
            $lines += "| --- | --- | --- | --- | --- |"
            foreach ($entry in $helmReleaseEntries) {
                $repoText = if ($entry.SourceType -eq "oci") {
                    "OCI chart"
                }
                elseif ($entry.RepoName -and $entry.RepoUrl) {
                    "{0} ({1})" -f $entry.RepoName, $entry.RepoUrl
                }
                else {
                    "none"
                }

                $lines += ("| {0} | {1} | {2} | {3} | {4} |" -f $entry.Name, $entry.Namespace, $entry.Chart, $entry.RepoStatus, $repoText)
            }
        }

        if (@($skippedHelmReleases).Count -gt 0) {
            $lines += ""
            $lines += "## Skipped Helm Releases"
            $lines += ""
            foreach ($release in $skippedHelmReleases) {
                $notes = if ($release.Notes) { $release.Notes } else { "Release is disabled or missing chart information." }
                $lines += ("- " + $release.Name + ": " + $notes)
            }
        }

        if (@($manualCheckItems).Count -gt 0) {
            $lines += ""
            $lines += "## Manual Follow-up Checks"
            $lines += ""
            foreach ($item in $manualCheckItems) {
                $lines += ("- " + $item)
            }
        }

        $lines += ""
        $lines += "## Recommended Commands"
        $lines += ""
        $lines += '```powershell'
        $lines += $recommendedSecretPlanCommand
        $lines += $recommendedPreflightCommand
        $lines += $recommendedReadinessCommandText
        $lines += $recommendedValidationCommandText
        $lines += '```'

        $document = $lines -join [Environment]::NewLine
    }
    default {
        $lines = @(
            "Cluster Preflight",
            "=================",
            ("Profile: " + $selection.Profile),
            ("Description: " + $selection.Description),
            ("Applications: " + $applicationsText),
            ("Data services: " + $dataServicesText),
            ("Include Jenkins: " + [string]([bool]$IncludeJenkins)),
            ("Values file: " + $resolvedValuesFile),
            ("Service directories: " + $serviceDirectoriesText),
            ("Overall status: " + $overallStatus),
            ("Current kubectl context: " + $currentContextText),
            ("Cluster reachable: " + [string]$clusterAccess.ClusterReachable),
            ("Required namespaces: " + $namespaceText),
            ("Pre-existing secrets required: " + $secretText),
            ("Storage classes referenced: " + $storageClassText),
            ("Custom resources requiring CRDs: " + $crdText),
            ("Helm releases: " + $helmReleaseText),
            "",
            "Access status",
            ("- kubectl installed: " + [string]$clusterAccess.KubectlInstalled),
            ("  Details: " + $clusterAccess.ClusterMessage),
            ("- helm installed: " + [string]$clusterAccess.HelmInstalled),
            ("- helm repo query available: " + [string]$clusterAccess.HelmRepoQuerySucceeded)
        )

        if (@($namespaceEntries).Count -gt 0) {
            $lines += ""
            $lines += "Namespace checks"
            foreach ($entry in $namespaceEntries) {
                $lines += ("- {0}: provisioning={1}, required-before-deploy={2}, cluster-status={3}" -f $entry.Namespace, $entry.Provisioning, [string]$entry.RequiredBeforeDeploy, $entry.ClusterStatus)
            }
        }

        if (@($secretEntries).Count -gt 0) {
            $lines += ""
            $lines += "Secret checks"
            foreach ($entry in $secretEntries) {
                $lines += ("- {0}/{1}: provisioning={2}, cluster-status={3}" -f $entry.Namespace, $entry.Name, $entry.Provisioning, $entry.ClusterStatus)
            }
        }

        if (@($storageClassEntries).Count -gt 0) {
            $lines += ""
            $lines += "Storage class checks"
            foreach ($entry in $storageClassEntries) {
                $lines += ("- {0}: cluster-status={1}" -f $entry.Name, $entry.ClusterStatus)
            }
        }

        if (@($crdEntries).Count -gt 0) {
            $lines += ""
            $lines += "Custom resource checks"
            foreach ($entry in $crdEntries) {
                $lines += ("- {0}: api-group={1}, cluster-status={2}" -f $entry.CrdName, $entry.ApiGroup, $entry.ClusterStatus)
            }
        }

        if (@($helmReleaseEntries).Count -gt 0) {
            $lines += ""
            $lines += "Helm source checks"
            foreach ($entry in $helmReleaseEntries) {
                $lines += ("- {0}: chart={1}, repo-status={2}" -f $entry.Name, $entry.Chart, $entry.RepoStatus)
            }
        }

        if (@($manualCheckItems).Count -gt 0) {
            $lines += ""
            $lines += "Manual follow-up checks"
            foreach ($item in $manualCheckItems) {
                $lines += ("- " + $item)
            }
        }

        $lines += ""
        $lines += "Recommended commands"
        $lines += ("- " + $recommendedSecretPlanCommand)
        $lines += ("- " + $recommendedPreflightCommand)
        $lines += ("- " + $recommendedReadinessCommandText)
        $lines += ("- " + $recommendedValidationCommandText)

        $document = $lines -join [Environment]::NewLine
    }
}

if ($PSBoundParameters.ContainsKey("OutputPath") -and $OutputPath) {
    $resolvedOutputPath = [System.IO.Path]::GetFullPath($OutputPath)
    $outputDirectory = Split-Path -Path $resolvedOutputPath -Parent
    if ($outputDirectory) {
        New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
    }

    Set-Content -Path $resolvedOutputPath -Value $document -NoNewline
    Write-Host ("Wrote cluster preflight report to {0}" -f $resolvedOutputPath)
}
else {
    Write-Output $document
}
