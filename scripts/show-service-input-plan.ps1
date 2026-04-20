param(
    [string]$RepoRoot,
    [string]$Profile = "full",
    [string[]]$Applications = @(),
    [string[]]$DataServices = @(),
    [switch]$IncludeJenkins,
    [string]$ValuesFile,
    [string]$RuntimeEnvFile,
    [ValidateSet("text", "markdown", "json")]
    [string]$Format = "text",
    [string]$OutputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "platform-catalog.ps1")

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

function Get-EffectiveDataServices {
    param(
        [string[]]$K8sDirectories,
        [pscustomobject]$Selection,
        [System.Collections.IDictionary]$DataServiceCatalog
    )

    $effectiveDataServices = New-Object System.Collections.Generic.List[string]
    foreach ($serviceName in @($DataServiceCatalog.Keys | Sort-Object)) {
        if ($Selection.DataServices -contains $serviceName -or $K8sDirectories -contains $DataServiceCatalog[$serviceName]) {
            $effectiveDataServices.Add($serviceName) | Out-Null
        }
    }

    return @($effectiveDataServices | Sort-Object -Unique)
}

function Get-EnvFileKeys {
    param(
        [string]$Path
    )

    $keys = New-Object System.Collections.Generic.List[string]
    foreach ($line in Get-Content -Path $Path) {
        $trimmedLine = $line.Trim()
        if (-not $trimmedLine -or $trimmedLine.StartsWith("#")) {
            continue
        }

        $delimiterIndex = $trimmedLine.IndexOf("=")
        if ($delimiterIndex -lt 1) {
            continue
        }

        $keys.Add($trimmedLine.Substring(0, $delimiterIndex).Trim()) | Out-Null
    }

    return @($keys | Sort-Object -Unique)
}

function Get-TextList {
    param(
        [object[]]$Values
    )

    if (@($Values).Count -gt 0) {
        return (@($Values) -join ", ")
    }

    return "none"
}

function Get-ValueOrNone {
    param(
        [string]$Value
    )

    if ($Value) {
        return $Value
    }

    return "none"
}

function Get-CatalogMap {
    param(
        [object[]]$Services
    )

    $map = [ordered]@{}
    foreach ($service in @($Services | Sort-Object { $_.Name })) {
        $map[$service.Name] = $service
    }

    return $map
}

function Get-ObjectPropertyArray {
    param(
        [object]$Object,
        [string]$PropertyName
    )

    if ($null -eq $Object) {
        return @()
    }

    if ($Object.PSObject.Properties.Name -contains $PropertyName) {
        return @($Object.$PropertyName)
    }

    return @()
}

function Get-ObjectPropertyString {
    param(
        [object]$Object,
        [string]$PropertyName
    )

    if ($null -eq $Object) {
        return ""
    }

    if ($Object.PSObject.Properties.Name -contains $PropertyName -and $Object.$PropertyName) {
        return [string]$Object.$PropertyName
    }

    return ""
}

if (-not $PSBoundParameters.ContainsKey("RepoRoot") -or -not $RepoRoot) {
    $RepoRoot = Join-Path $PSScriptRoot ".."
}

if (-not $PSBoundParameters.ContainsKey("ValuesFile") -or -not $ValuesFile) {
    $ValuesFile = Join-Path $PSScriptRoot "..\config\platform-values.env.example"
}

if (-not $PSBoundParameters.ContainsKey("RuntimeEnvFile") -or -not $RuntimeEnvFile) {
    $RuntimeEnvFile = Join-Path $PSScriptRoot "..\config\service-runtime.env.example"
}

$root = (Resolve-Path -Path $RepoRoot).Path
$resolvedValuesFile = (Resolve-Path -Path $ValuesFile).Path
$resolvedRuntimeEnvFile = (Resolve-Path -Path $RuntimeEnvFile).Path

$selection = Resolve-PlatformSelection -Profile $Profile -Applications $Applications -DataServices $DataServices -IncludeJenkins:$IncludeJenkins
$effectiveServiceDirectories = Get-EffectiveServiceDirectories -Root $root -Selection $selection
$effectiveK8sDirectories = Get-EffectiveK8sDirectories -Root $root -Selection $selection
$dataServiceCatalog = Get-PlatformDataServiceCatalog
$effectiveDataServices = Get-EffectiveDataServices -K8sDirectories $effectiveK8sDirectories -Selection $selection -DataServiceCatalog $dataServiceCatalog
$valuesFileKeys = Get-EnvFileKeys -Path $resolvedValuesFile
$runtimeEnvKeys = Get-EnvFileKeys -Path $resolvedRuntimeEnvFile

$pipelineCatalog = Import-PowerShellDataFile -Path (Join-Path $root "config\service-pipelines.psd1")
$runtimeCatalog = Import-PowerShellDataFile -Path (Join-Path $root "config\service-runtime-bindings.psd1")
$configCatalog = Import-PowerShellDataFile -Path (Join-Path $root "config\service-config-artifacts.psd1")
$dependencyCatalog = Import-PowerShellDataFile -Path (Join-Path $root "config\service-dependencies.psd1")

$pipelineMap = Get-CatalogMap -Services $pipelineCatalog.Services
$runtimeMap = Get-CatalogMap -Services $runtimeCatalog.Services
$configMap = Get-CatalogMap -Services $configCatalog.Services
$dependencyMap = Get-CatalogMap -Services $dependencyCatalog.Services

$jenkinsVariableOrder = @(
    "DOCKER_REGISTRY",
    "MODE",
    "BUILD_PROJECT",
    "CACHE",
    "SSHKEY_FILTER",
    "SOURCE_PROJECT"
)
$jenkinsVariableCatalog = [ordered]@{
    "DOCKER_REGISTRY" = "Required registry host for Jenkins image push steps and compose-based update flows."
    "MODE" = "Required for mode-aware services that publish test or release tags and rename mode-specific config files."
    "BUILD_PROJECT" = "Optional override for the upstream artifact job when it differs from the Jenkins job name."
    "CACHE" = "Optional toggle that allows cached Docker builds on services that support it."
    "SSHKEY_FILTER" = "Optional override for certificate or SSH artifact filters used with the sshkey job."
    "SOURCE_PROJECT" = "Optional variable reserved for teams that later add custom bootstrap or packaging jobs."
}

$jenkinsVariableMap = [ordered]@{}
foreach ($variableName in $jenkinsVariableOrder) {
    $jenkinsVariableMap[$variableName] = [ordered]@{
        Name = $variableName
        Description = $jenkinsVariableCatalog[$variableName]
        RequiredBy = New-Object System.Collections.Generic.List[string]
        OptionalBy = New-Object System.Collections.Generic.List[string]
    }
}

$platformValueMap = [ordered]@{}
$serviceRecords = @()

foreach ($serviceName in $effectiveServiceDirectories) {
    $pipeline = if ($pipelineMap.Contains($serviceName)) { $pipelineMap[$serviceName] } else { $null }
    $runtime = if ($runtimeMap.Contains($serviceName)) { $runtimeMap[$serviceName] } else { $null }
    $config = if ($configMap.Contains($serviceName)) { $configMap[$serviceName] } else { $null }
    $dependency = if ($dependencyMap.Contains($serviceName)) { $dependencyMap[$serviceName] } else { $null }

    $requiredJenkinsVars = New-Object System.Collections.Generic.List[string]
    if ($null -ne $pipeline) {
        if ($pipeline.PSObject.Properties.Name -contains "RequiresRegistry" -and [bool]$pipeline.RequiresRegistry) {
            $requiredJenkinsVars.Add("DOCKER_REGISTRY") | Out-Null
        }
        if ([bool]$pipeline.RequiresMode) {
            $requiredJenkinsVars.Add("MODE") | Out-Null
        }
        foreach ($variableName in @(Get-ObjectPropertyArray -Object $pipeline -PropertyName "RequiredEnvVars")) {
            if ($requiredJenkinsVars -notcontains $variableName) {
                $requiredJenkinsVars.Add($variableName) | Out-Null
            }
        }
    }

    $optionalJenkinsVars = @(Get-ObjectPropertyArray -Object $pipeline -PropertyName "OptionalEnvVars" | Sort-Object -Unique)
    $composeRequiredEnvVars = @(Get-ObjectPropertyArray -Object $runtime -PropertyName "RequiredEnvVars" | Sort-Object -Unique)
    $configArtifacts = @(Get-ObjectPropertyArray -Object $config -PropertyName "ConfigArtifacts")
    $platformValueKeys = @(
        $configArtifacts |
            ForEach-Object { @($_.PlaceholderTokens) } |
            Sort-Object -Unique
    )
    $missingPlatformValueKeys = @($platformValueKeys | Where-Object { $valuesFileKeys -notcontains $_ })
    $missingComposeEnvVars = @($composeRequiredEnvVars | Where-Object { $runtimeEnvKeys -notcontains $_ })
    $requiredK8sDirectories = if ($null -ne $dependency) { @($dependency.RequiredK8sDirectories | Sort-Object -Unique) } else { @() }
    $missingRequiredK8sDirectories = @($requiredK8sDirectories | Where-Object { $effectiveK8sDirectories -notcontains $_ })
    $recommendedK8sDirectories = if ($null -ne $dependency) { @($dependency.RecommendedK8sDirectories | Sort-Object -Unique) } else { @() }
    $missingRecommendedK8sDirectories = @($recommendedK8sDirectories | Where-Object { $effectiveK8sDirectories -notcontains $_ })
    $compatibleDataServices = if ($null -ne $dependency) { @($dependency.CompatibleDataServices | Sort-Object -Unique) } else { @() }
    $selectedCompatibleDataServices = @($compatibleDataServices | Where-Object { $effectiveDataServices -contains $_ })
    $relatedApplications = if ($null -ne $dependency) { @($dependency.RelatedApplications | Sort-Object -Unique) } else { @() }
    $selectedRelatedApplications = @($relatedApplications | Where-Object { $effectiveServiceDirectories -contains $_ })
    $configArtifactFiles = @($configArtifacts | ForEach-Object { $_.SourceFile } | Sort-Object -Unique)

    foreach ($variableName in @($requiredJenkinsVars | Sort-Object -Unique)) {
        if ($jenkinsVariableMap.Contains($variableName) -and $jenkinsVariableMap[$variableName].RequiredBy -notcontains $serviceName) {
            $jenkinsVariableMap[$variableName].RequiredBy.Add($serviceName) | Out-Null
        }
    }

    foreach ($variableName in @($optionalJenkinsVars)) {
        if ($jenkinsVariableMap.Contains($variableName) -and $jenkinsVariableMap[$variableName].OptionalBy -notcontains $serviceName) {
            $jenkinsVariableMap[$variableName].OptionalBy.Add($serviceName) | Out-Null
        }
    }

    foreach ($artifact in $configArtifacts) {
        foreach ($token in @($artifact.PlaceholderTokens | Sort-Object -Unique)) {
            if (-not $platformValueMap.Contains($token)) {
                $platformValueMap[$token] = [ordered]@{
                    Name = $token
                    UsedByServices = New-Object System.Collections.Generic.List[string]
                    UsedByArtifacts = New-Object System.Collections.Generic.List[string]
                    PresentInValuesFile = [bool]($valuesFileKeys -contains $token)
                }
            }

            if ($platformValueMap[$token].UsedByServices -notcontains $serviceName) {
                $platformValueMap[$token].UsedByServices.Add($serviceName) | Out-Null
            }

            $artifactReference = "{0}/{1}" -f $serviceName, $artifact.SourceFile
            if ($platformValueMap[$token].UsedByArtifacts -notcontains $artifactReference) {
                $platformValueMap[$token].UsedByArtifacts.Add($artifactReference) | Out-Null
            }
        }
    }

    $serviceRecords += [PSCustomObject]@{
        Name = $serviceName
        JenkinsRequiredEnvVars = @($requiredJenkinsVars | Sort-Object -Unique)
        JenkinsOptionalEnvVars = @($optionalJenkinsVars)
        ComposeRequiredEnvVars = @($composeRequiredEnvVars)
        MissingComposeEnvVars = @($missingComposeEnvVars)
        ConfigArtifactFiles = @($configArtifactFiles)
        PlatformValueKeys = @($platformValueKeys)
        MissingPlatformValueKeys = @($missingPlatformValueKeys)
        RequiredK8sDirectories = @($requiredK8sDirectories)
        MissingRequiredK8sDirectories = @($missingRequiredK8sDirectories)
        RecommendedK8sDirectories = @($recommendedK8sDirectories)
        MissingRecommendedK8sDirectories = @($missingRecommendedK8sDirectories)
        CompatibleDataServices = @($compatibleDataServices)
        SelectedCompatibleDataServices = @($selectedCompatibleDataServices)
        RelatedApplications = @($relatedApplications)
        SelectedRelatedApplications = @($selectedRelatedApplications)
        PipelineNotes = Get-ObjectPropertyString -Object $pipeline -PropertyName "Notes"
        RuntimeNotes = Get-ObjectPropertyString -Object $runtime -PropertyName "Notes"
        DependencyNotes = Get-ObjectPropertyString -Object $dependency -PropertyName "Notes"
    }
}

$jenkinsVariableEntries = @()
foreach ($variableName in $jenkinsVariableOrder) {
    $entry = $jenkinsVariableMap[$variableName]
    if ($entry.RequiredBy.Count -eq 0 -and $entry.OptionalBy.Count -eq 0) {
        continue
    }

    $jenkinsVariableEntries += [PSCustomObject]@{
        Name = $entry.Name
        Description = $entry.Description
        RequiredBy = @($entry.RequiredBy | Sort-Object)
        OptionalBy = @($entry.OptionalBy | Sort-Object)
    }
}

$runtimeVariableOrder = if ($runtimeCatalog.ContainsKey("VariableOrder")) {
    @($runtimeCatalog.VariableOrder)
}
else {
    @($runtimeCatalog.Variables.Keys | Sort-Object)
}

$composeVariableEntries = @()
foreach ($variableName in $runtimeVariableOrder) {
    $usedBy = @(
        $serviceRecords |
            Where-Object { @($_.ComposeRequiredEnvVars) -contains $variableName } |
            ForEach-Object { $_.Name }
    )
    if ($usedBy.Count -eq 0) {
        continue
    }

    $composeVariableEntries += [PSCustomObject]@{
        Name = $variableName
        Description = $runtimeCatalog.Variables[$variableName].Description
        Example = $runtimeCatalog.Variables[$variableName].Example
        UsedBy = @($usedBy | Sort-Object)
        PresentInRuntimeEnvFile = [bool]($runtimeEnvKeys -contains $variableName)
    }
}

$platformValueEntries = @()
foreach ($variableName in @($platformValueMap.Keys | Sort-Object)) {
    $entry = $platformValueMap[$variableName]
    $platformValueEntries += [PSCustomObject]@{
        Name = $entry.Name
        UsedByServices = @($entry.UsedByServices | Sort-Object)
        UsedByArtifacts = @($entry.UsedByArtifacts | Sort-Object)
        PresentInValuesFile = [bool]$entry.PresentInValuesFile
    }
}

$applicationsText = Get-TextList -Values $selection.Applications
$explicitDataServicesText = Get-TextList -Values $selection.DataServices
$effectiveDataServicesText = Get-TextList -Values $effectiveDataServices
$selectedServicesText = Get-TextList -Values $effectiveServiceDirectories

switch ($Format) {
    "json" {
        $document = ([ordered]@{
            Profile = $selection.Profile
            Description = $selection.Description
            Applications = @($selection.Applications)
            ExplicitDataServices = @($selection.DataServices)
            EffectiveDataServices = @($effectiveDataServices)
            IncludeJenkins = [bool]$IncludeJenkins
            ValuesFile = $resolvedValuesFile
            RuntimeEnvFile = $resolvedRuntimeEnvFile
            ServiceDirectories = @($effectiveServiceDirectories)
            JenkinsVariables = @($jenkinsVariableEntries)
            ComposeVariables = @($composeVariableEntries)
            PlatformValues = @($platformValueEntries)
            Services = @($serviceRecords)
        } | ConvertTo-Json -Depth 10)
    }
    "markdown" {
        $lines = @(
            "# Service Input Plan",
            "",
            "## Summary",
            "",
            ("- Profile: " + $selection.Profile),
            ("- Description: " + $selection.Description),
            ("- Applications: " + $applicationsText),
            ("- Explicit data services: " + $explicitDataServicesText),
            ("- Effective in-cluster data services: " + $effectiveDataServicesText),
            ("- Selected services: " + $selectedServicesText),
            ("- Jenkins environment variables: " + [string]$jenkinsVariableEntries.Count),
            ("- Compose environment variables: " + [string]$composeVariableEntries.Count),
            ("- Platform value keys: " + [string]$platformValueEntries.Count),
            ("- Values file: " + $resolvedValuesFile),
            ("- Runtime env file: " + $resolvedRuntimeEnvFile),
            ""
        )

        if ($jenkinsVariableEntries.Count -gt 0) {
            $lines += "## Jenkins Environment Variables"
            $lines += ""
            foreach ($variable in $jenkinsVariableEntries) {
                $lines += ("- " + $variable.Name + ": " + $variable.Description)
                $lines += ("  Required by: " + (Get-TextList -Values $variable.RequiredBy))
                $lines += ("  Optional for: " + (Get-TextList -Values $variable.OptionalBy))
            }
            $lines += ""
        }

        if ($composeVariableEntries.Count -gt 0) {
            $lines += "## Compose Environment Variables"
            $lines += ""
            foreach ($variable in $composeVariableEntries) {
                $lines += ("- " + $variable.Name + ": " + $variable.Description)
                $lines += ("  Used by: " + (Get-TextList -Values $variable.UsedBy))
                $lines += ("  Example: " + $variable.Example)
                $lines += ("  Present in runtime env file: " + [string]([bool]$variable.PresentInRuntimeEnvFile))
            }
            $lines += ""
        }

        if ($platformValueEntries.Count -gt 0) {
            $lines += "## Platform Value Keys"
            $lines += ""
            foreach ($variable in $platformValueEntries) {
                $lines += ("- " + $variable.Name + ": used by " + (Get-TextList -Values $variable.UsedByArtifacts))
                $lines += ("  Services: " + (Get-TextList -Values $variable.UsedByServices))
                $lines += ("  Present in values file: " + [string]([bool]$variable.PresentInValuesFile))
            }
            $lines += ""
        }

        if ($serviceRecords.Count -gt 0) {
            $lines += "## Service Input Details"
            $lines += ""
            foreach ($service in $serviceRecords) {
                $pipelineNotes = Get-ValueOrNone -Value $service.PipelineNotes
                $runtimeNotes = Get-ValueOrNone -Value $service.RuntimeNotes
                $dependencyNotes = Get-ValueOrNone -Value $service.DependencyNotes
                $lines += ("### " + $service.Name)
                $lines += ""
                $lines += ("- Jenkins required env vars: " + (Get-TextList -Values $service.JenkinsRequiredEnvVars))
                $lines += ("- Jenkins optional env vars: " + (Get-TextList -Values $service.JenkinsOptionalEnvVars))
                $lines += ("- Compose env vars: " + (Get-TextList -Values $service.ComposeRequiredEnvVars))
                $lines += ("- Missing compose env vars in runtime env file: " + (Get-TextList -Values $service.MissingComposeEnvVars))
                $lines += ("- Config artifacts: " + (Get-TextList -Values $service.ConfigArtifactFiles))
                $lines += ("- Platform value keys: " + (Get-TextList -Values $service.PlatformValueKeys))
                $lines += ("- Missing platform value keys in values file: " + (Get-TextList -Values $service.MissingPlatformValueKeys))
                $lines += ("- Required Kubernetes prerequisites: " + (Get-TextList -Values $service.RequiredK8sDirectories))
                $lines += ("- Missing required Kubernetes prerequisites: " + (Get-TextList -Values $service.MissingRequiredK8sDirectories))
                $lines += ("- Recommended Kubernetes add-ons: " + (Get-TextList -Values $service.RecommendedK8sDirectories))
                $lines += ("- Missing recommended Kubernetes add-ons: " + (Get-TextList -Values $service.MissingRecommendedK8sDirectories))
                $lines += ("- Compatible in-cluster data services: " + (Get-TextList -Values $service.CompatibleDataServices))
                $lines += ("- Selected compatible in-cluster data services: " + (Get-TextList -Values $service.SelectedCompatibleDataServices))
                $lines += ("- Related applications: " + (Get-TextList -Values $service.RelatedApplications))
                $lines += ("- Selected related applications: " + (Get-TextList -Values $service.SelectedRelatedApplications))
                $lines += ("- Pipeline notes: " + $pipelineNotes)
                $lines += ("- Runtime notes: " + $runtimeNotes)
                $lines += ("- Dependency notes: " + $dependencyNotes)
                $lines += ""
            }
        }

        $document = $lines -join [Environment]::NewLine
    }
    default {
        $lines = @(
            "Service Input Plan",
            "==================",
            ("Profile: " + $selection.Profile),
            ("Description: " + $selection.Description),
            ("Applications: " + $applicationsText),
            ("Explicit data services: " + $explicitDataServicesText),
            ("Effective in-cluster data services: " + $effectiveDataServicesText),
            ("Selected services: " + $selectedServicesText),
            ("Values file: " + $resolvedValuesFile),
            ("Runtime env file: " + $resolvedRuntimeEnvFile),
            ""
        )

        if ($jenkinsVariableEntries.Count -gt 0) {
            $lines += "Jenkins environment variables"
            foreach ($variable in $jenkinsVariableEntries) {
                $lines += ("- " + $variable.Name + ": " + $variable.Description)
                $lines += ("  Required by: " + (Get-TextList -Values $variable.RequiredBy))
                $lines += ("  Optional for: " + (Get-TextList -Values $variable.OptionalBy))
            }
            $lines += ""
        }

        if ($composeVariableEntries.Count -gt 0) {
            $lines += "Compose environment variables"
            foreach ($variable in $composeVariableEntries) {
                $lines += ("- " + $variable.Name + ": " + $variable.Description)
                $lines += ("  Used by: " + (Get-TextList -Values $variable.UsedBy))
                $lines += ("  Example: " + $variable.Example)
                $lines += ("  Present in runtime env file: " + [string]([bool]$variable.PresentInRuntimeEnvFile))
            }
            $lines += ""
        }

        if ($platformValueEntries.Count -gt 0) {
            $lines += "Platform value keys"
            foreach ($variable in $platformValueEntries) {
                $lines += ("- " + $variable.Name + ": used by " + (Get-TextList -Values $variable.UsedByArtifacts))
                $lines += ("  Services: " + (Get-TextList -Values $variable.UsedByServices))
                $lines += ("  Present in values file: " + [string]([bool]$variable.PresentInValuesFile))
            }
            $lines += ""
        }

        foreach ($service in $serviceRecords) {
            $pipelineNotes = Get-ValueOrNone -Value $service.PipelineNotes
            $runtimeNotes = Get-ValueOrNone -Value $service.RuntimeNotes
            $dependencyNotes = Get-ValueOrNone -Value $service.DependencyNotes
            $lines += $service.Name
            $lines += ("  Jenkins required env vars: " + (Get-TextList -Values $service.JenkinsRequiredEnvVars))
            $lines += ("  Jenkins optional env vars: " + (Get-TextList -Values $service.JenkinsOptionalEnvVars))
            $lines += ("  Compose env vars: " + (Get-TextList -Values $service.ComposeRequiredEnvVars))
            $lines += ("  Missing compose env vars in runtime env file: " + (Get-TextList -Values $service.MissingComposeEnvVars))
            $lines += ("  Config artifacts: " + (Get-TextList -Values $service.ConfigArtifactFiles))
            $lines += ("  Platform value keys: " + (Get-TextList -Values $service.PlatformValueKeys))
            $lines += ("  Missing platform value keys in values file: " + (Get-TextList -Values $service.MissingPlatformValueKeys))
            $lines += ("  Required Kubernetes prerequisites: " + (Get-TextList -Values $service.RequiredK8sDirectories))
            $lines += ("  Missing required Kubernetes prerequisites: " + (Get-TextList -Values $service.MissingRequiredK8sDirectories))
            $lines += ("  Recommended Kubernetes add-ons: " + (Get-TextList -Values $service.RecommendedK8sDirectories))
            $lines += ("  Missing recommended Kubernetes add-ons: " + (Get-TextList -Values $service.MissingRecommendedK8sDirectories))
            $lines += ("  Compatible in-cluster data services: " + (Get-TextList -Values $service.CompatibleDataServices))
            $lines += ("  Selected compatible in-cluster data services: " + (Get-TextList -Values $service.SelectedCompatibleDataServices))
            $lines += ("  Related applications: " + (Get-TextList -Values $service.RelatedApplications))
            $lines += ("  Selected related applications: " + (Get-TextList -Values $service.SelectedRelatedApplications))
            $lines += ("  Pipeline notes: " + $pipelineNotes)
            $lines += ("  Runtime notes: " + $runtimeNotes)
            $lines += ("  Dependency notes: " + $dependencyNotes)
            $lines += ""
        }

        if ($serviceRecords.Count -eq 0) {
            $lines += "No services selected."
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
    Write-Host ("Wrote service input plan to {0}" -f $resolvedOutputPath)
}
else {
    Write-Output $document
}
