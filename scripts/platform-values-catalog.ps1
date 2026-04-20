Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot "platform-catalog.ps1")
. (Join-Path $PSScriptRoot "template-rendering.ps1")

function Get-PlatformValueCatalog {
    param(
        [string]$RepoRoot
    )

    if (-not $PSBoundParameters.ContainsKey("RepoRoot") -or -not $RepoRoot) {
        $RepoRoot = Join-Path $PSScriptRoot ".."
    }

    $root = (Resolve-Path -Path $RepoRoot).Path
    return Import-PowerShellDataFile -Path (Join-Path $root "config\platform-values-catalog.psd1")
}

function Get-PlatformValueCatalogMap {
    param(
        [string]$RepoRoot
    )

    $catalog = Get-PlatformValueCatalog -RepoRoot $RepoRoot
    $map = [ordered]@{}
    foreach ($entry in @($catalog.Values | Sort-Object { $_.Name })) {
        $map[$entry.Name] = $entry
    }

    return $map
}

function Get-EnvFileEntryMap {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $resolvedPath = (Resolve-Path -Path $Path).Path
    $map = [ordered]@{}

    foreach ($line in Get-Content -Path $resolvedPath) {
        $trimmedLine = $line.Trim()
        if (-not $trimmedLine -or $trimmedLine.StartsWith("#")) {
            continue
        }

        $delimiterIndex = $trimmedLine.IndexOf("=")
        if ($delimiterIndex -lt 1) {
            continue
        }

        $key = $trimmedLine.Substring(0, $delimiterIndex).Trim()
        $value = $trimmedLine.Substring($delimiterIndex + 1)
        $map[$key] = $value
    }

    return $map
}

function Get-EffectivePlatformK8sDirectories {
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

function Get-EffectivePlatformServiceDirectories {
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

function Get-EffectivePlatformDataServices {
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

function Get-PlatformValuePlanData {
    param(
        [string]$RepoRoot,
        [string]$Profile = "full",
        [string[]]$Applications = @(),
        [string[]]$DataServices = @(),
        [switch]$IncludeJenkins,
        [string]$ValuesFile
    )

    if (-not $PSBoundParameters.ContainsKey("RepoRoot") -or -not $RepoRoot) {
        $RepoRoot = Join-Path $PSScriptRoot ".."
    }

    if (-not $PSBoundParameters.ContainsKey("ValuesFile") -or -not $ValuesFile) {
        $ValuesFile = Join-Path $PSScriptRoot "..\config\platform-values.env.example"
    }

    $root = (Resolve-Path -Path $RepoRoot).Path
    $resolvedValuesFile = (Resolve-Path -Path $ValuesFile).Path
    $selection = Resolve-PlatformSelection -Profile $Profile -Applications $Applications -DataServices $DataServices -IncludeJenkins:$IncludeJenkins
    $effectiveK8sDirectories = Get-EffectivePlatformK8sDirectories -Root $root -Selection $selection
    $effectiveServiceDirectories = Get-EffectivePlatformServiceDirectories -Root $root -Selection $selection
    $dataServiceCatalog = Get-PlatformDataServiceCatalog
    $effectiveDataServices = Get-EffectivePlatformDataServices -K8sDirectories $effectiveK8sDirectories -Selection $selection -DataServiceCatalog $dataServiceCatalog
    $catalogMap = Get-PlatformValueCatalogMap -RepoRoot $root
    $envMap = Get-EnvFileEntryMap -Path $resolvedValuesFile
    $serviceConfigCatalog = Import-PowerShellDataFile -Path (Join-Path $root "config\service-config-artifacts.psd1")
    $serviceConfigMap = [ordered]@{}
    $builtInTokens = @("DOCKER_REGISTRY", "VERSION")

    foreach ($service in @($serviceConfigCatalog.Services | Sort-Object { $_.Name })) {
        $serviceConfigMap[$service.Name] = $service
    }

    $requiredTokenMap = [ordered]@{}

    foreach ($directory in $effectiveK8sDirectories) {
        $directoryRoot = Join-Path $root ("k8s\{0}" -f $directory)
        if (-not (Test-Path -Path $directoryRoot -PathType Container)) {
            continue
        }

        Get-ChildItem -Path $directoryRoot -Recurse -File | Where-Object {
            $_.Extension.ToLowerInvariant() -in @(".yaml", ".yml")
        } | ForEach-Object {
            $relativePath = Get-RelativePathCompat -BasePath $root -TargetPath $_.FullName
            $content = Get-Content -Path $_.FullName -Raw
            $tokens = @(
                [regex]::Matches($content, '__([A-Z0-9_]+)__') |
                    ForEach-Object { $_.Groups[1].Value } |
                    Sort-Object -Unique
            )

            foreach ($token in $tokens) {
                if ($builtInTokens -contains $token) {
                    continue
                }

                if (-not $requiredTokenMap.Contains($token)) {
                    $requiredTokenMap[$token] = [ordered]@{
                        Name = $token
                        SourcePaths = New-Object System.Collections.Generic.List[string]
                        K8sDirectories = New-Object System.Collections.Generic.List[string]
                        ServiceNames = New-Object System.Collections.Generic.List[string]
                    }
                }

                if ($requiredTokenMap[$token].SourcePaths -notcontains $relativePath) {
                    $requiredTokenMap[$token].SourcePaths.Add($relativePath) | Out-Null
                }

                if ($requiredTokenMap[$token].K8sDirectories -notcontains $directory) {
                    $requiredTokenMap[$token].K8sDirectories.Add($directory) | Out-Null
                }
            }
        }
    }

    foreach ($serviceName in $effectiveServiceDirectories) {
        if (-not $serviceConfigMap.Contains($serviceName)) {
            continue
        }

        foreach ($artifact in @($serviceConfigMap[$serviceName].ConfigArtifacts)) {
            foreach ($token in @($artifact.PlaceholderTokens | Sort-Object -Unique)) {
                if ($builtInTokens -contains $token) {
                    continue
                }

                if (-not $requiredTokenMap.Contains($token)) {
                    $requiredTokenMap[$token] = [ordered]@{
                        Name = $token
                        SourcePaths = New-Object System.Collections.Generic.List[string]
                        K8sDirectories = New-Object System.Collections.Generic.List[string]
                        ServiceNames = New-Object System.Collections.Generic.List[string]
                    }
                }

                $relativePath = "services\{0}\{1}" -f $serviceName, $artifact.SourceFile
                if ($requiredTokenMap[$token].SourcePaths -notcontains $relativePath) {
                    $requiredTokenMap[$token].SourcePaths.Add($relativePath) | Out-Null
                }

                if ($requiredTokenMap[$token].ServiceNames -notcontains $serviceName) {
                    $requiredTokenMap[$token].ServiceNames.Add($serviceName) | Out-Null
                }
            }
        }
    }

    $entries = @()
    foreach ($tokenName in @($requiredTokenMap.Keys | Sort-Object)) {
        $requirement = $requiredTokenMap[$tokenName]
        $catalogEntry = if ($catalogMap.Contains($tokenName)) { $catalogMap[$tokenName] } else { $null }

        $entries += [PSCustomObject]@{
            Name = $tokenName
            Category = if ($null -ne $catalogEntry) { $catalogEntry.Category } else { "uncatalogued" }
            Sensitive = if ($null -ne $catalogEntry) { [bool]$catalogEntry.Sensitive } else { $false }
            Description = if ($null -ne $catalogEntry) { $catalogEntry.Description } else { "No platform value catalog entry is defined for this key yet." }
            ExampleValue = if ($envMap.Contains($tokenName)) { $envMap[$tokenName] } else { "" }
            PresentInValuesFile = [bool]$envMap.Contains($tokenName)
            SourcePaths = @($requirement.SourcePaths | Sort-Object)
            K8sDirectories = @($requirement.K8sDirectories | Sort-Object)
            ServiceNames = @($requirement.ServiceNames | Sort-Object)
        }
    }

    return [PSCustomObject]@{
        RepoRoot = $root
        ValuesFilePath = $resolvedValuesFile
        Selection = $selection
        K8sDirectories = @($effectiveK8sDirectories)
        ServiceDirectories = @($effectiveServiceDirectories)
        EffectiveDataServices = @($effectiveDataServices)
        Entries = @($entries | Sort-Object Category, Name)
        RequiredKeys = @($requiredTokenMap.Keys | Sort-Object)
        MissingCatalogKeys = @($requiredTokenMap.Keys | Where-Object { -not $catalogMap.Contains($_) } | Sort-Object)
        MissingValuesFileKeys = @($requiredTokenMap.Keys | Where-Object { -not $envMap.Contains($_) } | Sort-Object)
        UnknownValuesFileKeys = @($envMap.Keys | Where-Object { -not $catalogMap.Contains($_) } | Sort-Object)
        CatalogKeys = @($catalogMap.Keys | Sort-Object)
        ValuesFileKeys = @($envMap.Keys | Sort-Object)
    }
}
