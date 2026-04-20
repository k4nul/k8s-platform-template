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

. (Join-Path $PSScriptRoot "platform-catalog.ps1")
. (Join-Path $PSScriptRoot "cluster-secret-catalog.ps1")

function Get-ToolVersion {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    switch ($Name) {
        "kubectl" { return (& kubectl version --client 2>$null | Out-String).Trim() }
        "helm"    { return (& helm version --short 2>$null | Out-String).Trim() }
        "git"     { return (& git --version 2>$null | Out-String).Trim() }
        "docker"  { return (& docker --version 2>$null | Out-String).Trim() }
        "python"  { return (& python --version 2>&1 | Out-String).Trim() }
        default   { return "" }
    }
}

function Get-TextList {
    param(
        [object[]]$Values,
        [string]$Empty = "none"
    )

    if (@($Values).Count -gt 0) {
        return (@($Values) -join ", ")
    }

    return $Empty
}

function Get-EffectiveK8sDirectories {
    param(
        [string]$Root,
        [pscustomobject]$Selection
    )

    if ($Selection.IncludeAllK8s) {
        return @(
            Get-ChildItem -Path (Join-Path $Root "k8s") -Directory |
                Sort-Object Name |
                Select-Object -ExpandProperty Name
        )
    }

    return @($Selection.K8sDirectories | Sort-Object -Unique)
}

function Get-EffectiveServiceDirectories {
    param(
        [string]$Root,
        [pscustomobject]$Selection
    )

    if ($Selection.IncludeAllServices) {
        return @(
            Get-ChildItem -Path (Join-Path $Root "services") -Directory |
                Sort-Object Name |
                Select-Object -ExpandProperty Name
        )
    }

    return @($Selection.ServiceDirectories | Sort-Object -Unique)
}

function Get-RelativePathFromRoot {
    param(
        [string]$Root,
        [string]$Path
    )

    $resolvedRoot = [System.IO.Path]::GetFullPath($Root).TrimEnd('\') + '\'
    $resolvedPath = [System.IO.Path]::GetFullPath($Path)
    return $resolvedPath.Substring($resolvedRoot.Length)
}

function Get-CrdBackedManifestEntries {
    param(
        [string]$Root,
        [string[]]$K8sDirectories
    )

    $entries = @()

    foreach ($directory in @($K8sDirectories | Sort-Object -Unique)) {
        $directoryRoot = Join-Path $Root ("k8s\{0}" -f $directory)
        if (-not (Test-Path -Path $directoryRoot -PathType Container)) {
            continue
        }

        Get-ChildItem -Path $directoryRoot -Recurse -File | Where-Object {
            $_.Extension.ToLowerInvariant() -in @(".yaml", ".yml") -and $_.Name -ne "values.yaml"
        } | ForEach-Object {
            $content = Get-Content -Path $_.FullName -Raw
            $apiGroup = ""

            if ($content -match '(?m)^apiVersion:\s*gateway\.networking\.k8s\.io/') {
                $apiGroup = "gateway.networking.k8s.io"
            }
            elseif ($content -match '(?m)^apiVersion:\s*autoscaling\.k8s\.io/') {
                $apiGroup = "autoscaling.k8s.io"
            }

            if ($apiGroup) {
                $entries += [PSCustomObject]@{
                    Directory = $directory
                    RelativePath = Get-RelativePathFromRoot -Root $Root -Path $_.FullName
                    ApiGroup = $apiGroup
                }
            }
        }
    }

    return @($entries | Sort-Object RelativePath -Unique)
}

function Get-ValidationCommandLine {
    param(
        [string]$ValuesFile,
        [string]$Profile,
        [string[]]$Applications,
        [string[]]$DataServices,
        [bool]$IncludeJenkins,
        [bool]$PrepareHelmRepos,
        [bool]$IncludeCrdBackedResources
    )

    $parts = New-Object System.Collections.Generic.List[string]
    $parts.Add(".\scripts\validate-platform-assets.ps1") | Out-Null
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

    if ($PrepareHelmRepos) {
        $parts.Add("-PrepareHelmRepos") | Out-Null
    }

    if ($IncludeCrdBackedResources) {
        $parts.Add("-ValidateCrdBackedResources") | Out-Null
    }

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
$resolvedHelmConfig = (Resolve-Path -Path $HelmConfigFile).Path
$resolvedValuesFile = [System.IO.Path]::GetFullPath($ValuesFile)
$selection = Resolve-PlatformSelection -Profile $Profile -Applications $Applications -DataServices $DataServices -IncludeJenkins:$IncludeJenkins
$clusterSecretPlan = Get-ClusterSecretPlanData `
    -RepoRoot $root `
    -ValuesFile $resolvedValuesFile `
    -Profile $selection.Profile `
    -Applications $selection.Applications `
    -DataServices $selection.DataServices `
    -IncludeJenkins:$IncludeJenkins
$effectiveK8sDirectories = @(Get-EffectiveK8sDirectories -Root $root -Selection $selection)
$effectiveServiceDirectories = @(Get-EffectiveServiceDirectories -Root $root -Selection $selection)
$componentCatalog = Get-PlatformK8sComponentCatalog
$helmConfig = Import-PowerShellDataFile -Path $resolvedHelmConfig

$componentEntries = @()
foreach ($directory in $effectiveK8sDirectories) {
    $component = if ($componentCatalog.Contains($directory)) { $componentCatalog[$directory] } else { $null }
    $componentEntries += [PSCustomObject]@{
        Directory = $directory
        Delivery = if ($null -ne $component) { $component.Delivery } else { "uncatalogued" }
        Description = if ($null -ne $component) { $component.Description } else { "No component catalog description is defined for this directory yet." }
        PhaseName = if ($null -ne $component) { $component.PhaseName } else { "" }
    }
}

$helmReleases = @($helmConfig.Releases | Where-Object {
    $_.Enabled -and $_.ValuesRelativePath -and $_.Chart -and (
        $selection.IncludeAllK8s -or $_.K8sDirectory -in $effectiveK8sDirectories
    )
} | Sort-Object Name)

$skippedHelmReleases = @($helmConfig.Releases | Where-Object {
    ($selection.IncludeAllK8s -or $_.K8sDirectory -in $effectiveK8sDirectories) -and (
        -not $_.Enabled -or -not $_.Chart
    )
} | Sort-Object Name)

$crdBackedManifestEntries = @(Get-CrdBackedManifestEntries -Root $root -K8sDirectories $effectiveK8sDirectories)
$rawComponents = @($componentEntries | Where-Object { $_.Delivery -eq "raw" })
$deferredComponents = @($componentEntries | Where-Object { $_.Delivery -eq "deferred-raw" })
$bootstrapSecretEntries = @($clusterSecretPlan.Secrets)
$bootstrapNamespaceNames = @($bootstrapSecretEntries | Select-Object -ExpandProperty Namespace | Where-Object { $_ } | Sort-Object -Unique)
$bootstrapNamespaceEntries = @($clusterSecretPlan.NamespaceEntries | Where-Object {
    $bootstrapNamespaceNames -contains $_.Namespace -and [string]$_.Provisioning -ne "pre-existing-system"
})
$requiresKubectl = ($rawComponents.Count + $deferredComponents.Count + $bootstrapNamespaceEntries.Count + $bootstrapSecretEntries.Count) -gt 0
$requiresHelm = $helmReleases.Count -gt 0

$toolDefinitions = @(
    @{
        Name = "kubectl"
        Purpose = "Rendered manifest and bootstrap YAML dry-run validation plus raw bundle apply, status, and destroy helpers."
        RequiredForSelectedValidation = $requiresKubectl
    }
    @{
        Name = "helm"
        Purpose = "Helm template validation plus Helm bundle install, status, and destroy helpers."
        RequiredForSelectedValidation = $requiresHelm
    }
    @{
        Name = "git"
        Purpose = "Repository inspection and change tracking."
        RequiredForSelectedValidation = $false
    }
    @{
        Name = "docker"
        Purpose = "Optional local compose refresh, image builds, and runtime debugging."
        RequiredForSelectedValidation = $false
    }
    @{
        Name = "python"
        Purpose = "Optional script execution and environment debugging outside PowerShell flows."
        RequiredForSelectedValidation = $false
    }
)

$toolReport = @()
foreach ($definition in $toolDefinitions) {
    $command = Get-Command $definition.Name -ErrorAction SilentlyContinue
    $toolReport += [PSCustomObject]@{
        Tool = $definition.Name
        Installed = ($null -ne $command)
        Version = if ($null -ne $command) { Get-ToolVersion -Name $definition.Name } else { "" }
        RequiredForSelectedValidation = [bool]$definition.RequiredForSelectedValidation
        Purpose = $definition.Purpose
    }
}

$requiredTools = @($toolReport | Where-Object { $_.RequiredForSelectedValidation })
$missingRequiredTools = @($requiredTools | Where-Object { -not $_.Installed })
$installedRequiredTools = @($requiredTools | Where-Object { $_.Installed })

$readinessStatus = if ($missingRequiredTools.Count -eq 0) {
    "full-bundle-validation-available"
}
elseif ($installedRequiredTools.Count -gt 0) {
    "partial-bundle-validation-available"
}
else {
    "repository-only-validation-available"
}

$availableChecks = New-Object System.Collections.Generic.List[string]
$blockedChecks = New-Object System.Collections.Generic.List[string]

$availableChecks.Add("Repository-level template validation via .\scripts\validate-template.ps1") | Out-Null
$availableChecks.Add("Selection and values validation via .\scripts\validate-platform-selection.ps1 and .\scripts\validate-platform-values.ps1") | Out-Null
$availableChecks.Add("Service catalog, build, config, pipeline, and runtime validation via the .\scripts\validate-service-*.ps1 helpers") | Out-Null
$availableChecks.Add("Placeholder scanning via .\scripts\check-placeholders.ps1 -Path .") | Out-Null

if ($requiresKubectl) {
    if (($toolReport | Where-Object { $_.Tool -eq "kubectl" }).Installed) {
        $availableChecks.Add("Rendered raw manifest and bootstrap YAML dry-run validation via .\scripts\validate-platform-assets.ps1") | Out-Null
    }
    else {
        $blockedChecks.Add("Rendered raw manifest and bootstrap YAML dry-run validation is blocked until kubectl is installed.") | Out-Null
    }
}

if ($requiresHelm) {
    if (($toolReport | Where-Object { $_.Tool -eq "helm" }).Installed) {
        $availableChecks.Add("Helm template validation via .\scripts\validate-platform-assets.ps1") | Out-Null
    }
    else {
        $blockedChecks.Add("Helm template validation is blocked until helm is installed.") | Out-Null
    }
}

if ($crdBackedManifestEntries.Count -gt 0) {
    $blockedChecks.Add("CRD-backed manifest validation is intentionally skipped by default. Use -ValidateCrdBackedResources after the required CRDs are installed.") | Out-Null
}

$recommendedValidationCommand = Get-ValidationCommandLine `
    -ValuesFile $resolvedValuesFile `
    -Profile $selection.Profile `
    -Applications $selection.Applications `
    -DataServices $selection.DataServices `
    -IncludeJenkins ([bool]$IncludeJenkins) `
    -PrepareHelmRepos ($helmReleases.Count -gt 0) `
    -IncludeCrdBackedResources ($crdBackedManifestEntries.Count -gt 0)

$recommendedBootstrapValidationCommand = ""
if ($bootstrapSecretEntries.Count -gt 0) {
    $availableChecks.Add("Bootstrap secret placeholder readiness validation via .\scripts\validate-platform-assets.ps1 -RenderedPath <bundle-root> -RequireBootstrapSecretsReady after editing generated secret templates.") | Out-Null
    $recommendedBootstrapValidationCommand = ($recommendedValidationCommand + " -RenderedPath <bundle-root> -RequireBootstrapSecretsReady")
}

$applicationsText = Get-TextList -Values $selection.Applications
$dataServicesText = Get-TextList -Values $selection.DataServices
$k8sDirectoriesText = Get-TextList -Values $effectiveK8sDirectories
$serviceDirectoriesText = Get-TextList -Values $effectiveServiceDirectories
$bootstrapNamespaceText = Get-TextList -Values @($bootstrapNamespaceEntries | Select-Object -ExpandProperty Namespace)
$bootstrapSecretText = Get-TextList -Values @($bootstrapSecretEntries | ForEach-Object { "{0}/{1}" -f $_.Namespace, $_.Name })
$missingRequiredToolsText = Get-TextList -Values @($missingRequiredTools | Select-Object -ExpandProperty Tool)
$helmReleaseJsonEntries = @($helmReleases | ForEach-Object {
    [PSCustomObject]@{
        Name = $_.Name
        Namespace = $_.Namespace
        Chart = $_.Chart
        K8sDirectory = $_.K8sDirectory
    }
})
$skippedHelmReleaseJsonEntries = @($skippedHelmReleases | ForEach-Object {
    [PSCustomObject]@{
        Name = $_.Name
        K8sDirectory = $_.K8sDirectory
        Enabled = [bool]$_.Enabled
        Chart = $_.Chart
        Notes = if ($_.Notes) { $_.Notes } else { "" }
    }
})

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
            ReadinessStatus = $readinessStatus
            MissingRequiredTools = @($missingRequiredTools | Select-Object -ExpandProperty Tool)
            ToolReport = @($toolReport)
            RawComponents = @($rawComponents)
            DeferredComponents = @($deferredComponents)
            BootstrapNamespaces = @($bootstrapNamespaceEntries)
            BootstrapSecrets = @($bootstrapSecretEntries)
            HelmReleases = @($helmReleaseJsonEntries)
            SkippedHelmReleases = @($skippedHelmReleaseJsonEntries)
            CrdBackedManifestEntries = @($crdBackedManifestEntries)
            AvailableChecks = @($availableChecks)
            BlockedChecks = @($blockedChecks)
            RecommendedValidationCommand = $recommendedValidationCommand
            RecommendedBootstrapValidationCommand = $recommendedBootstrapValidationCommand
        } | ConvertTo-Json -Depth 10)
    }
    "markdown" {
        $lines = @(
            "# Validation Readiness",
            "",
            "This report reflects the current workstation and the selected deployment bundle. Re-run it on the target machine if tooling or environment state changes.",
            "",
            "## Summary",
            "",
            ("- Profile: " + $selection.Profile),
            ("- Description: " + $selection.Description),
            ("- Applications: " + $applicationsText),
            ("- Data services: " + $dataServicesText),
            ("- Include Jenkins: " + [string]([bool]$IncludeJenkins)),
            ("- Values file: " + $resolvedValuesFile),
            ("- Kubernetes directories: " + $k8sDirectoriesText),
            ("- Service directories: " + $serviceDirectoriesText),
            ("- Raw Kubernetes components: " + [string]$rawComponents.Count),
            ("- Deferred or post-controller components: " + [string]$deferredComponents.Count),
            ("- Bootstrap namespace templates: " + [string]$bootstrapNamespaceEntries.Count),
            ("- Bootstrap secret templates: " + [string]$bootstrapSecretEntries.Count),
            ("- Helm components: " + [string]$helmReleases.Count),
            ("- Readiness status: " + $readinessStatus),
            ("- Missing required tools for this bundle: " + $missingRequiredToolsText),
            "",
            "## Tool Status",
            "",
            "| Tool | Installed | Required For This Bundle | Purpose |",
            "| --- | --- | --- | --- |"
        )

        foreach ($tool in $toolReport) {
            $installedText = if ($tool.Installed) { "yes" } else { "no" }
            $requiredText = if ($tool.RequiredForSelectedValidation) { "yes" } else { "no" }
            $lines += ("| {0} | {1} | {2} | {3} |" -f $tool.Tool, $installedText, $requiredText, $tool.Purpose)
            if ($tool.Version) {
                $lines += ('| {0} version | `{1}` |  |  |' -f $tool.Tool, $tool.Version)
            }
        }

        $lines += ""
        $lines += "## Available Checks On This Workstation"
        $lines += ""
        foreach ($item in $availableChecks) {
            $lines += ("- " + $item)
        }

        if ($blockedChecks.Count -gt 0) {
            $lines += ""
            $lines += "## Blocked Or Deferred Checks"
            $lines += ""
            foreach ($item in $blockedChecks) {
                $lines += ("- " + $item)
            }
        }

        $lines += ""
        $lines += "## Selected Bundle Characteristics"
        $lines += ""
        $lines += ("- Raw components: " + (Get-TextList -Values @($rawComponents | Select-Object -ExpandProperty Directory)))
        $lines += ("- Deferred components: " + (Get-TextList -Values @($deferredComponents | Select-Object -ExpandProperty Directory)))
        $lines += ("- Bootstrap namespaces: " + $bootstrapNamespaceText)
        $lines += ("- Bootstrap secrets: " + $bootstrapSecretText)
        $lines += ("- Helm releases: " + (Get-TextList -Values @($helmReleases | ForEach-Object { "{0} ({1})" -f $_.Name, $_.Chart })))
        $lines += ("- Skipped Helm releases: " + (Get-TextList -Values @($skippedHelmReleases | Select-Object -ExpandProperty Name)))

        if ($crdBackedManifestEntries.Count -gt 0) {
            $lines += ""
            $lines += "## CRD-backed Manifests"
            $lines += ""
            foreach ($entry in $crdBackedManifestEntries) {
                $lines += ('- `{0}`: {1}' -f $entry.RelativePath, $entry.ApiGroup)
            }
        }

        $lines += ""
        $lines += "## Recommended Commands"
        $lines += ""
        $lines += '```powershell'
        $lines += ".\scripts\validate-workstation.ps1"
        $lines += (".\scripts\show-validation-readiness.ps1 -Profile " + $selection.Profile + " -ValuesFile " + $resolvedValuesFile + " -Format markdown")
        $lines += $recommendedValidationCommand
        if ($recommendedBootstrapValidationCommand) {
            $lines += $recommendedBootstrapValidationCommand
        }
        $lines += '```'

        $document = $lines -join [Environment]::NewLine
    }
    default {
        $lines = @(
            "Validation Readiness",
            "====================",
            ("Profile: " + $selection.Profile),
            ("Description: " + $selection.Description),
            ("Applications: " + $applicationsText),
            ("Data services: " + $dataServicesText),
            ("Include Jenkins: " + [string]([bool]$IncludeJenkins)),
            ("Values file: " + $resolvedValuesFile),
            ("Kubernetes directories: " + $k8sDirectoriesText),
            ("Service directories: " + $serviceDirectoriesText),
            ("Raw Kubernetes components: " + [string]$rawComponents.Count),
            ("Deferred components: " + [string]$deferredComponents.Count),
            ("Bootstrap namespace templates: " + [string]$bootstrapNamespaceEntries.Count),
            ("Bootstrap secret templates: " + [string]$bootstrapSecretEntries.Count),
            ("Helm components: " + [string]$helmReleases.Count),
            ("Readiness status: " + $readinessStatus),
            ("Missing required tools: " + $missingRequiredToolsText),
            "",
            "Tool status"
        )

        foreach ($tool in $toolReport) {
            $lines += ("- {0}: installed={1}, required-for-this-bundle={2}" -f $tool.Tool, [string]$tool.Installed, [string]$tool.RequiredForSelectedValidation)
            if ($tool.Version) {
                $lines += ("  Version: " + $tool.Version)
            }
            $lines += ("  Purpose: " + $tool.Purpose)
        }

        $lines += ""
        $lines += "Available checks"
        foreach ($item in $availableChecks) {
            $lines += ("- " + $item)
        }

        if ($blockedChecks.Count -gt 0) {
            $lines += ""
            $lines += "Blocked or deferred checks"
            foreach ($item in $blockedChecks) {
                $lines += ("- " + $item)
            }
        }

        if ($crdBackedManifestEntries.Count -gt 0) {
            $lines += ""
            $lines += "CRD-backed manifests"
            foreach ($entry in $crdBackedManifestEntries) {
                $lines += ("- " + $entry.RelativePath + ": " + $entry.ApiGroup)
            }
        }

        $lines += ""
        $lines += "Selected bundle characteristics"
        $lines += ("- Bootstrap namespaces: " + $bootstrapNamespaceText)
        $lines += ("- Bootstrap secrets: " + $bootstrapSecretText)

        $lines += ""
        $lines += "Recommended validation command"
        $lines += ("- " + $recommendedValidationCommand)
        if ($recommendedBootstrapValidationCommand) {
            $lines += ("- " + $recommendedBootstrapValidationCommand)
        }

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
    Write-Host ("Wrote validation readiness report to {0}" -f $resolvedOutputPath)
}
else {
    Write-Output $document
}
