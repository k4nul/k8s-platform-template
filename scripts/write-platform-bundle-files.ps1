param(
    [string]$RepoRoot,

    [Parameter(Mandatory = $true)]
    [string]$BundleRoot,

    [Parameter(Mandatory = $true)]
    [string]$ValuesFile,

    [string]$HelmConfigFile,
    [string]$DockerRegistry,
    [string]$Version,
    [string]$Profile = "full",
    [string[]]$Applications = @(),
    [string[]]$DataServices = @(),
    [switch]$IncludeJenkins
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "platform-catalog.ps1")

function Get-JenkinsSelectionName {
    param(
        [AllowEmptyString()]
        [string]$Value
    )

    if (-not $Value) {
        return "bundle"
    }

    $normalized = $Value.Trim()
    $normalized = $normalized -replace "[/\\]+", "-"
    $normalized = $normalized -replace "[^A-Za-z0-9._-]+", "-"
    $normalized = $normalized.Trim("-")

    if (-not $normalized) {
        return "bundle"
    }

    return $normalized
}

if (-not $PSBoundParameters.ContainsKey("RepoRoot") -or -not $RepoRoot) {
    $RepoRoot = Join-Path $PSScriptRoot ".."
}

if (-not $PSBoundParameters.ContainsKey("HelmConfigFile") -or -not $HelmConfigFile) {
    $HelmConfigFile = Join-Path $PSScriptRoot "..\config\helm-releases.psd1"
}

$resolvedBundleRoot = [System.IO.Path]::GetFullPath($BundleRoot)
$resolvedValuesFile = [System.IO.Path]::GetFullPath($ValuesFile)
$resolvedHelmConfig = (Resolve-Path -Path $HelmConfigFile).Path
$selection = Resolve-PlatformSelection -Profile $Profile -Applications $Applications -DataServices $DataServices -IncludeJenkins:$IncludeJenkins
$componentCatalog = Get-PlatformK8sComponentCatalog
$optionalManifestCatalog = Get-PlatformOptionalManifestCatalog
$helmConfig = Import-PowerShellDataFile -Path $resolvedHelmConfig
$jenkinsJobPlanScript = Join-Path $PSScriptRoot "show-jenkins-job-plan.ps1"
$jenkinsJobDslExportScript = Join-Path $PSScriptRoot "export-jenkins-job-dsl.ps1"

New-Item -ItemType Directory -Path $resolvedBundleRoot -Force | Out-Null

$k8sRoot = Join-Path $resolvedBundleRoot "k8s"
$servicesRoot = Join-Path $resolvedBundleRoot "services"

$renderedK8sDirectories = if (Test-Path -Path $k8sRoot -PathType Container) {
    @(Get-ChildItem -Path $k8sRoot -Directory | Sort-Object Name | Select-Object -ExpandProperty Name)
}
else {
    @()
}

$renderedServiceDirectories = if (Test-Path -Path $servicesRoot -PathType Container) {
    @(Get-ChildItem -Path $servicesRoot -Directory | Sort-Object Name | Select-Object -ExpandProperty Name)
}
else {
    @()
}

$phaseMap = [ordered]@{}
foreach ($directory in $renderedK8sDirectories) {
    if (-not $componentCatalog.Contains($directory)) {
        continue
    }

    $component = $componentCatalog[$directory]
    if ($component.Delivery -eq "helm") {
        continue
    }

    if (-not $phaseMap.Contains($component.PhaseId)) {
        $phaseMap[$component.PhaseId] = [ordered]@{
            Id = $component.PhaseId
            Name = $component.PhaseName
            Components = New-Object System.Collections.Generic.List[object]
        }
    }

    $phaseMap[$component.PhaseId].Components.Add([PSCustomObject]@{
        Directory = $directory
        Description = $component.Description
        Delivery = $component.Delivery
        ApplyPath = ("k8s\{0}" -f $directory)
        Notes = $component.Notes
    }) | Out-Null
}

$phaseList = @()
$phaseOrder = @("phase-a", "phase-b", "phase-c", "phase-d", "phase-e")
$orderedPhaseIds = @($phaseOrder + @($phaseMap.Keys | Where-Object { $_ -notin $phaseOrder }))

foreach ($phaseId in $orderedPhaseIds) {
    if (-not $phaseMap.Contains($phaseId)) {
        continue
    }

    $phase = $phaseMap[$phaseId]
    $phaseList += [PSCustomObject]@{
        Id = $phase.Id
        Name = $phase.Name
        Components = $phase.Components.ToArray()
    }
}

$helmReleases = @()
$skippedHelmReleases = @()

foreach ($release in @($helmConfig.Releases)) {
    if (-not $release.K8sDirectory -or $renderedK8sDirectories -notcontains $release.K8sDirectory) {
        continue
    }

    $component = if ($componentCatalog.Contains($release.K8sDirectory)) { $componentCatalog[$release.K8sDirectory] } else { $null }
    $description = if ($null -ne $component) { $component.Description } else { "" }

    if ($release.Enabled -and $release.Chart) {
        $helmReleases += [PSCustomObject]@{
            Name = $release.Name
            Description = $description
            Namespace = $release.Namespace
            Chart = $release.Chart
            RepoName = $release.RepoName
            RepoUrl = $release.RepoUrl
            ValuesPath = $release.ValuesRelativePath
            K8sDirectory = $release.K8sDirectory
        }
    }
    else {
        $skippedHelmReleases += [PSCustomObject]@{
            Name = $release.Name
            K8sDirectory = $release.K8sDirectory
            Reason = if ($release.Notes) { $release.Notes } else { "Release is disabled or missing chart information." }
        }
    }
}

$optionalManifests = @()
foreach ($relativePath in $optionalManifestCatalog.Keys) {
    $bundleRelativePath = Join-Path "k8s" $relativePath
    $fullPath = Join-Path $resolvedBundleRoot $bundleRelativePath
    if (Test-Path -Path $fullPath -PathType Leaf) {
        $optionalManifests += [PSCustomObject]@{
            RelativePath = $bundleRelativePath
            Notes = $optionalManifestCatalog[$relativePath]
        }
    }
}

$bundleManifest = [ordered]@{
    GeneratedAtUtc = [DateTime]::UtcNow.ToString("o")
    Profile = $selection.Profile
    Description = $selection.Description
    Applications = @($selection.Applications)
    DataServices = @($selection.DataServices)
    IncludeJenkins = [bool]$IncludeJenkins
    DockerRegistry = $DockerRegistry
    Version = $Version
    ValuesFileSource = $resolvedValuesFile
    K8sDirectories = @($renderedK8sDirectories)
    ServiceDirectories = @($renderedServiceDirectories)
    Phases = @($phaseList)
    HelmReleases = @($helmReleases)
    SkippedHelmReleases = @($skippedHelmReleases)
    OptionalManifests = @($optionalManifests)
}

$manifestPath = Join-Path $resolvedBundleRoot "bundle-manifest.json"
$bundleManifest | ConvertTo-Json -Depth 10 | Set-Content -Path $manifestPath -NoNewline

$applicationsText = if ($selection.Applications.Count -gt 0) { $selection.Applications -join ", " } else { "none selected" }
$dataServicesText = if ($selection.DataServices.Count -gt 0) { $selection.DataServices -join ", " } else { "none selected" }
$dockerRegistryText = if ($DockerRegistry) { $DockerRegistry } else { "not set" }
$versionText = if ($Version) { $Version } else { "not set" }
$includeJenkinsText = [string]([bool]$IncludeJenkins)

$docLines = @(
    "# Deployment Bundle",
    "",
    ("This bundle was generated for profile " + $selection.Profile + " on " + $bundleManifest.GeneratedAtUtc + "."),
    "",
    "## Summary",
    "",
    ("- Profile: " + $selection.Profile),
    ("- Description: " + $selection.Description),
    ("- Applications: " + $applicationsText),
    ("- Data services: " + $dataServicesText),
    ("- Include Jenkins: " + $includeJenkinsText),
    ("- Docker registry: " + $dockerRegistryText),
    ("- Version: " + $versionText),
    "",
    "## Commands",
    "",
    '```powershell',
    ".\validate-bundle.ps1",
    ".\cluster-bootstrap\status-secrets.ps1",
    ".\apply-manifests.ps1",
    ".\install-helm-components.ps1 -PrepareRepos",
    ".\deploy-bundle.ps1 -PrepareHelmRepos",
    ".\status-bundle.ps1",
    ".\destroy-bundle.ps1",
    '```',
    "",
    "## Planning References",
    "",
    "- `PROFILE_CATALOG.md`: repository-wide profile comparison matrix, recommended use cases, and example preview commands.",
    "- `CLUSTER_BOOTSTRAP.md`: editable namespace and secret bootstrap assets that prepare the cluster before main bundle rollout.",
    "- `CLUSTER_PREFLIGHT.md`: cluster-side namespaces, secrets, storage classes, CRDs, and Helm source expectations for this bundle.",
    "- `CLUSTER_SECRET_PLAN.md`: pre-existing secret requirements, expected keys, and example creation commands for this bundle.",
    "- `VALIDATION_READINESS.md`: current workstation readiness for this bundle, required tools, and recommended validation commands.",
    "- `validate-bundle.ps1`: bundle-local validation helper for bootstrap placeholders, bootstrap status checks, raw manifest dry-runs, and Helm dry-runs.",
    "- `PLATFORM_PLAN.md`: selected Kubernetes directories and rollout phases.",
    "- `PLATFORM_VALUES_PLAN.md`: required platform values, their source templates, and whether they are sensitive.",
    "- `SERVICE_BUILD_PLAN.md`: service image build profiles and wrapper expectations.",
    "- `SERVICE_CONFIG_PLAN.md`: repository-managed JSON and INI templates plus placeholders.",
    "- `SERVICE_DEPENDENCY_PLAN.md`: service prerequisites, compatible in-cluster data services, and peer components.",
    "- `SERVICE_INPUT_PLAN.md`: Jenkins variables, compose variables, values keys, and selected service prerequisites in one summary.",
    "- `SERVICE_RUNTIME_PLAN.md`: compose ports, mounts, and runtime expectations.",
    "- `jenkins\README.md`: bundle-specific Jenkins automation asset summary and next steps.",
    "- `jenkins\JOB_PLAN.md`: Jenkins folder layout, pipeline chain, and parameter defaults for this exact bundle selection.",
    "- `jenkins\job-plan.json`: machine-readable version of the generated Jenkins job plan.",
    "- `jenkins\seed-job-dsl.groovy`: Job DSL output that can create matching Jenkins folders and pipeline jobs after you replace the placeholder repository URL.",
    "- `platform-values.env.example`: filtered platform values example for the selected bundle.",
    "- `service-runtime.env.example`: filtered compose env example for the selected services.",
    ""
)

if ($phaseList.Count -gt 0) {
    $docLines += "## Raw Manifest Phases"
    $docLines += ""
    foreach ($phase in $phaseList) {
        $docLines += ("### " + $phase.Name)
        $docLines += ""
        foreach ($component in @($phase.Components)) {
            $docLines += ("- " + $component.Directory + ": " + $component.Description)
            if ($component.Notes) {
                $docLines += ("  Note: " + $component.Notes)
            }
        }
        $docLines += ""
    }
}

if ($helmReleases.Count -gt 0) {
    $docLines += "## Helm Components"
    $docLines += ""
    foreach ($release in $helmReleases) {
        $docLines += ("- " + $release.Name + ": chart " + $release.Chart + ", namespace " + $release.Namespace + ", values " + $release.ValuesPath)
    }
    $docLines += ""
}

if ($optionalManifests.Count -gt 0) {
    $docLines += "## Optional Follow-up Manifests"
    $docLines += ""
    foreach ($item in $optionalManifests) {
        $docLines += ("- " + $item.RelativePath + ": " + $item.Notes)
    }
    $docLines += ""
}

if ($renderedServiceDirectories.Count -gt 0) {
    $docLines += "## Included Service Configurations"
    $docLines += ""
    foreach ($serviceDirectory in $renderedServiceDirectories) {
        $docLines += ("- " + $serviceDirectory)
    }
    $docLines += ""
}

if ($skippedHelmReleases.Count -gt 0) {
    $docLines += "## Skipped Helm Releases"
    $docLines += ""
    foreach ($release in $skippedHelmReleases) {
        $docLines += ("- " + $release.Name + ": " + $release.Reason)
    }
    $docLines += ""
}

Set-Content -Path (Join-Path $resolvedBundleRoot "DEPLOYMENT_BUNDLE.md") -Value ($docLines -join [Environment]::NewLine) -NoNewline

$applyScript = @'
param(
    [string]$BundleRoot,
    [string[]]$PhaseIds = @(),
    [switch]$DryRun,
    [switch]$IncludeDeferredComponents
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if (-not $PSBoundParameters.ContainsKey("BundleRoot") -or -not $BundleRoot) {
    $BundleRoot = $PSScriptRoot
}

$kubectl = Get-Command kubectl -ErrorAction SilentlyContinue
if ($null -eq $kubectl) {
    throw "kubectl is required to apply bundle manifests."
}

$manifestPath = Join-Path $BundleRoot "bundle-manifest.json"
if (-not (Test-Path -Path $manifestPath -PathType Leaf)) {
    throw "Bundle manifest not found: $manifestPath"
}

$manifest = Get-Content -Path $manifestPath -Raw | ConvertFrom-Json
$phases = @($manifest.Phases)

if ($PhaseIds.Count -gt 0) {
    $requestedPhaseIds = @()
    foreach ($phaseId in $PhaseIds) {
        if (-not $phaseId) {
            continue
        }

        foreach ($item in ($phaseId -split ",")) {
            $trimmed = $item.Trim().ToLowerInvariant()
            if ($trimmed) {
                $requestedPhaseIds += $trimmed
            }
        }
    }

    $phases = @($phases | Where-Object { $requestedPhaseIds -contains $_.Id.ToLowerInvariant() })
}

$skippedDeferred = New-Object System.Collections.Generic.List[object]

foreach ($phase in $phases) {
    Write-Host ("== {0} ==" -f $phase.Name)

    foreach ($component in @($phase.Components)) {
        if ($component.Delivery -eq "deferred-raw" -and -not $IncludeDeferredComponents) {
            $skippedDeferred.Add([PSCustomObject]@{
                Phase = $phase.Name
                Directory = $component.Directory
                Notes = $component.Notes
            }) | Out-Null
            continue
        }

        $targetPath = Join-Path $BundleRoot $component.ApplyPath
        $args = @("apply")
        if ($DryRun) {
            $args += "--dry-run=client"
        }
        $args += @("-f", $targetPath)

        Write-Host ("Applying {0}" -f $component.ApplyPath)
        & kubectl @args
        if ($LASTEXITCODE -ne 0) {
            throw "kubectl apply failed for $($component.ApplyPath)"
        }
    }
}

if ($skippedDeferred.Count -gt 0) {
    Write-Host "Deferred components were skipped. Re-run with -IncludeDeferredComponents after the required controllers are ready."
    $skippedDeferred | Format-Table -AutoSize
}

if (@($manifest.HelmReleases).Count -gt 0) {
    Write-Host "Helm-managed components remain. Run .\install-helm-components.ps1 after raw manifests are ready."
}
'@

$helmInstallScript = @'
param(
    [string]$BundleRoot,
    [string[]]$ReleaseNames = @(),
    [switch]$PrepareRepos,
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if (-not $PSBoundParameters.ContainsKey("BundleRoot") -or -not $BundleRoot) {
    $BundleRoot = $PSScriptRoot
}

$helm = Get-Command helm -ErrorAction SilentlyContinue
if ($null -eq $helm) {
    throw "helm is required to install bundle Helm components."
}

$manifestPath = Join-Path $BundleRoot "bundle-manifest.json"
if (-not (Test-Path -Path $manifestPath -PathType Leaf)) {
    throw "Bundle manifest not found: $manifestPath"
}

$manifest = Get-Content -Path $manifestPath -Raw | ConvertFrom-Json
$releases = @($manifest.HelmReleases)

if ($ReleaseNames.Count -gt 0) {
    $requestedNames = @()
    foreach ($releaseName in $ReleaseNames) {
        if (-not $releaseName) {
            continue
        }

        foreach ($item in ($releaseName -split ",")) {
            $trimmed = $item.Trim().ToLowerInvariant()
            if ($trimmed) {
                $requestedNames += $trimmed
            }
        }
    }

    $releases = @($releases | Where-Object { $requestedNames -contains $_.Name.ToLowerInvariant() })
}

if ($releases.Count -eq 0) {
    Write-Host "No Helm-managed components are included in this bundle."
    return
}

if ($PrepareRepos) {
    $repoMap = @{}
    foreach ($release in $releases) {
        if (-not $release.RepoName -or -not $release.RepoUrl) {
            continue
        }

        $repoKey = "{0}|{1}" -f $release.RepoName, $release.RepoUrl
        if (-not $repoMap.ContainsKey($repoKey)) {
            $repoMap[$repoKey] = [PSCustomObject]@{
                RepoName = $release.RepoName
                RepoUrl = $release.RepoUrl
            }
        }
    }

    foreach ($repo in $repoMap.Values) {
        & helm repo add $repo.RepoName $repo.RepoUrl --force-update
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to add Helm repo $($repo.RepoName)"
        }
    }

    if ($repoMap.Count -gt 0) {
        & helm repo update
        if ($LASTEXITCODE -ne 0) {
            throw "helm repo update failed."
        }
    }
}

foreach ($release in $releases) {
    $valuesPath = Join-Path $BundleRoot $release.ValuesPath
    $args = @(
        "upgrade",
        "--install",
        $release.Name,
        $release.Chart,
        "--namespace",
        $release.Namespace,
        "--create-namespace",
        "-f",
        $valuesPath
    )

    if ($DryRun) {
        $args += @("--dry-run", "--debug")
    }

    Write-Host ("helm {0}" -f ($args -join " "))
    & helm @args
    if ($LASTEXITCODE -ne 0) {
        throw "Helm install failed for release $($release.Name)"
    }
}

if (@($manifest.SkippedHelmReleases).Count -gt 0) {
    Write-Host "Some Helm releases were intentionally skipped:"
    @($manifest.SkippedHelmReleases) | Format-Table -AutoSize
}
'@

$validateScript = @'
param(
    [string]$BundleRoot,
    [switch]$PrepareHelmRepos,
    [switch]$IncludeDeferredComponents,
    [switch]$RequireBootstrapSecretsReady,
    [switch]$RequireBootstrapStatus,
    [switch]$SkipBootstrapPlaceholderCheck,
    [switch]$SkipBootstrapStatus,
    [switch]$SkipRawDryRun,
    [switch]$SkipHelmDryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if (-not $PSBoundParameters.ContainsKey("BundleRoot") -or -not $BundleRoot) {
    $BundleRoot = $PSScriptRoot
}

$manifestPath = Join-Path $BundleRoot "bundle-manifest.json"
if (-not (Test-Path -Path $manifestPath -PathType Leaf)) {
    throw "Bundle manifest not found: $manifestPath"
}

$manifest = Get-Content -Path $manifestPath -Raw | ConvertFrom-Json
$bootstrapCheckScript = Join-Path $BundleRoot "cluster-bootstrap\check-secret-templates.ps1"
$bootstrapStatusScript = Join-Path $BundleRoot "cluster-bootstrap\status-secrets.ps1"
$applyScript = Join-Path $BundleRoot "apply-manifests.ps1"
$helmScript = Join-Path $BundleRoot "install-helm-components.ps1"

if (-not $SkipBootstrapPlaceholderCheck -and (Test-Path -Path $bootstrapCheckScript -PathType Leaf)) {
    Write-Host "== Bootstrap placeholder check =="
    & $bootstrapCheckScript -BundleRoot $BundleRoot -FailOnMatch:$RequireBootstrapSecretsReady
    $bootstrapPlaceholderExitCode = 0
    if (Test-Path Variable:LASTEXITCODE) {
        $bootstrapPlaceholderExitCode = [int]$LASTEXITCODE
    }

    if ($RequireBootstrapSecretsReady -and $bootstrapPlaceholderExitCode -ne 0) {
        throw "Bootstrap secret placeholder validation failed. Update the generated bootstrap secret templates and retry."
    }
}

if (-not $SkipBootstrapStatus -and (Test-Path -Path $bootstrapStatusScript -PathType Leaf)) {
    $kubectl = Get-Command kubectl -ErrorAction SilentlyContinue
    if ($null -eq $kubectl) {
        if ($RequireBootstrapStatus) {
            throw "kubectl is required to enforce bootstrap namespace and secret status checks."
        }

        Write-Warning "kubectl is not installed. Skipping bootstrap namespace and secret status checks."
    }
    else {
        Write-Host "== Bootstrap status =="
        & $bootstrapStatusScript -BundleRoot $BundleRoot -FailOnMissing:$RequireBootstrapStatus
    }
}

if (-not $SkipRawDryRun) {
    if (@($manifest.Phases).Count -eq 0) {
        Write-Host "No raw manifest phases are included in this bundle."
    }
    else {
        $kubectl = Get-Command kubectl -ErrorAction SilentlyContinue
        if ($null -eq $kubectl) {
            Write-Warning "kubectl is not installed. Skipping raw manifest dry-run validation."
        }
        else {
            Write-Host "== Raw manifest dry-run =="
            & $applyScript -BundleRoot $BundleRoot -DryRun -IncludeDeferredComponents:$IncludeDeferredComponents
        }
    }
}

if (-not $SkipHelmDryRun) {
    if (@($manifest.HelmReleases).Count -eq 0) {
        Write-Host "No Helm-managed components are included in this bundle."
    }
    else {
        $helm = Get-Command helm -ErrorAction SilentlyContinue
        if ($null -eq $helm) {
            Write-Warning "helm is not installed. Skipping Helm dry-run validation."
        }
        else {
            Write-Host "== Helm dry-run =="
            & $helmScript -BundleRoot $BundleRoot -PrepareRepos:$PrepareHelmRepos -DryRun
        }
    }
}

Write-Host "Bundle validation helper completed."
'@

$deployScript = @'
param(
    [string]$BundleRoot,
    [string[]]$PhaseIds = @(),
    [switch]$PrepareHelmRepos,
    [switch]$DryRun,
    [switch]$IncludeDeferredComponents,
    [switch]$SkipBootstrapStatusCheck
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if (-not $PSBoundParameters.ContainsKey("BundleRoot") -or -not $BundleRoot) {
    $BundleRoot = $PSScriptRoot
}

$applyScript = Join-Path $BundleRoot "apply-manifests.ps1"
$helmScript = Join-Path $BundleRoot "install-helm-components.ps1"
$bootstrapStatusScript = Join-Path $BundleRoot "cluster-bootstrap\status-secrets.ps1"

if (-not $SkipBootstrapStatusCheck -and (Test-Path -Path $bootstrapStatusScript -PathType Leaf)) {
    Write-Host "Checking bootstrap namespace and secret prerequisites"
    try {
        & $bootstrapStatusScript -BundleRoot $BundleRoot -FailOnMissing
    }
    catch {
        throw ("Bootstrap prerequisites are not ready. Run .\cluster-bootstrap\apply-secrets.ps1 or use -SkipBootstrapStatusCheck to bypass. {0}" -f $_.Exception.Message)
    }
}

& $applyScript `
    -BundleRoot $BundleRoot `
    -PhaseIds $PhaseIds `
    -DryRun:$DryRun `
    -IncludeDeferredComponents:$IncludeDeferredComponents

& $helmScript `
    -BundleRoot $BundleRoot `
    -PrepareRepos:$PrepareHelmRepos `
    -DryRun:$DryRun
'@

$statusScript = @'
param(
    [string]$BundleRoot,
    [string[]]$PhaseIds = @(),
    [string[]]$ReleaseNames = @(),
    [switch]$IncludeDeferredComponents
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if (-not $PSBoundParameters.ContainsKey("BundleRoot") -or -not $BundleRoot) {
    $BundleRoot = $PSScriptRoot
}

$manifestPath = Join-Path $BundleRoot "bundle-manifest.json"
if (-not (Test-Path -Path $manifestPath -PathType Leaf)) {
    throw "Bundle manifest not found: $manifestPath"
}

$manifest = Get-Content -Path $manifestPath -Raw | ConvertFrom-Json
$phases = @($manifest.Phases)
$releases = @($manifest.HelmReleases)

if ($PhaseIds.Count -gt 0) {
    $requestedPhaseIds = @()
    foreach ($phaseId in $PhaseIds) {
        if (-not $phaseId) {
            continue
        }

        foreach ($item in ($phaseId -split ",")) {
            $trimmed = $item.Trim().ToLowerInvariant()
            if ($trimmed) {
                $requestedPhaseIds += $trimmed
            }
        }
    }

    $phases = @($phases | Where-Object { $requestedPhaseIds -contains $_.Id.ToLowerInvariant() })
}

if ($ReleaseNames.Count -gt 0) {
    $requestedReleaseNames = @()
    foreach ($releaseName in $ReleaseNames) {
        if (-not $releaseName) {
            continue
        }

        foreach ($item in ($releaseName -split ",")) {
            $trimmed = $item.Trim().ToLowerInvariant()
            if ($trimmed) {
                $requestedReleaseNames += $trimmed
            }
        }
    }

    $releases = @($releases | Where-Object { $requestedReleaseNames -contains $_.Name.ToLowerInvariant() })
}

$kubectl = Get-Command kubectl -ErrorAction SilentlyContinue
if ($null -eq $kubectl) {
    Write-Warning "kubectl is not installed. Skipping raw manifest status checks."
}
else {
    $bootstrapStatusScript = Join-Path $BundleRoot "cluster-bootstrap\status-secrets.ps1"
    if (Test-Path -Path $bootstrapStatusScript -PathType Leaf) {
        Write-Host "== Bootstrap prerequisites =="
        & $bootstrapStatusScript -BundleRoot $BundleRoot
    }

    foreach ($phase in $phases) {
        Write-Host ("== {0} ==" -f $phase.Name)
        foreach ($component in @($phase.Components)) {
            if ($component.Delivery -eq "deferred-raw" -and -not $IncludeDeferredComponents) {
                Write-Host ("Skipping deferred component {0}" -f $component.Directory)
                continue
            }

            $targetPath = Join-Path $BundleRoot $component.ApplyPath
            Write-Host ("kubectl get -f {0}" -f $component.ApplyPath)
            $output = & kubectl get -f $targetPath 2>&1 | Out-String
            if ($LASTEXITCODE -eq 0) {
                Write-Host $output.TrimEnd()
            }
            else {
                Write-Warning ("Unable to get status for {0}`n{1}" -f $component.ApplyPath, $output.Trim())
            }
        }
    }
}

$helm = Get-Command helm -ErrorAction SilentlyContinue
if ($null -eq $helm) {
    Write-Warning "helm is not installed. Skipping Helm release status checks."
}
else {
    foreach ($release in $releases) {
        Write-Host ("== Helm release: {0} ==" -f $release.Name)
        $output = & helm status $release.Name --namespace $release.Namespace 2>&1 | Out-String
        if ($LASTEXITCODE -eq 0) {
            Write-Host $output.TrimEnd()
        }
        else {
            Write-Warning ("Unable to get Helm status for {0}`n{1}" -f $release.Name, $output.Trim())
        }
    }
}
'@

$destroyScript = @'
param(
    [string]$BundleRoot,
    [string[]]$PhaseIds = @(),
    [string[]]$ReleaseNames = @(),
    [switch]$SkipDeferredComponents,
    [switch]$SkipRaw,
    [switch]$SkipHelm,
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if (-not $PSBoundParameters.ContainsKey("BundleRoot") -or -not $BundleRoot) {
    $BundleRoot = $PSScriptRoot
}

$manifestPath = Join-Path $BundleRoot "bundle-manifest.json"
if (-not (Test-Path -Path $manifestPath -PathType Leaf)) {
    throw "Bundle manifest not found: $manifestPath"
}

$manifest = Get-Content -Path $manifestPath -Raw | ConvertFrom-Json
$phases = @($manifest.Phases)
$releases = @($manifest.HelmReleases)

if ($PhaseIds.Count -gt 0) {
    $requestedPhaseIds = @()
    foreach ($phaseId in $PhaseIds) {
        if (-not $phaseId) {
            continue
        }

        foreach ($item in ($phaseId -split ",")) {
            $trimmed = $item.Trim().ToLowerInvariant()
            if ($trimmed) {
                $requestedPhaseIds += $trimmed
            }
        }
    }

    $phases = @($phases | Where-Object { $requestedPhaseIds -contains $_.Id.ToLowerInvariant() })
}

if ($ReleaseNames.Count -gt 0) {
    $requestedReleaseNames = @()
    foreach ($releaseName in $ReleaseNames) {
        if (-not $releaseName) {
            continue
        }

        foreach ($item in ($releaseName -split ",")) {
            $trimmed = $item.Trim().ToLowerInvariant()
            if ($trimmed) {
                $requestedReleaseNames += $trimmed
            }
        }
    }

    $releases = @($releases | Where-Object { $requestedReleaseNames -contains $_.Name.ToLowerInvariant() })
}

if (-not $SkipRaw) {
    $kubectl = Get-Command kubectl -ErrorAction SilentlyContinue
    if ($null -eq $kubectl) {
        throw "kubectl is required to delete raw bundle manifests."
    }

    $reversedPhases = @($phases)
    [array]::Reverse($reversedPhases)

    foreach ($phase in $reversedPhases) {
        Write-Host ("== Deleting {0} ==" -f $phase.Name)
        $components = @($phase.Components)
        [array]::Reverse($components)

        foreach ($component in $components) {
            if ($component.Delivery -eq "deferred-raw" -and $SkipDeferredComponents) {
                Write-Host ("Skipping deferred component {0}" -f $component.Directory)
                continue
            }

            $targetPath = Join-Path $BundleRoot $component.ApplyPath
            $args = @("delete", "--ignore-not-found=true", "-f", $targetPath)
            if ($DryRun) {
                Write-Host ("kubectl {0}" -f ($args -join " "))
                continue
            }

            Write-Host ("Deleting {0}" -f $component.ApplyPath)
            & kubectl @args
            if ($LASTEXITCODE -ne 0) {
                throw "kubectl delete failed for $($component.ApplyPath)"
            }
        }
    }
}

if (-not $SkipHelm) {
    $helm = Get-Command helm -ErrorAction SilentlyContinue
    if ($null -eq $helm) {
        throw "helm is required to uninstall Helm-managed bundle components."
    }

    $reversedReleases = @($releases)
    [array]::Reverse($reversedReleases)

    foreach ($release in $reversedReleases) {
        if ($DryRun) {
            Write-Host ("helm uninstall {0} --namespace {1}" -f $release.Name, $release.Namespace)
            continue
        }

        & helm status $release.Name --namespace $release.Namespace 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-Warning ("Helm release {0} was not found in namespace {1}" -f $release.Name, $release.Namespace)
            continue
        }

        Write-Host ("Uninstalling Helm release {0}" -f $release.Name)
        & helm uninstall $release.Name --namespace $release.Namespace
        if ($LASTEXITCODE -ne 0) {
            throw "Helm uninstall failed for release $($release.Name)"
        }
    }
}
'@

Set-Content -Path (Join-Path $resolvedBundleRoot "apply-manifests.ps1") -Value $applyScript -NoNewline
Set-Content -Path (Join-Path $resolvedBundleRoot "install-helm-components.ps1") -Value $helmInstallScript -NoNewline
Set-Content -Path (Join-Path $resolvedBundleRoot "validate-bundle.ps1") -Value $validateScript -NoNewline
Set-Content -Path (Join-Path $resolvedBundleRoot "deploy-bundle.ps1") -Value $deployScript -NoNewline
Set-Content -Path (Join-Path $resolvedBundleRoot "status-bundle.ps1") -Value $statusScript -NoNewline
Set-Content -Path (Join-Path $resolvedBundleRoot "destroy-bundle.ps1") -Value $destroyScript -NoNewline

$bundleLeafName = Split-Path -Path $resolvedBundleRoot -Leaf
$jenkinsSelectionName = Get-JenkinsSelectionName -Value $bundleLeafName
$jenkinsAssetRoot = Join-Path $resolvedBundleRoot "jenkins"
$defaultJenkinsArchivePath = $resolvedBundleRoot + ".zip"
$defaultJenkinsPromotionPath = Join-Path (Split-Path -Path $resolvedBundleRoot -Parent) ("{0}-promotion" -f $jenkinsSelectionName)

New-Item -ItemType Directory -Path $jenkinsAssetRoot -Force | Out-Null

& $jenkinsJobPlanScript `
    -RepoRoot $root `
    -SelectionName $jenkinsSelectionName `
    -Profile $Profile `
    -Applications $Applications `
    -DataServices $DataServices `
    -ValuesFile $resolvedValuesFile `
    -DockerRegistry $DockerRegistry `
    -Version $Version `
    -BundleOutputPath $resolvedBundleRoot `
    -ArchivePath $defaultJenkinsArchivePath `
    -PromotionExtractPath $defaultJenkinsPromotionPath `
    -IncludeJenkins:$IncludeJenkins `
    -Format markdown `
    -OutputPath (Join-Path $jenkinsAssetRoot "JOB_PLAN.md")

& $jenkinsJobPlanScript `
    -RepoRoot $root `
    -SelectionName $jenkinsSelectionName `
    -Profile $Profile `
    -Applications $Applications `
    -DataServices $DataServices `
    -ValuesFile $resolvedValuesFile `
    -DockerRegistry $DockerRegistry `
    -Version $Version `
    -BundleOutputPath $resolvedBundleRoot `
    -ArchivePath $defaultJenkinsArchivePath `
    -PromotionExtractPath $defaultJenkinsPromotionPath `
    -IncludeJenkins:$IncludeJenkins `
    -Format json `
    -OutputPath (Join-Path $jenkinsAssetRoot "job-plan.json")

$defaultJenkinsRepoUrl = "https://github.com/k4nul/k8s-platform-template.git"

& $jenkinsJobDslExportScript `
    -RepoRoot $root `
    -SelectionName $jenkinsSelectionName `
    -Profile $Profile `
    -Applications $Applications `
    -DataServices $DataServices `
    -ValuesFile $resolvedValuesFile `
    -DockerRegistry $DockerRegistry `
    -Version $Version `
    -BundleOutputPath $resolvedBundleRoot `
    -ArchivePath $defaultJenkinsArchivePath `
    -PromotionExtractPath $defaultJenkinsPromotionPath `
    -IncludeJenkins:$IncludeJenkins `
    -RepoUrl $defaultJenkinsRepoUrl `
    -OutputPath (Join-Path $jenkinsAssetRoot "seed-job-dsl.groovy")

$jenkinsReadmeLines = @(
    "# Jenkins Automation Assets",
    "",
    "These files were generated for the exact bundle selection in this directory so operators can carry the matching Jenkins setup alongside the deployment bundle.",
    "",
    "## Included Files",
    "",
    "- `JOB_PLAN.md`: bundle-specific Jenkins folder and job plan.",
    "- `job-plan.json`: machine-readable version of the same plan.",
    "- `seed-job-dsl.groovy`: Job DSL Groovy for creating the matching folders and pipeline jobs.",
    "",
    "## Notes",
    "",
    ("- Generated selection name: " + $jenkinsSelectionName),
    ("- Suggested bundle output path: " + $resolvedBundleRoot),
    ("- Suggested bundle archive path: " + $defaultJenkinsArchivePath),
    ("- Suggested promotion extract path: " + $defaultJenkinsPromotionPath),
    ("- Include Jenkins components in bundle selection: " + [string]([bool]$IncludeJenkins)),
    ("- `seed-job-dsl.groovy` is preconfigured with the repository URL `{0}`." -f $defaultJenkinsRepoUrl),
    "- If you fork or mirror this template, re-run `scripts\\export-jenkins-job-dsl.ps1` with your own Git URL and credentials ID before applying the DSL in Jenkins.",
    ""
)

Set-Content -Path (Join-Path $jenkinsAssetRoot "README.md") -Value ($jenkinsReadmeLines -join [Environment]::NewLine) -NoNewline

Write-Host ("Wrote bundle metadata and deployment helpers to {0}" -f $resolvedBundleRoot)
Write-Host ("Wrote Jenkins automation assets to {0}" -f $jenkinsAssetRoot)
