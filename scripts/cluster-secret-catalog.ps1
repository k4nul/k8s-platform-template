Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-ClusterSecretCatalog {
    param(
        [string]$RepoRoot
    )

    if (-not $PSBoundParameters.ContainsKey("RepoRoot") -or -not $RepoRoot) {
        $RepoRoot = Join-Path $PSScriptRoot ".."
    }

    $root = (Resolve-Path -Path $RepoRoot).Path
    return Import-PowerShellDataFile -Path (Join-Path $root "config\cluster-secret-catalog.psd1")
}

function Resolve-ClusterSecretCatalogEntry {
    param(
        [pscustomobject]$SecretEntry,
        [object[]]$CatalogEntries
    )

    $valueKeys = @($SecretEntry.ValueKeys)

    foreach ($entry in @($CatalogEntries)) {
        if ($entry.ContainsKey("MatchValueKey") -and $entry.MatchValueKey -and $valueKeys -contains $entry.MatchValueKey) {
            return $entry
        }
    }

    foreach ($entry in @($CatalogEntries)) {
        if ($entry.ContainsKey("MatchName") -and $entry.MatchName -and $SecretEntry.Name -eq $entry.MatchName) {
            return $entry
        }
    }

    return $null
}

function Get-ClusterSecretExampleValue {
    param(
        [string]$Key,
        [System.Collections.IDictionary]$CatalogEntry
    )

    if ($null -ne $CatalogEntry -and $CatalogEntry.ContainsKey("ExampleValues") -and $CatalogEntry.ExampleValues.ContainsKey($Key)) {
        return [string]$CatalogEntry.ExampleValues[$Key]
    }

    $normalizedKey = ($Key.ToLowerInvariant() -replace '[^a-z0-9]+', '-').Trim('-')
    if (-not $normalizedKey) {
        $normalizedKey = "value"
    }

    return ("change-me-{0}" -f $normalizedKey)
}

function Get-ClusterSecretExampleManifest {
    param(
        [string]$Namespace,
        [string]$Name,
        [System.Collections.IDictionary]$CatalogEntry
    )

    $secretType = if ($null -ne $CatalogEntry -and $CatalogEntry.ContainsKey("SecretType")) {
        [string]$CatalogEntry.SecretType
    }
    else {
        "Opaque"
    }

    $templateType = if ($null -ne $CatalogEntry -and $CatalogEntry.ContainsKey("TemplateType")) {
        [string]$CatalogEntry.TemplateType
    }
    else {
        "opaque"
    }

    $requiredKeys = if ($null -ne $CatalogEntry -and $CatalogEntry.ContainsKey("RequiredKeys")) {
        @($CatalogEntry.RequiredKeys)
    }
    else {
        @("PLACEHOLDER_KEY")
    }

    $lines = @(
        "apiVersion: v1",
        "kind: Secret",
        "metadata:",
        ("  name: " + $Name),
        ("  namespace: " + $Namespace),
        ("type: " + $secretType)
    )

    switch ($templateType) {
        "docker-registry" {
            $lines += "stringData:"
            $lines += "  .dockerconfigjson: |"
            $lines += "    {"
            $lines += '      "auths": {'
            $lines += '        "registry.example.com": {'
            $lines += '          "username": "REPLACE_WITH_REGISTRY_USERNAME",'
            $lines += '          "password": "REPLACE_WITH_REGISTRY_PASSWORD",'
            $lines += '          "email": "REPLACE_WITH_REGISTRY_EMAIL",'
            $lines += '          "auth": "BASE64_ENCODED_USERNAME_COLON_PASSWORD"'
            $lines += "        }"
            $lines += "      }"
            $lines += "    }"
        }
        "tls" {
            $lines += "stringData:"
            $lines += "  tls.crt: |"
            $lines += "    -----BEGIN CERTIFICATE-----"
            $lines += "    REPLACE_WITH_CERTIFICATE_CONTENT"
            $lines += "    -----END CERTIFICATE-----"
            $lines += "  tls.key: |"
            $lines += "    -----BEGIN PRIVATE KEY-----"
            $lines += "    REPLACE_WITH_PRIVATE_KEY_CONTENT"
            $lines += "    -----END PRIVATE KEY-----"
        }
        "basic-auth" {
            $lines += "stringData:"
            $lines += ("  auth: " + (Get-ClusterSecretExampleValue -Key "auth" -CatalogEntry $CatalogEntry))
        }
        default {
            $lines += "stringData:"
            foreach ($key in @($requiredKeys)) {
                $lines += ("  {0}: {1}" -f $key, (Get-ClusterSecretExampleValue -Key $key -CatalogEntry $CatalogEntry))
            }
        }
    }

    return ($lines -join [Environment]::NewLine)
}

function Expand-ClusterSecretExampleCommand {
    param(
        [string]$Template,
        [string]$Namespace,
        [string]$Name
    )

    if (-not $Template) {
        return ""
    }

    return $Template.Replace("<namespace>", $Namespace).Replace("<name>", $Name)
}

function Get-ClusterSecretPlanData {
    param(
        [string]$RepoRoot,
        [string]$ValuesFile,
        [string]$Profile = "full",
        [string[]]$Applications = @(),
        [string[]]$DataServices = @(),
        [switch]$IncludeJenkins,
        [switch]$IncludeBundleManaged
    )

    if (-not $PSBoundParameters.ContainsKey("RepoRoot") -or -not $RepoRoot) {
        $RepoRoot = Join-Path $PSScriptRoot ".."
    }

    if (-not $PSBoundParameters.ContainsKey("ValuesFile") -or -not $ValuesFile) {
        $ValuesFile = Join-Path $PSScriptRoot "..\config\platform-values.env.example"
    }

    $root = (Resolve-Path -Path $RepoRoot).Path
    $resolvedValuesFile = (Resolve-Path -Path $ValuesFile).Path
    $preflightScript = Join-Path $PSScriptRoot "show-cluster-preflight.ps1"

    $preflightParameters = @{
        RepoRoot = $root
        ValuesFile = $resolvedValuesFile
        Profile = $Profile
        Format = "json"
    }

    if (@($Applications).Count -gt 0) {
        $preflightParameters.Applications = $Applications
    }

    if (@($DataServices).Count -gt 0) {
        $preflightParameters.DataServices = $DataServices
    }

    if ($IncludeJenkins) {
        $preflightParameters.IncludeJenkins = $true
    }

    $preflightJson = (& $preflightScript @preflightParameters | Out-String).Trim()
    if (-not $preflightJson) {
        throw "Unable to load cluster preflight data."
    }

    $preflightData = $preflightJson | ConvertFrom-Json
    $catalogEntries = @((Get-ClusterSecretCatalog -RepoRoot $root).Secrets)
    $secretEntries = @($preflightData.SecretEntries)

    if (-not $IncludeBundleManaged) {
        $secretEntries = @($secretEntries | Where-Object { $_.RequiredBeforeDeploy })
    }

    $planEntries = @()
    foreach ($secret in @($secretEntries | Sort-Object Namespace, Name)) {
        $catalogEntry = Resolve-ClusterSecretCatalogEntry -SecretEntry $secret -CatalogEntries $catalogEntries
        $requiredKeys = if ($null -ne $catalogEntry -and $catalogEntry.ContainsKey("RequiredKeys")) {
            @($catalogEntry.RequiredKeys)
        }
        else {
            @()
        }

        $planEntries += [PSCustomObject]@{
            Namespace = $secret.Namespace
            Name = $secret.Name
            Provisioning = $secret.Provisioning
            RequiredBeforeDeploy = [bool]$secret.RequiredBeforeDeploy
            ClusterStatus = $secret.ClusterStatus
            SecretType = if ($null -ne $catalogEntry -and $catalogEntry.ContainsKey("SecretType")) { $catalogEntry.SecretType } else { "Opaque" }
            Description = if ($null -ne $catalogEntry -and $catalogEntry.ContainsKey("Description")) { $catalogEntry.Description } else { "Inspect the referenced manifests to confirm the expected secret contents before creating it." }
            RequiredKeys = @($requiredKeys)
            ValueKeys = @($secret.ValueKeys)
            SourcePaths = @($secret.SourcePaths)
            CreationHint = if ($null -ne $catalogEntry -and $catalogEntry.ContainsKey("CreationHint")) { $catalogEntry.CreationHint } else { "Inspect the manifest source and create the secret with the keys your workload expects." }
            ExampleCommand = Expand-ClusterSecretExampleCommand `
                -Template $(if ($null -ne $catalogEntry -and $catalogEntry.ContainsKey("ExampleCommand")) { [string]$catalogEntry.ExampleCommand } else { "kubectl create secret generic <name> -n <namespace> --from-literal=PLACEHOLDER_KEY=change-me" }) `
                -Namespace $secret.Namespace `
                -Name $secret.Name
            ExampleManifest = Get-ClusterSecretExampleManifest `
                -Namespace $secret.Namespace `
                -Name $secret.Name `
                -CatalogEntry $catalogEntry
            CatalogMatched = ($null -ne $catalogEntry)
        }
    }

    return [PSCustomObject]@{
        RepoRoot = $root
        ValuesFile = $resolvedValuesFile
        Profile = $preflightData.Profile
        Description = $preflightData.Description
        Applications = @($preflightData.Applications)
        DataServices = @($preflightData.DataServices)
        IncludeJenkins = [bool]$preflightData.IncludeJenkins
        IncludeBundleManaged = [bool]$IncludeBundleManaged
        PreflightStatus = $preflightData.OverallStatus
        ClusterAccess = $preflightData.ClusterAccess
        NamespaceEntries = @($preflightData.NamespaceEntries)
        Secrets = @($planEntries)
    }
}
