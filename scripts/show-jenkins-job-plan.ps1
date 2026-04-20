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
    [ValidateSet("text", "markdown", "json")]
    [string]$Format = "text",
    [string]$OutputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "environment-preset.ps1")
. (Join-Path $PSScriptRoot "platform-catalog.ps1")

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

function Get-SelectionSegment {
    param(
        [AllowEmptyString()]
        [string]$Value
    )

    if (-not $Value) {
        return "custom"
    }

    $normalized = $Value.Trim()
    $normalized = $normalized -replace "[/\\]+", "-"
    $normalized = $normalized -replace "[^A-Za-z0-9._-]+", "-"
    $normalized = $normalized.Trim("-")

    if (-not $normalized) {
        return "custom"
    }

    return $normalized
}

function Get-OptionalString {
    param(
        [hashtable]$Preset,
        [string]$Key,
        [string]$Default = ""
    )

    if ($null -eq $Preset -or -not $Preset.ContainsKey($Key)) {
        return $Default
    }

    return ([string]$Preset[$Key]).Trim()
}

function Get-OptionalBoolean {
    param(
        [hashtable]$Preset,
        [string]$Key,
        [bool]$Default = $false
    )

    if ($null -eq $Preset -or -not $Preset.ContainsKey($Key)) {
        return $Default
    }

    return [bool]$Preset[$Key]
}

function Join-JobPath {
    param(
        [string[]]$Segments
    )

    $parts = New-Object System.Collections.Generic.List[string]
    foreach ($segment in @($Segments)) {
        foreach ($part in @(([string]$segment -split "[\\/]+"))) {
            $trimmed = $part.Trim()
            if ($trimmed) {
                $parts.Add($trimmed) | Out-Null
            }
        }
    }

    return ($parts.ToArray() -join "/")
}

function Format-PowerShellLiteral {
    param(
        [AllowEmptyString()]
        [string]$Value
    )

    if ($null -eq $Value) {
        return "''"
    }

    if ($Value -match "^[A-Za-z0-9_./:\\-]+$") {
        return $Value
    }

    return ("'{0}'" -f $Value.Replace("'", "''"))
}

function Add-CommandArgument {
    param(
        [System.Collections.Generic.List[string]]$Parts,
        [string]$Name,
        [AllowEmptyString()]
        [string]$Value
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return
    }

    $Parts.Add($Name) | Out-Null
    $Parts.Add((Format-PowerShellLiteral -Value $Value)) | Out-Null
}

function Add-CommandListArgument {
    param(
        [System.Collections.Generic.List[string]]$Parts,
        [string]$Name,
        [string[]]$Values
    )

    $normalized = @(Get-NormalizedList -Values $Values)
    if ($normalized.Count -eq 0) {
        return
    }

    $Parts.Add($Name) | Out-Null
    $Parts.Add((Format-PowerShellLiteral -Value ($normalized -join ","))) | Out-Null
}

function Add-CommandSwitch {
    param(
        [System.Collections.Generic.List[string]]$Parts,
        [string]$Name,
        [bool]$Enabled
    )

    if ($Enabled) {
        $Parts.Add($Name) | Out-Null
    }
}

function Get-SelectionCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ScriptName,

        [Parameter(Mandatory = $true)]
        [pscustomobject]$Selection
    )

    $parts = [System.Collections.Generic.List[string]]::new()
    $parts.Add((".\scripts\{0}" -f $ScriptName)) | Out-Null

    if ($Selection.UsesPreset) {
        Add-CommandArgument -Parts $parts -Name "-EnvironmentPreset" -Value $Selection.Name
    }

    switch ($ScriptName) {
        "invoke-repository-validation.ps1" {
            Add-CommandArgument -Parts $parts -Name "-Profile" -Value $Selection.Profile
            Add-CommandListArgument -Parts $parts -Name "-Applications" -Values @($Selection.Applications)
            Add-CommandListArgument -Parts $parts -Name "-DataServices" -Values @($Selection.DataServices)
            Add-CommandArgument -Parts $parts -Name "-ValuesFile" -Value $Selection.ValuesFile
            Add-CommandArgument -Parts $parts -Name "-DockerRegistry" -Value $Selection.DockerRegistry
            Add-CommandArgument -Parts $parts -Name "-Version" -Value $Selection.Version
            Add-CommandSwitch -Parts $parts -Name "-IncludeJenkins" -Enabled ([bool]$Selection.IncludeJenkins)
        }
        "invoke-bundle-delivery.ps1" {
            Add-CommandArgument -Parts $parts -Name "-Profile" -Value $Selection.Profile
            Add-CommandListArgument -Parts $parts -Name "-Applications" -Values @($Selection.Applications)
            Add-CommandListArgument -Parts $parts -Name "-DataServices" -Values @($Selection.DataServices)
            Add-CommandArgument -Parts $parts -Name "-ValuesFile" -Value $Selection.ValuesFile
            Add-CommandArgument -Parts $parts -Name "-DockerRegistry" -Value $Selection.DockerRegistry
            Add-CommandArgument -Parts $parts -Name "-Version" -Value $Selection.Version
            Add-CommandArgument -Parts $parts -Name "-OutputPath" -Value $Selection.BundleOutputPath
            Add-CommandArgument -Parts $parts -Name "-ArchivePath" -Value $Selection.ArchivePath
            Add-CommandSwitch -Parts $parts -Name "-IncludeJenkins" -Enabled ([bool]$Selection.IncludeJenkins)
        }
        "invoke-bundle-promotion.ps1" {
            Add-CommandArgument -Parts $parts -Name "-ArchivePath" -Value $Selection.ArchivePath
            Add-CommandArgument -Parts $parts -Name "-ExtractPath" -Value $Selection.PromotionExtractPath
        }
    }

    return ($parts.ToArray() -join " ")
}

function Get-KeyParameterList {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Phase,

        [Parameter(Mandatory = $true)]
        [pscustomobject]$Selection
    )

    switch ($Phase) {
        "validation" {
            $parameters = @()
            if ($Selection.UsesPreset) {
                $parameters += ("VALIDATION_ENVIRONMENT_PRESET={0}" -f $Selection.Name)
            }
            $parameters += ("VALIDATION_PROFILE={0}" -f $Selection.Profile)
            $parameters += ("VALIDATION_APPLICATIONS={0}" -f (Get-TextList -Values $Selection.Applications))
            $parameters += ("VALIDATION_DATA_SERVICES={0}" -f (Get-TextList -Values $Selection.DataServices))
            $parameters += ("VALIDATION_VALUES_FILE={0}" -f $Selection.ValuesFile)
            if ($Selection.DockerRegistry) {
                $parameters += ("VALIDATION_DOCKER_REGISTRY={0}" -f $Selection.DockerRegistry)
            }
            if ([bool]$Selection.IncludeJenkins) {
                $parameters += "VALIDATION_INCLUDE_JENKINS=true"
            }
            $parameters += ("VALIDATION_REQUIRE_BOOTSTRAP_SECRETS_READY=false")
            return @($parameters)
        }
        "delivery" {
            $parameters = @()
            if ($Selection.UsesPreset) {
                $parameters += ("BUNDLE_ENVIRONMENT_PRESET={0}" -f $Selection.Name)
            }
            $parameters += ("BUNDLE_PROFILE={0}" -f $Selection.Profile)
            $parameters += ("BUNDLE_APPLICATIONS={0}" -f (Get-TextList -Values $Selection.Applications))
            $parameters += ("BUNDLE_DATA_SERVICES={0}" -f (Get-TextList -Values $Selection.DataServices))
            $parameters += ("BUNDLE_VALUES_FILE={0}" -f $Selection.ValuesFile)
            $parameters += ("BUNDLE_OUTPUT_PATH={0}" -f $Selection.BundleOutputPath)
            $parameters += ("BUNDLE_ARCHIVE_PATH={0}" -f $Selection.ArchivePath)
            if ($Selection.DockerRegistry) {
                $parameters += ("BUNDLE_DOCKER_REGISTRY={0}" -f $Selection.DockerRegistry)
            }
            if ([bool]$Selection.IncludeJenkins) {
                $parameters += "BUNDLE_INCLUDE_JENKINS=true"
            }
            $parameters += ("BUNDLE_DEPLOY=false")
            return @($parameters)
        }
        "promotion" {
            $parameters = @()
            if ($Selection.UsesPreset) {
                $parameters += ("PROMOTION_ENVIRONMENT_PRESET={0}" -f $Selection.Name)
            }
            $parameters += ("PROMOTION_ARCHIVE_PATH={0}" -f $Selection.ArchivePath)
            $parameters += ("PROMOTION_EXTRACT_PATH={0}" -f $Selection.PromotionExtractPath)
            $parameters += ("PROMOTION_DEPLOY=false")
            $parameters += ("PROMOTION_DEPLOY_DRY_RUN=true")
            return @($parameters)
        }
    }

    return @()
}

if (-not $PSBoundParameters.ContainsKey("RepoRoot") -or -not $RepoRoot) {
    $RepoRoot = Join-Path $PSScriptRoot ".."
}

$root = (Resolve-Path -Path $RepoRoot).Path
$presetDirectory = Join-Path $root "config\environments"
$servicePipelineCatalogPath = Join-Path $root "config\service-pipelines.psd1"
$servicePipelineCatalog = Import-PowerShellDataFile -Path $servicePipelineCatalogPath
$serviceCatalogIndex = @{}
foreach ($service in @($servicePipelineCatalog.Services)) {
    $serviceCatalogIndex[[string]$service.Name] = $service
}

$hasDirectSelection =
    $PSBoundParameters.ContainsKey("Profile") -or
    $PSBoundParameters.ContainsKey("Applications") -or
    $PSBoundParameters.ContainsKey("DataServices") -or
    $PSBoundParameters.ContainsKey("ValuesFile") -or
    $PSBoundParameters.ContainsKey("DockerRegistry") -or
    $PSBoundParameters.ContainsKey("Version") -or
    $PSBoundParameters.ContainsKey("BundleOutputPath") -or
    $PSBoundParameters.ContainsKey("ArchivePath") -or
    $PSBoundParameters.ContainsKey("PromotionExtractPath") -or
    $PSBoundParameters.ContainsKey("IncludeJenkins")

$selectedPresetNames = @()
if ($PSBoundParameters.ContainsKey("EnvironmentPreset") -and @(Get-NormalizedList -Values $EnvironmentPreset).Count -gt 0) {
    $selectedPresetNames = @(Get-NormalizedList -Values $EnvironmentPreset)
}
elseif ($hasDirectSelection) {
    $selectedPresetNames = @("custom")
}
else {
    $selectedPresetNames = @(
        Get-ChildItem -Path $presetDirectory -File -Filter "*.psd1" |
            Sort-Object BaseName |
            Select-Object -ExpandProperty BaseName
    )
}

$selectionPlans = New-Object System.Collections.Generic.List[object]

foreach ($presetName in @($selectedPresetNames)) {
    $presetData = $null
    $usesPreset = $false
    if ($presetName -ne "custom") {
        $presetData = Get-EnvironmentPresetData -RepoRoot $root -EnvironmentPreset $presetName
        $usesPreset = $true
    }

    $selectionProfile = $Profile
    Set-ValueFromEnvironmentPreset -Preset $presetData -BoundParameters $PSBoundParameters -Key "Profile" -Target ([ref]$selectionProfile)
    if (-not $selectionProfile) {
        $selectionProfile = "web-platform"
    }

    $selectionApplications = @(Get-NormalizedList -Values $Applications)
    Set-ValueFromEnvironmentPreset -Preset $presetData -BoundParameters $PSBoundParameters -Key "Applications" -Target ([ref]$selectionApplications) -AsList
    if ($selectionApplications.Count -eq 0) {
        $selectionApplications = @("nginx-web", "httpbin", "whoami")
    }
    $selectionApplications = @(Get-NormalizedList -Values $selectionApplications)

    $selectionDataServices = @(Get-NormalizedList -Values $DataServices)
    Set-ValueFromEnvironmentPreset -Preset $presetData -BoundParameters $PSBoundParameters -Key "DataServices" -Target ([ref]$selectionDataServices) -AsList
    if ($selectionDataServices.Count -eq 0) {
        $selectionDataServices = @("redis")
    }
    $selectionDataServices = @(Get-NormalizedList -Values $selectionDataServices)

    $selectionValuesFile = $ValuesFile
    Set-ValueFromEnvironmentPreset -Preset $presetData -BoundParameters $PSBoundParameters -Key "ValuesFile" -Target ([ref]$selectionValuesFile)
    if (-not $selectionValuesFile) {
        $selectionValuesFile = "config\platform-values.env.example"
    }

    $selectionDockerRegistry = $DockerRegistry
    Set-ValueFromEnvironmentPreset -Preset $presetData -BoundParameters $PSBoundParameters -Key "DockerRegistry" -Target ([ref]$selectionDockerRegistry)

    $selectionVersion = $Version
    Set-ValueFromEnvironmentPreset -Preset $presetData -BoundParameters $PSBoundParameters -Key "Version" -Target ([ref]$selectionVersion)
    if (-not $selectionVersion) {
        $selectionVersion = "0.0.0-ci"
    }

    $selectionBundleOutputPath = $BundleOutputPath
    Set-ValueFromEnvironmentPreset -Preset $presetData -BoundParameters $PSBoundParameters -Key "OutputPath" -Target ([ref]$selectionBundleOutputPath)
    if (-not $selectionBundleOutputPath) {
        $selectionBundleOutputPath = ("out\delivery\{0}" -f $selectionProfile)
    }

    $selectionArchivePath = $ArchivePath
    Set-ValueFromEnvironmentPreset -Preset $presetData -BoundParameters $PSBoundParameters -Key "ArchivePath" -Target ([ref]$selectionArchivePath)
    if (-not $selectionArchivePath) {
        $selectionArchivePath = ("out\delivery\{0}.zip" -f $selectionProfile)
    }

    $selectionPromotionExtractPath = $PromotionExtractPath
    Set-ValueFromEnvironmentPreset -Preset $presetData -BoundParameters $PSBoundParameters -Key "PromotionExtractPath" -Target ([ref]$selectionPromotionExtractPath)
    if (-not $selectionPromotionExtractPath) {
        Set-ValueFromEnvironmentPreset -Preset $presetData -BoundParameters $PSBoundParameters -Key "ExtractPath" -Target ([ref]$selectionPromotionExtractPath)
    }
    if (-not $selectionPromotionExtractPath) {
        $selectionPromotionExtractPath = ("out\promotion\{0}" -f $selectionProfile)
    }

    $includeJenkins = [bool]$IncludeJenkins
    Set-ValueFromEnvironmentPreset -Preset $presetData -BoundParameters $PSBoundParameters -Key "IncludeJenkins" -Target ([ref]$includeJenkins) -AsSwitch

    $selectionName = if ($usesPreset) { $presetName } else { Get-SelectionSegment -Value $SelectionName }
    $selectionDescription = if ($usesPreset) {
        Get-OptionalString -Preset $presetData -Key "Description" -Default ""
    }
    else {
        "Custom Jenkins job plan assembled from explicit bundle selection parameters."
    }

    $resolvedPlatformSelection = Resolve-PlatformSelection `
        -Profile $selectionProfile `
        -Applications $selectionApplications `
        -DataServices $selectionDataServices `
        -IncludeJenkins:$includeJenkins

    $bundleFolderPath = Join-JobPath -Segments @($JobRoot, $selectionName)

    $selection = [PSCustomObject]@{
        Name = $selectionName
        UsesPreset = $usesPreset
        Description = $selectionDescription
        Profile = $selectionProfile
        Applications = @($selectionApplications)
        DataServices = @($selectionDataServices)
        ValuesFile = $selectionValuesFile
        DockerRegistry = $selectionDockerRegistry
        Version = $selectionVersion
        BundleOutputPath = $selectionBundleOutputPath
        ServiceDirectories = @($resolvedPlatformSelection.ServiceDirectories)
        IncludeJenkins = [bool]$includeJenkins
        ArchivePath = $selectionArchivePath
        PromotionExtractPath = $selectionPromotionExtractPath
        BundleFolderPath = $bundleFolderPath
        ValidationJobPath = Join-JobPath -Segments @($JobRoot, $selectionName, "repository-validation")
        DeliveryJobPath = Join-JobPath -Segments @($JobRoot, $selectionName, "bundle-delivery")
        PromotionJobPath = Join-JobPath -Segments @($JobRoot, $selectionName, "bundle-promotion")
    }

    $validationCommand = Get-SelectionCommand -ScriptName "invoke-repository-validation.ps1" -Selection $selection
    $deliveryCommand = Get-SelectionCommand -ScriptName "invoke-bundle-delivery.ps1" -Selection $selection
    $promotionCommand = Get-SelectionCommand -ScriptName "invoke-bundle-promotion.ps1" -Selection $selection

    $pipelineJobs = @(
        [PSCustomObject]@{
            Name = "repository-validation"
            Path = $selection.ValidationJobPath
            Jenkinsfile = "jenkins\repository-validation.Jenkinsfile"
            Purpose = "Validate repository structure, workstation readiness, and rendered bundle safety."
            RecommendedTrigger = "Pull request validation, protected branch changes, or scheduled drift checks."
            UpstreamDependencies = @()
            ArtifactOutputs = @(
                "Validation logs and optional existing bundle re-validation results."
            )
            KeyParameters = @(Get-KeyParameterList -Phase "validation" -Selection $selection)
            LocalCommand = $validationCommand
        },
        [PSCustomObject]@{
            Name = "bundle-delivery"
            Path = $selection.DeliveryJobPath
            Jenkinsfile = "jenkins\bundle-delivery.Jenkinsfile"
            Purpose = "Render a bundle, validate it, archive it, and optionally run a dry-run deployment."
            RecommendedTrigger = "Manual release packaging, protected branch release flow, or downstream after validation."
            UpstreamDependencies = @($selection.ValidationJobPath)
            ArtifactOutputs = @(
                ("Bundle archive: {0}" -f $selection.ArchivePath),
                ("Rendered bundle directory: {0}" -f $selection.BundleOutputPath)
            )
            KeyParameters = @(Get-KeyParameterList -Phase "delivery" -Selection $selection)
            LocalCommand = $deliveryCommand
        },
        [PSCustomObject]@{
            Name = "bundle-promotion"
            Path = $selection.PromotionJobPath
            Jenkinsfile = "jenkins\bundle-promotion.Jenkinsfile"
            Purpose = "Unpack a published bundle, validate it again, and optionally deploy it after approval."
            RecommendedTrigger = "Manual approval gate or downstream from delivery only after artifact publication is confirmed."
            UpstreamDependencies = @($selection.DeliveryJobPath)
            ArtifactOutputs = @(
                ("Promoted extraction path: {0}" -f $selection.PromotionExtractPath)
            )
            KeyParameters = @(Get-KeyParameterList -Phase "promotion" -Selection $selection)
            LocalCommand = $promotionCommand
        }
    )

    $selectionPlans.Add([PSCustomObject]@{
        Name = $selection.Name
        Description = $selection.Description
        UsesPreset = $selection.UsesPreset
        Profile = $selection.Profile
        Applications = @($selection.Applications)
        DataServices = @($selection.DataServices)
        ValuesFile = $selection.ValuesFile
        DockerRegistry = $selection.DockerRegistry
        Version = $selection.Version
        BundleOutputPath = $selection.BundleOutputPath
        ServiceDirectories = @($selection.ServiceDirectories)
        IncludeJenkins = [bool]$selection.IncludeJenkins
        ArchivePath = $selection.ArchivePath
        PromotionExtractPath = $selection.PromotionExtractPath
        BundleFolderPath = $selection.BundleFolderPath
        ValidationJobPath = $selection.ValidationJobPath
        DeliveryJobPath = $selection.DeliveryJobPath
        PromotionJobPath = $selection.PromotionJobPath
        ValidationCommand = $validationCommand
        DeliveryCommand = $deliveryCommand
        PromotionCommand = $promotionCommand
        PipelineJobs = @($pipelineJobs)
        RecommendedFlow = @(
            "Run any optional service-specific automation you keep locally before or alongside bundle validation.",
            ("Validate selection in {0}." -f $selection.ValidationJobPath),
            ("Render and archive the bundle in {0}." -f $selection.DeliveryJobPath),
            "Insert manual approval or change-management review before promotion deployment.",
            ("Promote and optionally deploy from {0}." -f $selection.PromotionJobPath)
        )
    }) | Out-Null
}

$serviceJobs = @()
if (-not $SkipServiceJobs) {
    $serviceUsage = @{}
    foreach ($selection in @($selectionPlans.ToArray())) {
        foreach ($serviceDirectory in @($selection.ServiceDirectories)) {
            if (-not $serviceUsage.ContainsKey($serviceDirectory)) {
                $serviceUsage[$serviceDirectory] = New-Object System.Collections.Generic.List[string]
            }

            if (-not $serviceUsage[$serviceDirectory].Contains($selection.Name)) {
                $serviceUsage[$serviceDirectory].Add($selection.Name) | Out-Null
            }
        }
    }

    foreach ($serviceName in @($serviceUsage.Keys | Sort-Object)) {
        $serviceDefinition = $null
        if ($serviceCatalogIndex.ContainsKey($serviceName)) {
            $serviceDefinition = $serviceCatalogIndex[$serviceName]
        }

        if ($null -ne $serviceDefinition -and [bool]$serviceDefinition.HasJenkinsfile) {
            $requiredEnvVars = @()
            if ($serviceDefinition.PSObject.Properties.Name -contains "RequiresRegistry" -and [bool]$serviceDefinition.RequiresRegistry) {
                $requiredEnvVars += "DOCKER_REGISTRY"
            }
            if ([bool]$serviceDefinition.RequiresMode) {
                $requiredEnvVars += "MODE"
            }

            $serviceJobs += [PSCustomObject]@{
                Name = [string]$serviceDefinition.Name
                Path = Join-JobPath -Segments @($ServiceJobRoot, $serviceDefinition.Name)
                Jenkinsfile = ("services\{0}\Jenkinsfile" -f $serviceDefinition.Name)
                Category = [string]$serviceDefinition.Category
                ImageName = [string]$serviceDefinition.ImageName
                BuildTagStrategy = [string]$serviceDefinition.BuildTagStrategy
                ComposeUpdate = [string]$serviceDefinition.ComposeUpdate
                RequiredEnvironmentVariables = @($requiredEnvVars)
                OptionalEnvironmentVariables = @(Get-NormalizedList -Values $serviceDefinition.OptionalEnvVars)
                UpstreamArtifactInputs = @($serviceDefinition.ArtifactInputs)
                UsedBySelections = @($serviceUsage[$serviceName].ToArray() | Sort-Object -Unique)
                Notes = [string]$serviceDefinition.Notes
                RecommendedTrigger = "Source changes in the service workspace or successful completion of the upstream artifact jobs described below."
            }
        }
    }
}

$mermaidLines = @(
    "flowchart LR"
)

if ($serviceJobs.Count -gt 0) {
    $mermaidLines += '    SharedServices["Selected service image jobs"]'
}

for ($index = 0; $index -lt $selectionPlans.Count; $index++) {
    $selection = $selectionPlans[$index]
    $validationNode = "Validation{0}" -f $index
    $deliveryNode = "Delivery{0}" -f $index
    $approvalNode = "Approval{0}" -f $index
    $promotionNode = "Promotion{0}" -f $index

    $mermaidLines += ('    {0}["{1}"]' -f $validationNode, $selection.ValidationJobPath)
    $mermaidLines += ('    {0}["{1}"]' -f $deliveryNode, $selection.DeliveryJobPath)
    $mermaidLines += ('    {0}["Manual approval"]' -f $approvalNode)
    $mermaidLines += ('    {0}["{1}"]' -f $promotionNode, $selection.PromotionJobPath)
    if ($serviceJobs.Count -gt 0) {
        $mermaidLines += ('    SharedServices --> {0}' -f $validationNode)
    }
    $mermaidLines += ('    {0} --> {1}' -f $validationNode, $deliveryNode)
    $mermaidLines += ('    {0} --> {1}' -f $deliveryNode, $approvalNode)
    $mermaidLines += ('    {0} --> {1}' -f $approvalNode, $promotionNode)
}

$generatedAt = (Get-Date).ToString("s")

switch ($Format) {
    "json" {
        $document = ([ordered]@{
            GeneratedAt = $generatedAt
            RepoRoot = $root
            JobRoot = (Join-JobPath -Segments @($JobRoot))
            ServiceJobRoot = (Join-JobPath -Segments @($ServiceJobRoot))
            SelectionCount = $selectionPlans.Count
            ServiceJobCount = $serviceJobs.Count
            Selections = @($selectionPlans.ToArray())
            ServiceJobs = @($serviceJobs)
            Mermaid = ($mermaidLines -join [Environment]::NewLine)
        } | ConvertTo-Json -Depth 10)
    }
    "markdown" {
        $lines = @(
            "# Jenkins Job Plan",
            "",
            "## Summary",
            "",
            ("- Repository root: " + $root),
            ('- Bundle job root: `' + (Join-JobPath -Segments @($JobRoot)) + '`'),
            ('- Service job root: `' + (Join-JobPath -Segments @($ServiceJobRoot)) + '`'),
            ("- Bundle selection count: " + [string]$selectionPlans.Count),
            ("- Shared service job count: " + [string]$serviceJobs.Count),
            ""
        )

        if ($selectionPlans.Count -gt 0) {
            $lines += "## Bundle Job Matrix"
            $lines += ""
            $lines += "| Selection | Profile | Applications | Data Services | Validation Job | Delivery Job | Promotion Job |"
            $lines += "| --- | --- | --- | --- | --- | --- | --- |"
            foreach ($selection in @($selectionPlans.ToArray())) {
                $lines += ('| {0} | {1} | {2} | {3} | `{4}` | `{5}` | `{6}` |' -f $selection.Name, $selection.Profile, (Get-TextList -Values $selection.Applications), (Get-TextList -Values $selection.DataServices), $selection.ValidationJobPath, $selection.DeliveryJobPath, $selection.PromotionJobPath)
            }

            $lines += ""
            $lines += "## Recommended Flow"
            $lines += ""
            $lines += '```mermaid'
            $lines += $mermaidLines
            $lines += '```'
            $lines += ""
            $lines += "## Bundle Job Details"
            $lines += ""

            foreach ($selection in @($selectionPlans.ToArray())) {
                $lines += ("### " + $selection.Name)
                $lines += ""
                $lines += ("- Description: " + $selection.Description)
                $lines += ("- Profile: " + $selection.Profile)
                $lines += ("- Applications: " + (Get-TextList -Values $selection.Applications))
                $lines += ("- Data services: " + (Get-TextList -Values $selection.DataServices))
                $lines += ("- Values file: " + $selection.ValuesFile)
                $lines += ("- Docker registry: " + $selection.DockerRegistry)
                $lines += ("- Version: " + $selection.Version)
                $lines += ("- Include Jenkins components: " + [string]([bool]$selection.IncludeJenkins))
                $lines += ("- Delivery output path: " + $selection.BundleOutputPath)
                $lines += ("- Archive path: " + $selection.ArchivePath)
                $lines += ("- Promotion extract path: " + $selection.PromotionExtractPath)
                $lines += ""

                foreach ($job in @($selection.PipelineJobs)) {
                    $lines += ("#### " + $job.Name)
                    $lines += ""
                    $lines += ('- Jenkins path: `' + $job.Path + '`')
                    $lines += ('- Jenkinsfile: `' + $job.Jenkinsfile + '`')
                    $lines += ("- Purpose: " + $job.Purpose)
                    $lines += ("- Recommended trigger: " + $job.RecommendedTrigger)
                    $lines += ('- Local command: `' + $job.LocalCommand + '`')
                    $lines += ("- Upstream dependencies: " + (Get-TextList -Values $job.UpstreamDependencies))
                    $lines += ("- Artifact outputs: " + (Get-TextList -Values $job.ArtifactOutputs))
                    $lines += ("- Key parameters: " + (Get-TextList -Values $job.KeyParameters))
                    $lines += ""
                }
            }
        }

        if ($serviceJobs.Count -gt 0) {
            $lines += "## Shared Service Jobs"
            $lines += ""
            $lines += "| Job | Category | Image | Build Tag | Used By | Required Env Vars |"
            $lines += "| --- | --- | --- | --- | --- | --- |"
            foreach ($service in @($serviceJobs | Sort-Object Name)) {
                $lines += ('| `{0}` | {1} | {2} | {3} | {4} | {5} |' -f $service.Path, $service.Category, $service.ImageName, $service.BuildTagStrategy, (Get-TextList -Values $service.UsedBySelections), (Get-TextList -Values $service.RequiredEnvironmentVariables))
            }

            $lines += ""
            $lines += 'Review `services/<service>/Jenkinsfile` together with `scripts/show-service-pipeline-plan.ps1` when you need the per-service artifact inputs and optional environment variables before creating those jobs.'
            $lines += ""
        }

        $document = $lines -join [Environment]::NewLine
    }
    default {
        $lines = @(
            "Jenkins Job Plan",
            "================",
            ("Repository root: " + $root),
            ("Bundle job root: " + (Join-JobPath -Segments @($JobRoot))),
            ("Service job root: " + (Join-JobPath -Segments @($ServiceJobRoot))),
            ("Bundle selection count: " + [string]$selectionPlans.Count),
            ("Shared service job count: " + [string]$serviceJobs.Count),
            ""
        )

        foreach ($selection in @($selectionPlans.ToArray())) {
            $lines += ($selection.Name + " [" + $selection.Profile + "]")
            $lines += ("  Description: " + $selection.Description)
            $lines += ("  Applications: " + (Get-TextList -Values $selection.Applications))
            $lines += ("  Data services: " + (Get-TextList -Values $selection.DataServices))
            $lines += ("  Values file: " + $selection.ValuesFile)
            $lines += ("  Archive path: " + $selection.ArchivePath)
            $lines += ("  Promotion extract path: " + $selection.PromotionExtractPath)
            foreach ($job in @($selection.PipelineJobs)) {
                $lines += ("  " + $job.Name + ": " + $job.Path)
                $lines += ("    Jenkinsfile: " + $job.Jenkinsfile)
                $lines += ("    Trigger: " + $job.RecommendedTrigger)
                $lines += ("    Upstream dependencies: " + (Get-TextList -Values $job.UpstreamDependencies))
                $lines += ("    Artifact outputs: " + (Get-TextList -Values $job.ArtifactOutputs))
                $lines += ("    Key parameters: " + (Get-TextList -Values $job.KeyParameters))
                $lines += ("    Local command: " + $job.LocalCommand)
            }
            foreach ($flowStep in @($selection.RecommendedFlow)) {
                $lines += ("  Flow: " + $flowStep)
            }
            $lines += ""
        }

        if ($serviceJobs.Count -gt 0) {
            $lines += "Shared service jobs"
            foreach ($service in @($serviceJobs | Sort-Object Name)) {
                $lines += ("- " + $service.Path + " [" + $service.Category + "]")
                $lines += ("  Jenkinsfile: " + $service.Jenkinsfile)
                $lines += ("  Required env vars: " + (Get-TextList -Values $service.RequiredEnvironmentVariables))
                $lines += ("  Optional env vars: " + (Get-TextList -Values $service.OptionalEnvironmentVariables))
                $lines += ("  Used by selections: " + (Get-TextList -Values $service.UsedBySelections))
                foreach ($artifactInput in @($service.UpstreamArtifactInputs)) {
                    $lines += ("  Upstream artifact input: " + $artifactInput)
                }
                $lines += ("  Notes: " + $service.Notes)
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
    Write-Host ("Wrote Jenkins job plan to {0}" -f $resolvedOutputPath)
}
else {
    Write-Output $document
}
