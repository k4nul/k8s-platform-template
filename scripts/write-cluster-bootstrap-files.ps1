param(
    [string]$RepoRoot,

    [Parameter(Mandatory = $true)]
    [string]$BundleRoot,

    [Parameter(Mandatory = $true)]
    [string]$ValuesFile,

    [string]$Profile = "full",
    [string[]]$Applications = @(),
    [string[]]$DataServices = @(),
    [switch]$IncludeJenkins,
    [switch]$IncludeBundleManaged
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "cluster-secret-catalog.ps1")

function Get-NamespaceBootstrapManifest {
    param(
        [string]$Name
    )

    return @(
        "apiVersion: v1",
        "kind: Namespace",
        "metadata:",
        ("  name: " + $Name)
    ) -join [Environment]::NewLine
}

if (-not $PSBoundParameters.ContainsKey("RepoRoot") -or -not $RepoRoot) {
    $RepoRoot = Join-Path $PSScriptRoot ".."
}

$resolvedRepoRoot = (Resolve-Path -Path $RepoRoot).Path
$resolvedBundleRoot = [System.IO.Path]::GetFullPath($BundleRoot)
$resolvedValuesFile = (Resolve-Path -Path $ValuesFile).Path

$planData = Get-ClusterSecretPlanData `
    -RepoRoot $resolvedRepoRoot `
    -ValuesFile $resolvedValuesFile `
    -Profile $Profile `
    -Applications $Applications `
    -DataServices $DataServices `
    -IncludeJenkins:$IncludeJenkins `
    -IncludeBundleManaged:$IncludeBundleManaged

$bootstrapRoot = Join-Path $resolvedBundleRoot "cluster-bootstrap"
$namespacesRoot = Join-Path $bootstrapRoot "namespaces"
$secretsRoot = Join-Path $bootstrapRoot "secrets"

New-Item -ItemType Directory -Path $bootstrapRoot -Force | Out-Null
New-Item -ItemType Directory -Path $namespacesRoot -Force | Out-Null
New-Item -ItemType Directory -Path $secretsRoot -Force | Out-Null

$namespaceEntryMap = @{}
foreach ($namespaceEntry in @($planData.NamespaceEntries)) {
    if ($namespaceEntry.Namespace) {
        $namespaceEntryMap[$namespaceEntry.Namespace] = $namespaceEntry
    }
}

$namespaceManifestMap = @{}
$namespaceManifestEntries = @()
$secretManifestEntries = @()

foreach ($secret in @($planData.Secrets | Sort-Object Namespace, Name)) {
    $namespaceName = [string]$secret.Namespace
    if (-not $namespaceName) {
        continue
    }

    $namespaceRelativePath = ""
    if (-not $namespaceManifestMap.ContainsKey($namespaceName)) {
        $namespaceProvisioning = if ($namespaceEntryMap.ContainsKey($namespaceName)) {
            [string]$namespaceEntryMap[$namespaceName].Provisioning
        }
        else {
            "bootstrap-managed"
        }

        if ($namespaceProvisioning -ne "pre-existing-system") {
            $namespaceFileRelativePath = "cluster-bootstrap\namespaces\{0}.yaml" -f $namespaceName
            $namespaceFilePath = Join-Path $resolvedBundleRoot $namespaceFileRelativePath
            $namespaceDirectory = Split-Path -Path $namespaceFilePath -Parent
            if ($namespaceDirectory) {
                New-Item -ItemType Directory -Path $namespaceDirectory -Force | Out-Null
            }

            Set-Content -Path $namespaceFilePath -Value (Get-NamespaceBootstrapManifest -Name $namespaceName) -NoNewline
            $namespaceManifestMap[$namespaceName] = $namespaceFileRelativePath
            $namespaceManifestEntries += [PSCustomObject]@{
                Name = $namespaceName
                Provisioning = $namespaceProvisioning
                RelativePath = $namespaceFileRelativePath
            }
        }
    }

    if ($namespaceManifestMap.ContainsKey($namespaceName)) {
        $namespaceRelativePath = [string]$namespaceManifestMap[$namespaceName]
    }

    $secretFileRelativePath = "cluster-bootstrap\secrets\{0}\{1}.yaml" -f $namespaceName, $secret.Name
    $secretFilePath = Join-Path $resolvedBundleRoot $secretFileRelativePath
    $secretDirectory = Split-Path -Path $secretFilePath -Parent
    if ($secretDirectory) {
        New-Item -ItemType Directory -Path $secretDirectory -Force | Out-Null
    }

    Set-Content -Path $secretFilePath -Value $secret.ExampleManifest -NoNewline

    $secretManifestEntries += [PSCustomObject]@{
        Namespace = $namespaceName
        Name = [string]$secret.Name
        SecretType = [string]$secret.SecretType
        RequiredBeforeDeploy = [bool]$secret.RequiredBeforeDeploy
        ClusterStatus = [string]$secret.ClusterStatus
        RelativePath = $secretFileRelativePath
        NamespaceRelativePath = $namespaceRelativePath
        RequiredKeys = @($secret.RequiredKeys)
        ValueKeys = @($secret.ValueKeys)
        SourcePaths = @($secret.SourcePaths)
        Description = [string]$secret.Description
        CreationHint = [string]$secret.CreationHint
        ExampleCommand = [string]$secret.ExampleCommand
        CatalogMatched = [bool]$secret.CatalogMatched
    }
}

$bootstrapManifest = [ordered]@{
    GeneratedAtUtc = [DateTime]::UtcNow.ToString("o")
    Profile = $planData.Profile
    Description = $planData.Description
    Applications = @($planData.Applications)
    DataServices = @($planData.DataServices)
    IncludeJenkins = [bool]$planData.IncludeJenkins
    IncludeBundleManaged = [bool]$planData.IncludeBundleManaged
    ValuesFileSource = $planData.ValuesFile
    Namespaces = @($namespaceManifestEntries | Sort-Object Name)
    Secrets = @($secretManifestEntries | Sort-Object Namespace, Name)
}

$bootstrapManifestPath = Join-Path $bootstrapRoot "secret-manifest.json"
$bootstrapManifest | ConvertTo-Json -Depth 10 | Set-Content -Path $bootstrapManifestPath -NoNewline

$applicationsText = if (@($planData.Applications).Count -gt 0) { $planData.Applications -join ", " } else { "none selected" }
$dataServicesText = if (@($planData.DataServices).Count -gt 0) { $planData.DataServices -join ", " } else { "none selected" }
$secretNamesText = if (@($secretManifestEntries).Count -gt 0) {
    @($secretManifestEntries | ForEach-Object { "{0}/{1}" -f $_.Namespace, $_.Name }) -join ", "
}
else {
    "none generated"
}

$docLines = @(
    "# Cluster Bootstrap",
    "",
    'These bootstrap assets help you prepare namespaces and pre-existing secrets before the main bundle is applied. Edit the generated YAML files under `cluster-bootstrap\secrets\` with real values before using the apply helper.',
    "",
    "## Summary",
    "",
    ("- Profile: " + $planData.Profile),
    ("- Description: " + $planData.Description),
    ("- Applications: " + $applicationsText),
    ("- Data services: " + $dataServicesText),
    ("- Include Jenkins: " + [string]([bool]$planData.IncludeJenkins)),
    ("- Include bundle-managed secrets: " + [string]([bool]$planData.IncludeBundleManaged)),
    ("- Values file: " + $planData.ValuesFile),
    ("- Generated namespaces: " + [string]@($namespaceManifestEntries).Count),
    ("- Generated secret templates: " + [string]@($secretManifestEntries).Count),
    ("- Secret list: " + $secretNamesText),
    "",
    "## Recommended Workflow",
    "",
    '```powershell',
    ".\cluster-bootstrap\check-secret-templates.ps1",
    ".\cluster-bootstrap\apply-secrets.ps1",
    ".\cluster-bootstrap\status-secrets.ps1",
    '```',
    "",
    "## Generated Assets",
    "",
    '- `cluster-bootstrap\secret-manifest.json`: machine-readable index of generated namespace and secret bootstrap assets.',
    '- `cluster-bootstrap\check-secret-templates.ps1`: scans the generated secret YAML files for placeholder markers before apply.',
    '- `cluster-bootstrap\apply-secrets.ps1`: optionally creates the required namespaces first, then applies the edited secret YAML files.',
    '- `cluster-bootstrap\status-secrets.ps1`: checks the current cluster for the expected namespaces and secrets.',
    '- `cluster-bootstrap\namespaces\`: namespace YAML files used by the secret apply helper.',
    '- `cluster-bootstrap\secrets\`: editable secret YAML templates grouped by namespace.',
    ""
)

if (@($secretManifestEntries).Count -gt 0) {
    $docLines += "## Secret Templates"
    $docLines += ""
    foreach ($secretEntry in @($secretManifestEntries | Sort-Object Namespace, Name)) {
        $requiredKeysText = if (@($secretEntry.RequiredKeys).Count -gt 0) {
            @($secretEntry.RequiredKeys) -join ", "
        }
        else {
            "inspect source manifests"
        }

        $valueKeysText = if (@($secretEntry.ValueKeys).Count -gt 0) {
            @($secretEntry.ValueKeys) -join ", "
        }
        else {
            "none"
        }

        $sourcePathsText = if (@($secretEntry.SourcePaths).Count -gt 0) {
            @($secretEntry.SourcePaths) -join ", "
        }
        else {
            "none recorded"
        }

        $docLines += ('- `{0}/{1}`: `{2}`' -f $secretEntry.Namespace, $secretEntry.Name, $secretEntry.RelativePath)
        $docLines += ("  Required keys: " + $requiredKeysText)
        $docLines += ("  Source values keys: " + $valueKeysText)
        $docLines += ("  Source manifests: " + $sourcePathsText)
    }
    $docLines += ""
}
else {
    $docLines += "## Secret Templates"
    $docLines += ""
    $docLines += "No pre-existing secret templates were generated for this bundle."
    $docLines += ""
}

$checkScript = @'
param(
    [string]$BundleRoot,
    [switch]$FailOnMatch
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if (-not $PSBoundParameters.ContainsKey("BundleRoot") -or -not $BundleRoot) {
    $BundleRoot = Split-Path -Path $PSScriptRoot -Parent
}

$manifestPath = Join-Path $BundleRoot "cluster-bootstrap\secret-manifest.json"
if (-not (Test-Path -Path $manifestPath -PathType Leaf)) {
    throw "Bootstrap manifest not found: $manifestPath"
}

$manifest = Get-Content -Path $manifestPath -Raw | ConvertFrom-Json
$secretEntries = @($manifest.Secrets)

if ($secretEntries.Count -eq 0) {
    Write-Host "No bootstrap secret templates are included in this bundle."
    return
}

$patterns = @(
    @{ Name = "Example Domain"; Regex = "example\.com" },
    @{ Name = "Example Registry"; Regex = "registry\.example\.com" },
    @{ Name = "Placeholder Password"; Regex = "change-me-[a-z0-9-]+" },
    @{ Name = "Replace Marker"; Regex = "REPLACE_WITH_[A-Z0-9_]+" },
    @{ Name = "Base64 Marker"; Regex = "BASE64_ENCODED_[A-Z0-9_]+" },
    @{ Name = "Htpasswd Marker"; Regex = "\{HTPASSWD_OUTPUT\}" }
)

$matches = New-Object System.Collections.Generic.List[object]
foreach ($entry in $secretEntries) {
    $targetPath = Join-Path $BundleRoot $entry.RelativePath
    if (-not (Test-Path -Path $targetPath -PathType Leaf)) {
        continue
    }

    foreach ($pattern in $patterns) {
        $results = Select-String -Path $targetPath -Pattern $pattern.Regex
        foreach ($result in $results) {
            $matches.Add([PSCustomObject]@{
                Type = $pattern.Name
                File = $entry.RelativePath
                Line = $result.LineNumber
                Text = $result.Line.Trim()
            }) | Out-Null
        }
    }
}

if ($matches.Count -eq 0) {
    Write-Host "No bootstrap secret placeholder markers were found."
    return
}

$matches | Sort-Object File, Line | Format-Table -AutoSize
Write-Warning ("Found {0} bootstrap secret placeholder matches. Update the YAML files before applying them." -f $matches.Count)

if ($FailOnMatch) {
    exit 1
}
'@

$applyScript = @'
param(
    [string]$BundleRoot,
    [string[]]$SecretNames = @(),
    [switch]$SkipNamespaceSetup,
    [switch]$AllowPlaceholders,
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-NormalizedSecretRequests {
    param([string[]]$Values)

    $items = New-Object System.Collections.Generic.List[string]
    foreach ($value in @($Values)) {
        if (-not $value) {
            continue
        }

        foreach ($item in ($value -split ",")) {
            $trimmed = $item.Trim().ToLowerInvariant()
            if ($trimmed) {
                $items.Add($trimmed) | Out-Null
            }
        }
    }

    return @($items | Sort-Object -Unique)
}

function Test-SecretTemplatePlaceholders {
    param(
        [string]$Path
    )

    $patterns = @(
        "example\.com",
        "registry\.example\.com",
        "change-me-[a-z0-9-]+",
        "REPLACE_WITH_[A-Z0-9_]+",
        "BASE64_ENCODED_[A-Z0-9_]+",
        "\{HTPASSWD_OUTPUT\}"
    )

    foreach ($pattern in $patterns) {
        $results = Select-String -Path $Path -Pattern $pattern
        if (@($results).Count -gt 0) {
            return $true
        }
    }

    return $false
}

if (-not $PSBoundParameters.ContainsKey("BundleRoot") -or -not $BundleRoot) {
    $BundleRoot = Split-Path -Path $PSScriptRoot -Parent
}

$kubectl = Get-Command kubectl -ErrorAction SilentlyContinue
if ($null -eq $kubectl) {
    throw "kubectl is required to apply bootstrap namespaces and secrets."
}

$manifestPath = Join-Path $BundleRoot "cluster-bootstrap\secret-manifest.json"
if (-not (Test-Path -Path $manifestPath -PathType Leaf)) {
    throw "Bootstrap manifest not found: $manifestPath"
}

$manifest = Get-Content -Path $manifestPath -Raw | ConvertFrom-Json
$secretEntries = @($manifest.Secrets)
$namespaceEntries = @($manifest.Namespaces)

if ($secretEntries.Count -eq 0) {
    Write-Host "No bootstrap secret templates are included in this bundle."
    return
}

$requestedSecrets = Get-NormalizedSecretRequests -Values $SecretNames
if ($requestedSecrets.Count -gt 0) {
    $secretEntries = @($secretEntries | Where-Object {
        $fullName = ("{0}/{1}" -f $_.Namespace, $_.Name).ToLowerInvariant()
        $requestedSecrets -contains $fullName -or $requestedSecrets -contains $_.Name.ToLowerInvariant()
    })
}

if ($secretEntries.Count -eq 0) {
    Write-Host "No bootstrap secret templates matched the requested names."
    return
}

if (-not $SkipNamespaceSetup) {
    $selectedNamespaceNames = @($secretEntries | Select-Object -ExpandProperty Namespace | Sort-Object -Unique)
    $namespaceEntries = @($namespaceEntries | Where-Object { $selectedNamespaceNames -contains $_.Name })

    foreach ($namespaceEntry in $namespaceEntries) {
        $namespacePath = Join-Path $BundleRoot $namespaceEntry.RelativePath
        $args = @("apply")
        if ($DryRun) {
            $args += "--dry-run=client"
        }
        $args += @("-f", $namespacePath)

        Write-Host ("Ensuring namespace {0}" -f $namespaceEntry.Name)
        & kubectl @args
        if ($LASTEXITCODE -ne 0) {
            throw "kubectl apply failed for namespace bootstrap file $($namespaceEntry.RelativePath)"
        }
    }
}

foreach ($secretEntry in $secretEntries) {
    $secretPath = Join-Path $BundleRoot $secretEntry.RelativePath
    if (-not $AllowPlaceholders -and (Test-SecretTemplatePlaceholders -Path $secretPath)) {
        throw ("Secret template still contains placeholder values: {0}" -f $secretEntry.RelativePath)
    }

    $args = @("apply")
    if ($DryRun) {
        $args += "--dry-run=client"
    }
    $args += @("-f", $secretPath)

    Write-Host ("Applying secret {0}/{1}" -f $secretEntry.Namespace, $secretEntry.Name)
    & kubectl @args
    if ($LASTEXITCODE -ne 0) {
        throw "kubectl apply failed for secret template $($secretEntry.RelativePath)"
    }
}
'@

$statusScript = @'
param(
    [string]$BundleRoot,
    [string[]]$SecretNames = @(),
    [switch]$FailOnMissing
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-NormalizedSecretRequests {
    param([string[]]$Values)

    $items = New-Object System.Collections.Generic.List[string]
    foreach ($value in @($Values)) {
        if (-not $value) {
            continue
        }

        foreach ($item in ($value -split ",")) {
            $trimmed = $item.Trim().ToLowerInvariant()
            if ($trimmed) {
                $items.Add($trimmed) | Out-Null
            }
        }
    }

    return @($items | Sort-Object -Unique)
}

if (-not $PSBoundParameters.ContainsKey("BundleRoot") -or -not $BundleRoot) {
    $BundleRoot = Split-Path -Path $PSScriptRoot -Parent
}

$kubectl = Get-Command kubectl -ErrorAction SilentlyContinue
if ($null -eq $kubectl) {
    throw "kubectl is required to check bootstrap namespace and secret status."
}

$manifestPath = Join-Path $BundleRoot "cluster-bootstrap\secret-manifest.json"
if (-not (Test-Path -Path $manifestPath -PathType Leaf)) {
    throw "Bootstrap manifest not found: $manifestPath"
}

$manifest = Get-Content -Path $manifestPath -Raw | ConvertFrom-Json
$secretEntries = @($manifest.Secrets)
$namespaceEntries = @($manifest.Namespaces)
$requestedSecrets = Get-NormalizedSecretRequests -Values $SecretNames

if ($secretEntries.Count -eq 0) {
    Write-Host "No bootstrap secret templates are included in this bundle."
    return
}

if ($requestedSecrets.Count -gt 0) {
    $secretEntries = @($secretEntries | Where-Object {
        $fullName = ("{0}/{1}" -f $_.Namespace, $_.Name).ToLowerInvariant()
        $requestedSecrets -contains $fullName -or $requestedSecrets -contains $_.Name.ToLowerInvariant()
    })
}

if ($secretEntries.Count -eq 0) {
    Write-Host "No bootstrap secret templates matched the requested names."
    return
}

$selectedNamespaceNames = @($secretEntries | Select-Object -ExpandProperty Namespace | Sort-Object -Unique)
$namespaceEntries = @($namespaceEntries | Where-Object { $selectedNamespaceNames -contains $_.Name })

$report = New-Object System.Collections.Generic.List[object]

foreach ($namespaceEntry in $namespaceEntries) {
    & kubectl get namespace $namespaceEntry.Name -o name 2>&1 | Out-Null
    $namespacePresent = ($LASTEXITCODE -eq 0)

    $matchingSecrets = @($secretEntries | Where-Object { $_.Namespace -eq $namespaceEntry.Name })
    foreach ($secretEntry in $matchingSecrets) {
        & kubectl get secret $secretEntry.Name -n $secretEntry.Namespace -o name 2>&1 | Out-Null
        $secretPresent = ($LASTEXITCODE -eq 0)

        $report.Add([PSCustomObject]@{
            Namespace = $secretEntry.Namespace
            Secret = $secretEntry.Name
            NamespacePresent = $namespacePresent
            SecretPresent = $secretPresent
        }) | Out-Null
    }
}

$remainingSecrets = @($secretEntries | Where-Object { $selectedNamespaceNames -notcontains $_.Namespace })
foreach ($secretEntry in $remainingSecrets) {
    & kubectl get namespace $secretEntry.Namespace -o name 2>&1 | Out-Null
    $namespacePresent = ($LASTEXITCODE -eq 0)

    & kubectl get secret $secretEntry.Name -n $secretEntry.Namespace -o name 2>&1 | Out-Null
    $secretPresent = ($LASTEXITCODE -eq 0)

    $report.Add([PSCustomObject]@{
        Namespace = $secretEntry.Namespace
        Secret = $secretEntry.Name
        NamespacePresent = $namespacePresent
        SecretPresent = $secretPresent
    }) | Out-Null
}

$report | Sort-Object Namespace, Secret | Format-Table -AutoSize

$missing = @($report | Where-Object { -not $_.NamespacePresent -or -not $_.SecretPresent })
if ($missing.Count -eq 0) {
    Write-Host "All bootstrap namespaces and secrets are present."
}
else {
    Write-Warning ("Missing bootstrap prerequisites: {0}" -f $missing.Count)
    if ($FailOnMissing) {
        throw "One or more bootstrap namespaces or secrets are missing."
    }
}
'@

Set-Content -Path (Join-Path $resolvedBundleRoot "CLUSTER_BOOTSTRAP.md") -Value ($docLines -join [Environment]::NewLine) -NoNewline
Set-Content -Path (Join-Path $bootstrapRoot "check-secret-templates.ps1") -Value $checkScript -NoNewline
Set-Content -Path (Join-Path $bootstrapRoot "apply-secrets.ps1") -Value $applyScript -NoNewline
Set-Content -Path (Join-Path $bootstrapRoot "status-secrets.ps1") -Value $statusScript -NoNewline

Write-Host ("Wrote cluster bootstrap assets to {0}" -f $bootstrapRoot)
