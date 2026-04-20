param(
    [string]$RepoRoot,
    [string]$InputRoot,
    [string]$HelmConfigFile,
    [string]$Profile = "full",
    [string[]]$Applications = @(),
    [string[]]$DataServices = @(),
    [switch]$IncludeJenkins,
    [switch]$PrepareRepos,
    [switch]$Strict
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "platform-catalog.ps1")

if (-not $PSBoundParameters.ContainsKey("RepoRoot") -or -not $RepoRoot) {
    $RepoRoot = Join-Path $PSScriptRoot ".."
}

if (-not $PSBoundParameters.ContainsKey("InputRoot") -or -not $InputRoot) {
    $InputRoot = $RepoRoot
}

if (-not $PSBoundParameters.ContainsKey("HelmConfigFile") -or -not $HelmConfigFile) {
    $HelmConfigFile = Join-Path $PSScriptRoot "..\config\helm-releases.psd1"
}

$helm = Get-Command helm -ErrorAction SilentlyContinue
if ($null -eq $helm) {
    Write-Warning "helm is not installed. Skipping Helm values validation."
    if ($Strict) {
        throw "helm is required for Helm values validation."
    }

    return
}

$resolvedRepoRoot = (Resolve-Path -Path $RepoRoot).Path
$resolvedInputRoot = (Resolve-Path -Path $InputRoot).Path
$resolvedConfig = (Resolve-Path -Path $HelmConfigFile).Path
$helmConfig = Import-PowerShellDataFile -Path $resolvedConfig
$selection = Resolve-PlatformSelection -Profile $Profile -Applications $Applications -DataServices $DataServices -IncludeJenkins:$IncludeJenkins

$selectedDirectories = @()
if (-not $selection.IncludeAllK8s) {
    $selectedDirectories = @($selection.K8sDirectories)
}

$releases = @($helmConfig.Releases | Where-Object {
    $_.Enabled -and $_.ValuesRelativePath -and $_.Chart -and (
        $selection.IncludeAllK8s -or $_.K8sDirectory -in $selectedDirectories
    )
})

$skipped = New-Object System.Collections.Generic.List[object]
$validated = New-Object System.Collections.Generic.List[object]
$failed = New-Object System.Collections.Generic.List[object]

if ($PrepareRepos) {
    $repoMap = @{}
    foreach ($release in $releases) {
        if (-not $release.RepoName -or -not $release.RepoUrl) {
            continue
        }

        $repoKey = "{0}|{1}" -f $release.RepoName, $release.RepoUrl
        if (-not $repoMap.ContainsKey($repoKey)) {
            $repoMap[$repoKey] = [PSCustomObject]@{
                Name = $release.Name
                RepoName = $release.RepoName
                RepoUrl = $release.RepoUrl
            }
        }
    }

    $repoEntries = @($repoMap.Values)

    foreach ($repoEntry in $repoEntries) {
        & helm repo add $repoEntry.RepoName $repoEntry.RepoUrl --force-update 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) {
            $failed.Add([PSCustomObject]@{
                Release = $repoEntry.Name
                ValuesFile = ""
                Message = "Failed to add Helm repo $($repoEntry.RepoName) from $($repoEntry.RepoUrl)"
            }) | Out-Null
        }
    }

    if ($failed.Count -eq 0 -and $repoEntries.Count -gt 0) {
        & helm repo update 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "helm repo update failed. Continuing with existing repo cache."
        }
    }
}

foreach ($release in $releases) {
    $valuesPath = Join-Path $resolvedInputRoot $release.ValuesRelativePath
    if (-not (Test-Path -Path $valuesPath -PathType Leaf)) {
        $failed.Add([PSCustomObject]@{
            Release = $release.Name
            ValuesFile = $valuesPath
            Message = "Values file not found."
        }) | Out-Null
        continue
    }

    $output = & helm template $release.Name $release.Chart --namespace $release.Namespace -f $valuesPath 2>&1 | Out-String
    if ($LASTEXITCODE -eq 0) {
        $validated.Add([PSCustomObject]@{
            Release = $release.Name
            ValuesFile = $valuesPath
            Chart = $release.Chart
        }) | Out-Null
    }
    else {
        $failed.Add([PSCustomObject]@{
            Release = $release.Name
            ValuesFile = $valuesPath
            Message = $output.Trim()
        }) | Out-Null
    }
}

foreach ($release in @($helmConfig.Releases | Where-Object { -not $_.Enabled -or -not $_.Chart })) {
    if (-not $selection.IncludeAllK8s -and $_.K8sDirectory -notin $selectedDirectories) {
        continue
    }

    $notes = if ($_.Notes) { $_.Notes } else { "Release is disabled or missing chart information." }
    $skipped.Add([PSCustomObject]@{
        Release = $_.Name
        Reason = $notes
    }) | Out-Null
}

Write-Host ("Validated Helm releases: {0}" -f $validated.Count)

if ($skipped.Count -gt 0) {
    Write-Host ("Skipped Helm releases: {0}" -f $skipped.Count)
    $skipped | Format-Table -AutoSize
}

if ($failed.Count -gt 0) {
    Write-Host ("Failed Helm releases: {0}" -f $failed.Count)
    $failed | Format-Table -AutoSize
    throw "Helm values validation failed."
}

Write-Host "Helm values validation completed successfully."
