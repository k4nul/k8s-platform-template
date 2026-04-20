param(
    [string]$RepoRoot,
    [string]$ValuesFile,
    [string]$Profile = "full",
    [string[]]$Applications = @(),
    [string[]]$DataServices = @(),
    [switch]$IncludeJenkins,
    [switch]$IncludeBundleManaged,
    [ValidateSet("text", "markdown", "json")]
    [string]$Format = "text",
    [string]$OutputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "cluster-secret-catalog.ps1")

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

if (-not $PSBoundParameters.ContainsKey("RepoRoot") -or -not $RepoRoot) {
    $RepoRoot = Join-Path $PSScriptRoot ".."
}

if (-not $PSBoundParameters.ContainsKey("ValuesFile") -or -not $ValuesFile) {
    $ValuesFile = Join-Path $PSScriptRoot "..\config\platform-values.env.example"
}

$planData = Get-ClusterSecretPlanData `
    -RepoRoot $RepoRoot `
    -ValuesFile $ValuesFile `
    -Profile $Profile `
    -Applications $Applications `
    -DataServices $DataServices `
    -IncludeJenkins:$IncludeJenkins `
    -IncludeBundleManaged:$IncludeBundleManaged

$secrets = @($planData.Secrets)
$requiredSecrets = @($secrets | Where-Object { $_.RequiredBeforeDeploy })
$presentSecrets = @($requiredSecrets | Where-Object { $_.ClusterStatus -eq "present" })
$missingSecrets = @($requiredSecrets | Where-Object { $_.ClusterStatus -eq "missing" })
$unknownSecrets = @($requiredSecrets | Where-Object { $_.ClusterStatus -eq "unknown" })
$applicationsText = Get-TextList -Values $planData.Applications
$dataServicesText = Get-TextList -Values $planData.DataServices
$secretNamesText = Get-TextList -Values @($requiredSecrets | ForEach-Object { "{0}/{1}" -f $_.Namespace, $_.Name })
$currentContextText = if ($planData.ClusterAccess.CurrentContext) { $planData.ClusterAccess.CurrentContext } else { "none" }
$secretCount = @($secrets).Count
$requiredSecretCount = @($requiredSecrets).Count
$presentSecretCount = @($presentSecrets).Count
$missingSecretCount = @($missingSecrets).Count
$unknownSecretCount = @($unknownSecrets).Count

switch ($Format) {
    "json" {
        $document = ([ordered]@{
            GeneratedAt = (Get-Date).ToString("s")
            RepoRoot = $planData.RepoRoot
            ValuesFile = $planData.ValuesFile
            Profile = $planData.Profile
            Description = $planData.Description
            Applications = @($planData.Applications)
            DataServices = @($planData.DataServices)
            IncludeJenkins = [bool]$planData.IncludeJenkins
            IncludeBundleManaged = [bool]$planData.IncludeBundleManaged
            PreflightStatus = $planData.PreflightStatus
            ClusterAccess = $planData.ClusterAccess
            SecretCount = $secretCount
            RequiredSecretCount = $requiredSecretCount
            PresentSecretCount = $presentSecretCount
            MissingSecretCount = $missingSecretCount
            UnknownSecretCount = $unknownSecretCount
            Secrets = @($secrets)
        } | ConvertTo-Json -Depth 10)
    }
    "markdown" {
        $lines = @(
            "# Cluster Secret Plan",
            "",
            "This report focuses on secrets referenced by the selected bundle. By default it lists only the secrets that should exist before deployment. Re-run it on the target cluster before rollout.",
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
            ("- Cluster preflight status: " + $planData.PreflightStatus),
            ("- Current kubectl context: " + $currentContextText),
            ("- Required pre-existing secrets: " + $secretNamesText),
            ("- Present on current cluster: " + [string]$presentSecretCount),
            ("- Missing on current cluster: " + [string]$missingSecretCount),
            ("- Unknown on current cluster: " + [string]$unknownSecretCount),
            ""
        )

        if ($secretCount -eq 0) {
            $lines += "## Result"
            $lines += ""
            $lines += "No secrets matched the current selection."
        }
        else {
            $lines += "## Secret Matrix"
            $lines += ""
            $lines += "| Namespace | Secret | Type | Required Before Deploy | Cluster Status | Required Keys | Sources |"
            $lines += "| --- | --- | --- | --- | --- | --- | --- |"
            foreach ($entry in $secrets) {
                $requiredKeysText = Get-TextList -Values $entry.RequiredKeys
                $sourcePathsText = Get-TextList -Values $entry.SourcePaths
                $lines += ("| {0} | {1} | {2} | {3} | {4} | {5} | {6} |" -f $entry.Namespace, $entry.Name, $entry.SecretType, [string]$entry.RequiredBeforeDeploy, $entry.ClusterStatus, $requiredKeysText, $sourcePathsText)
            }

            foreach ($entry in $secrets) {
                $lines += ""
                $lines += ("## Secret: {0}/{1}" -f $entry.Namespace, $entry.Name)
                $lines += ""
                $lines += ("- Secret type: " + $entry.SecretType)
                $lines += ("- Required before deploy: " + [string]$entry.RequiredBeforeDeploy)
                $lines += ("- Cluster status: " + $entry.ClusterStatus)
                $lines += ("- Description: " + $entry.Description)
                $lines += ("- Required keys: " + (Get-TextList -Values $entry.RequiredKeys))
                $lines += ("- Source values keys: " + (Get-TextList -Values $entry.ValueKeys))
                $lines += ("- Sources: " + (Get-TextList -Values $entry.SourcePaths))
                $lines += ("- Catalog matched: " + [string]$entry.CatalogMatched)
                $lines += ("- Creation hint: " + $entry.CreationHint)
                $lines += ""
                $lines += "### Example Command"
                $lines += ""
                $lines += '```powershell'
                $lines += $entry.ExampleCommand
                $lines += '```'
                $lines += ""
                $lines += "### Example Manifest"
                $lines += ""
                $lines += '```yaml'
                $lines += $entry.ExampleManifest
                $lines += '```'
            }
        }

        $document = $lines -join [Environment]::NewLine
    }
    default {
        $lines = @(
            "Cluster Secret Plan",
            "===================",
            ("Profile: " + $planData.Profile),
            ("Description: " + $planData.Description),
            ("Applications: " + $applicationsText),
            ("Data services: " + $dataServicesText),
            ("Include Jenkins: " + [string]([bool]$planData.IncludeJenkins)),
            ("Include bundle-managed secrets: " + [string]([bool]$planData.IncludeBundleManaged)),
            ("Values file: " + $planData.ValuesFile),
            ("Cluster preflight status: " + $planData.PreflightStatus),
            ("Current kubectl context: " + $currentContextText),
            ("Required pre-existing secrets: " + $secretNamesText),
            ("Present on current cluster: " + [string]$presentSecretCount),
            ("Missing on current cluster: " + [string]$missingSecretCount),
            ("Unknown on current cluster: " + [string]$unknownSecretCount)
        )

        if ($secretCount -eq 0) {
            $lines += ""
            $lines += "No secrets matched the current selection."
        }
        else {
            foreach ($entry in $secrets) {
                $lines += ""
                $lines += ("- {0}/{1}: type={2}, required-before-deploy={3}, cluster-status={4}" -f $entry.Namespace, $entry.Name, $entry.SecretType, [string]$entry.RequiredBeforeDeploy, $entry.ClusterStatus)
                $lines += ("  Required keys: " + (Get-TextList -Values $entry.RequiredKeys))
                $lines += ("  Source values keys: " + (Get-TextList -Values $entry.ValueKeys))
                $lines += ("  Sources: " + (Get-TextList -Values $entry.SourcePaths))
                $lines += ("  Creation hint: " + $entry.CreationHint)
                $lines += ("  Example command: " + $entry.ExampleCommand)
            }
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
    Write-Host ("Wrote cluster secret plan to {0}" -f $resolvedOutputPath)
}
else {
    Write-Output $document
}
