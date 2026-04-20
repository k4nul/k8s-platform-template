param(
    [string]$RepoRoot,
    [string[]]$EnvironmentPreset,
    [string]$SelectionName,
    [string]$Profile,
    [string[]]$Applications,
    [string[]]$DataServices,
    [string]$ValuesFile,
    [string]$DockerRegistry,
    [string]$Version,
    [string]$BundleOutputPath,
    [string]$ArchivePath,
    [string]$PromotionExtractPath,
    [string]$JobRoot = "platform",
    [string]$ServiceJobRoot = "services",
    [switch]$IncludeJenkins,
    [switch]$SkipServiceJobs,
    [string]$RepoUrl = "https://github.com/k4nul/k8s-platform-template.git",
    [string]$BranchSpec = "*/main",
    [string]$ScmCredentialsId,
    [bool]$UseLightweightCheckout = $true,
    [string]$OutputPath = "out\jenkins\seed-job-dsl.groovy"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-NormalizedList {
    param(
        [object[]]$Values
    )

    return @(
        @($Values) |
            ForEach-Object { [string]$_ } |
            ForEach-Object { $_ -split "\s*,\s*" } |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ } |
            Sort-Object -Unique
    )
}

function Get-TextList {
    param(
        [object[]]$Values,
        [string]$Empty = "none"
    )

    $normalized = @(Get-NormalizedList -Values $Values)
    if ($normalized.Count -gt 0) {
        return ($normalized -join ", ")
    }

    return $Empty
}

function ConvertTo-GroovyString {
    param(
        [AllowEmptyString()]
        [string]$Value
    )

    if ($null -eq $Value) {
        return "''"
    }

    $escaped = $Value.Replace("\", "\\").Replace("'", "\'").Replace("`r", "").Replace("`n", "\n")
    return ("'{0}'" -f $escaped)
}

function ConvertTo-RelativeScmPath {
    param(
        [string]$Path
    )

    return ([string]$Path).Replace("\", "/")
}

function Get-FolderPathsFromJobPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$JobPath
    )

    $segments = @(
        $JobPath -split "[/\\]+" |
            Where-Object { $_ }
    )

    $folders = New-Object System.Collections.Generic.List[string]
    if ($segments.Count -lt 2) {
        return @()
    }

    for ($index = 0; $index -lt ($segments.Count - 1); $index++) {
        $folders.Add(($segments[0..$index] -join "/")) | Out-Null
    }

    return @($folders.ToArray())
}

function Add-UniqueFolderDescription {
    param(
        [hashtable]$Map,
        [string]$Path,
        [string]$Description,
        [switch]$Replace
    )

    if (-not $Path) {
        return
    }

    if ($Replace -or -not $Map.ContainsKey($Path)) {
        $Map[$Path] = $Description
    }
}

if (-not $PSBoundParameters.ContainsKey("RepoRoot") -or -not $RepoRoot) {
    $RepoRoot = Join-Path $PSScriptRoot ".."
}

$root = (Resolve-Path -Path $RepoRoot).Path
$jobPlanScript = Join-Path $root "scripts\show-jenkins-job-plan.ps1"

$jobPlanArguments = @{
    RepoRoot = $root
    JobRoot = $JobRoot
    ServiceJobRoot = $ServiceJobRoot
    Format = "json"
}

if (@(Get-NormalizedList -Values $EnvironmentPreset).Count -gt 0) {
    $jobPlanArguments["EnvironmentPreset"] = @(Get-NormalizedList -Values $EnvironmentPreset)
}

if ($PSBoundParameters.ContainsKey("SelectionName") -and $SelectionName) {
    $jobPlanArguments["SelectionName"] = $SelectionName
}

if ($PSBoundParameters.ContainsKey("Profile") -and $Profile) {
    $jobPlanArguments["Profile"] = $Profile
}

if (@(Get-NormalizedList -Values $Applications).Count -gt 0) {
    $jobPlanArguments["Applications"] = @(Get-NormalizedList -Values $Applications)
}

if (@(Get-NormalizedList -Values $DataServices).Count -gt 0) {
    $jobPlanArguments["DataServices"] = @(Get-NormalizedList -Values $DataServices)
}

foreach ($optionalName in @("ValuesFile", "DockerRegistry", "Version", "BundleOutputPath", "ArchivePath", "PromotionExtractPath")) {
    if ($PSBoundParameters.ContainsKey($optionalName) -and (Get-Variable -Name $optionalName -ValueOnly)) {
        $jobPlanArguments[$optionalName] = Get-Variable -Name $optionalName -ValueOnly
    }
}

if ($IncludeJenkins) {
    $jobPlanArguments["IncludeJenkins"] = $true
}

if ($SkipServiceJobs) {
    $jobPlanArguments["SkipServiceJobs"] = $true
}

$jobPlanJson = (& $jobPlanScript @jobPlanArguments | Out-String).Trim()
if (-not $jobPlanJson) {
    throw "Jenkins job plan script did not return any JSON output."
}

$jobPlan = $jobPlanJson | ConvertFrom-Json
$selections = @($jobPlan.Selections)
$serviceJobs = @($jobPlan.ServiceJobs)

$folderDescriptions = @{}
$bundleRootPath = (($JobRoot -split "[/\\]+" | Where-Object { $_ }) -join "/")
$serviceRootPath = (($ServiceJobRoot -split "[/\\]+" | Where-Object { $_ }) -join "/")

foreach ($folderPath in @(Get-FolderPathsFromJobPath -JobPath ($bundleRootPath + "/placeholder"))) {
    Add-UniqueFolderDescription -Map $folderDescriptions -Path $folderPath -Description "Generated Jenkins folder for reusable bundle validation, delivery, and promotion jobs."
}

foreach ($folderPath in @(Get-FolderPathsFromJobPath -JobPath ($serviceRootPath + "/placeholder"))) {
    Add-UniqueFolderDescription -Map $folderDescriptions -Path $folderPath -Description "Generated Jenkins folder for reusable service image build jobs."
}

foreach ($selection in $selections) {
    foreach ($job in @($selection.PipelineJobs)) {
        foreach ($folderPath in @(Get-FolderPathsFromJobPath -JobPath $job.Path)) {
            Add-UniqueFolderDescription -Map $folderDescriptions -Path $folderPath -Description "Generated Jenkins folder created from the reusable bundle job topology."
        }
    }

    Add-UniqueFolderDescription `
        -Map $folderDescriptions `
        -Path ([string]$selection.BundleFolderPath) `
        -Description ("Generated bundle job folder for selection '{0}' using profile '{1}'." -f $selection.Name, $selection.Profile) `
        -Replace
}

foreach ($serviceJob in $serviceJobs) {
    foreach ($folderPath in @(Get-FolderPathsFromJobPath -JobPath $serviceJob.Path)) {
        Add-UniqueFolderDescription -Map $folderDescriptions -Path $folderPath -Description "Generated Jenkins folder that groups service image pipeline jobs used by the selected bundle plans."
    }
}

$sortedFolderPaths = @(
    $folderDescriptions.Keys |
        Sort-Object @{ Expression = { ($_ -split "/").Count } }, @{ Expression = { $_ } }
)

$lines = @(
    ("// Generated by scripts/export-jenkins-job-dsl.ps1 on {0}" -f (Get-Date).ToString("s")),
    ("// Repository root: {0}" -f $root),
    ("// Selection count: {0}" -f $selections.Count),
    ("// Service job count: {0}" -f $serviceJobs.Count),
    "",
    ("String repoUrl = {0}" -f (ConvertTo-GroovyString -Value $RepoUrl)),
    ("String branchSpec = {0}" -f (ConvertTo-GroovyString -Value $BranchSpec)),
    ("String scmCredentialsId = {0}" -f (ConvertTo-GroovyString -Value $ScmCredentialsId)),
    ("boolean useLightweightCheckout = {0}" -f $UseLightweightCheckout.ToString().ToLowerInvariant()),
    "",
    "def configureGeneratedPipelineJob = { jobContext, String scriptPath, String descriptionText ->",
    "    jobContext.description(descriptionText)",
    "    jobContext.logRotator {",
    "        numToKeep(30)",
    "    }",
    "    jobContext.definition {",
    "        cpsScm {",
    "            lightweight(useLightweightCheckout)",
    "            scm {",
    "                git {",
    "                    remote {",
    "                        url(repoUrl)",
    "                        if (scmCredentialsId?.trim()) {",
    "                            credentials(scmCredentialsId)",
    "                        }",
    "                    }",
    "                    branch(branchSpec)",
    "                }",
    "            }",
    "            scriptPath(scriptPath)",
    "        }",
    "    }",
    "}",
    ""
)

foreach ($folderPath in $sortedFolderPaths) {
    $lines += ("folder({0}) {{" -f (ConvertTo-GroovyString -Value $folderPath))
    $lines += ("    description({0})" -f (ConvertTo-GroovyString -Value $folderDescriptions[$folderPath]))
    $lines += "}"
    $lines += ""
}

foreach ($selection in $selections) {
    foreach ($job in @($selection.PipelineJobs)) {
        $descriptionLines = @(
            "Generated bundle pipeline job.",
            ("Selection: {0}" -f $selection.Name),
            ("Profile: {0}" -f $selection.Profile),
            ("Applications: {0}" -f (Get-TextList -Values $selection.Applications)),
            ("Data services: {0}" -f (Get-TextList -Values $selection.DataServices)),
            ("Purpose: {0}" -f $job.Purpose),
            ("Recommended trigger: {0}" -f $job.RecommendedTrigger),
            ("Upstream dependencies: {0}" -f (Get-TextList -Values $job.UpstreamDependencies))
        )

        if ($job.ArtifactOutputs) {
            $descriptionLines += ("Artifact outputs: {0}" -f (Get-TextList -Values $job.ArtifactOutputs))
        }

        if ($job.KeyParameters) {
            $descriptionLines += "Key parameters:"
            foreach ($keyParameter in @($job.KeyParameters)) {
                $descriptionLines += ("- {0}" -f $keyParameter)
            }
        }

        $descriptionLines += ("Local command: {0}" -f $job.LocalCommand)

        $lines += ("pipelineJob({0}) {{" -f (ConvertTo-GroovyString -Value ([string]$job.Path)))
        $lines += ("    configureGeneratedPipelineJob(delegate, {0}, {1})" -f `
            (ConvertTo-GroovyString -Value (ConvertTo-RelativeScmPath -Path ([string]$job.Jenkinsfile))), `
            (ConvertTo-GroovyString -Value ($descriptionLines -join "`n")))
        $lines += "}"
        $lines += ""
    }
}

foreach ($serviceJob in $serviceJobs | Sort-Object Name) {
    $descriptionLines = @(
        "Generated service image pipeline job.",
        ("Service: {0}" -f $serviceJob.Name),
        ("Category: {0}" -f $serviceJob.Category),
        ("Image name: {0}" -f $serviceJob.ImageName),
        ("Build tag strategy: {0}" -f $serviceJob.BuildTagStrategy),
        ("Compose update behavior: {0}" -f $serviceJob.ComposeUpdate),
        ("Used by selections: {0}" -f (Get-TextList -Values $serviceJob.UsedBySelections)),
        ("Required environment variables: {0}" -f (Get-TextList -Values $serviceJob.RequiredEnvironmentVariables)),
        ("Optional environment variables: {0}" -f (Get-TextList -Values $serviceJob.OptionalEnvironmentVariables)),
        ("Recommended trigger: {0}" -f $serviceJob.RecommendedTrigger),
        ("Notes: {0}" -f $serviceJob.Notes)
    )

    if ($serviceJob.UpstreamArtifactInputs) {
        $descriptionLines += "Upstream artifact inputs:"
        foreach ($artifactInput in @($serviceJob.UpstreamArtifactInputs)) {
            $descriptionLines += ("- {0}" -f $artifactInput)
        }
    }

    $lines += ("pipelineJob({0}) {{" -f (ConvertTo-GroovyString -Value ([string]$serviceJob.Path)))
    $lines += ("    configureGeneratedPipelineJob(delegate, {0}, {1})" -f `
        (ConvertTo-GroovyString -Value (ConvertTo-RelativeScmPath -Path ([string]$serviceJob.Jenkinsfile))), `
        (ConvertTo-GroovyString -Value ($descriptionLines -join "`n")))
    $lines += "}"
    $lines += ""
}

$document = $lines -join [Environment]::NewLine

$resolvedOutputPath = if ([System.IO.Path]::IsPathRooted($OutputPath)) {
    [System.IO.Path]::GetFullPath($OutputPath)
}
else {
    [System.IO.Path]::GetFullPath((Join-Path $root $OutputPath))
}

$outputDirectory = Split-Path -Path $resolvedOutputPath -Parent
if ($outputDirectory) {
    New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
}

Set-Content -Path $resolvedOutputPath -Value $document -NoNewline
Write-Host ("Wrote Jenkins Job DSL to {0}" -f $resolvedOutputPath)
