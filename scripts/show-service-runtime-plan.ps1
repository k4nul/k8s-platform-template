param(
    [string]$RepoRoot,
    [string[]]$ServiceNames = @(),
    [ValidateSet("text", "markdown", "json", "env")]
    [string]$Format = "text",
    [string]$OutputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Expand-RequestedServiceNames {
    param(
        [string[]]$Values
    )

    $expandedValues = New-Object System.Collections.Generic.List[string]
    foreach ($value in @($Values)) {
        if (-not $value) {
            continue
        }

        foreach ($item in ($value -split ",")) {
            $trimmedItem = $item.Trim()
            if ($trimmedItem) {
                $expandedValues.Add($trimmedItem) | Out-Null
            }
        }
    }

    return @($expandedValues | Sort-Object -Unique)
}

function Get-ServiceNamesText {
    param(
        [object[]]$Services
    )

    if (@($Services).Count -gt 0) {
        return (@($Services | ForEach-Object { $_.Name }) -join ", ")
    }

    return "none selected"
}

function Get-ServiceRuntimeVariableCatalog {
    param(
        [System.Collections.IDictionary]$VariableCatalog,
        [string[]]$VariableOrder,
        [object[]]$Services
    )

    $selectedVariableNames = New-Object System.Collections.Generic.List[string]
    foreach ($service in @($Services)) {
        foreach ($variableName in @($service.RequiredEnvVars)) {
            if ($selectedVariableNames -notcontains $variableName) {
                $selectedVariableNames.Add($variableName) | Out-Null
            }
        }
    }

    $variableEntries = @()
    foreach ($variableName in @($VariableOrder)) {
        if ($selectedVariableNames -notcontains $variableName) {
            continue
        }

        $usedBy = @(
            $Services |
                Where-Object { @($_.RequiredEnvVars) -contains $variableName } |
                ForEach-Object { $_.Name }
        )

        $variableEntries += [PSCustomObject]@{
            Name = $variableName
            Description = $VariableCatalog[$variableName].Description
            Example = $VariableCatalog[$variableName].Example
            UsedBy = @($usedBy)
        }
    }

    return $variableEntries
}

function Get-ServiceImageReference {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Service
    )

    if ($Service.PSObject.Properties.Name -contains "PublicImage" -and $Service.PublicImage) {
        return [string]$Service.PublicImage
    }

    if ($Service.PSObject.Properties.Name -contains "ImagePath" -and $Service.ImagePath) {
        return ('${DOCKER_REGISTRY}/' + [string]$Service.ImagePath)
    }

    return "not specified"
}

if (-not $PSBoundParameters.ContainsKey("RepoRoot") -or -not $RepoRoot) {
    $RepoRoot = Join-Path $PSScriptRoot ".."
}

$root = (Resolve-Path -Path $RepoRoot).Path
$catalogPath = Join-Path $root "config\service-runtime-bindings.psd1"
$catalog = Import-PowerShellDataFile -Path $catalogPath
$allServices = @($catalog.Services | Sort-Object { $_.Name })
$availableServiceNames = @($allServices | ForEach-Object { $_.Name })
$variableOrder = if ($catalog.ContainsKey("VariableOrder")) {
    @($catalog.VariableOrder)
}
else {
    @($catalog.Variables.Keys | Sort-Object)
}

$selectedServices = @()
if ($PSBoundParameters.ContainsKey("ServiceNames")) {
    $requestedServiceNames = Expand-RequestedServiceNames -Values $ServiceNames
    $unknownServices = @($requestedServiceNames | Where-Object { $availableServiceNames -notcontains $_ })
    if ($unknownServices.Count -gt 0) {
        throw "Unknown service runtime selection: $($unknownServices -join ', '). Available services: $($availableServiceNames -join ', ')"
    }

    foreach ($service in $allServices) {
        if ($requestedServiceNames -contains $service.Name) {
            $selectedServices += $service
        }
    }
}
else {
    $selectedServices = @($allServices)
}

$selectedServiceNamesText = Get-ServiceNamesText -Services $selectedServices
$variableEntries = @(Get-ServiceRuntimeVariableCatalog -VariableCatalog $catalog.Variables -VariableOrder $variableOrder -Services $selectedServices)
$composeVariableCountText = [string]$variableEntries.Count

switch ($Format) {
    "json" {
        $document = ([ordered]@{
            SelectedServices = @($selectedServices | ForEach-Object { $_.Name })
            Variables = @($variableEntries)
            Services = @($selectedServices)
        } | ConvertTo-Json -Depth 10)
    }
    "env" {
        $lines = @(
            "# Service runtime environment variables",
            ("# Selected services: " + $selectedServiceNamesText),
            "# Copy this file to a local env file or export the variables before running docker-compose."
        )

        if ($variableEntries.Count -eq 0) {
            $lines += "# No service runtime variables are required because no services were selected."
        }
        else {
            foreach ($variable in $variableEntries) {
                $lines += ""
                $lines += ("# " + $variable.Name + ": " + $variable.Description)
                $lines += ("# Used by: " + ($variable.UsedBy -join ", "))
                $lines += ($variable.Name + "=" + $variable.Example)
            }
        }

        $document = $lines -join [Environment]::NewLine
    }
    "markdown" {
        $lines = @(
            "# Service Runtime Plan",
            "",
            "## Summary",
            "",
            ("- Selected services: " + $selectedServiceNamesText),
            ("- Compose environment variables: " + $composeVariableCountText),
            ""
        )

        if ($variableEntries.Count -gt 0) {
            $lines += "## Compose Environment Variables"
            $lines += ""
            foreach ($variable in $variableEntries) {
                $lines += ("- " + $variable.Name + ": " + $variable.Description + " Used by " + ($variable.UsedBy -join ", ") + ".")
            }
            $lines += ""
        }

        if ($selectedServices.Count -gt 0) {
            $lines += "## Service Runtime Details"
            $lines += ""
            foreach ($service in $selectedServices) {
                $imageReference = Get-ServiceImageReference -Service $service
                $lines += ("### " + $service.Name)
                $lines += ""
                $lines += ("- Compose service: " + $service.ComposeServiceName)
                $lines += ("- Image reference: " + $imageReference)
                $lines += ("- Restart policy: " + $service.RestartPolicy)
                $lines += ("- Requires host gateway: " + [string]([bool]$service.RequiresHostGateway))
                if (@($service.ExposedPorts).Count -gt 0) {
                    $lines += ("- Exposed ports: " + (@($service.ExposedPorts) -join ", "))
                }
                else {
                    $lines += "- Exposed ports: none"
                }
                if ($service.ContainerName) {
                    $lines += ("- Container name env: " + $service.ContainerName)
                }
                else {
                    $lines += "- Container name env: none"
                }
                if (@($service.VolumeBindings).Count -gt 0) {
                    $lines += ("- Volume bindings: " + (@($service.VolumeBindings) -join ", "))
                }
                else {
                    $lines += "- Volume bindings: none"
                }
                $lines += ("- Notes: " + $service.Notes)
                $lines += ""
            }
        }

        $document = $lines -join [Environment]::NewLine
    }
    default {
        $lines = @(
            "Service Runtime Plan",
            "====================",
            ("Selected services: " + $selectedServiceNamesText),
            ""
        )

        if ($variableEntries.Count -gt 0) {
            $lines += "Compose environment variables"
            foreach ($variable in $variableEntries) {
                $lines += ("- " + $variable.Name + ": " + $variable.Description + " Used by " + ($variable.UsedBy -join ", ") + ".")
            }
            $lines += ""
        }

        foreach ($service in $selectedServices) {
            $imageReference = Get-ServiceImageReference -Service $service
            $lines += ($service.Name + " [" + $service.ComposeServiceName + "]")
            $lines += ("  Image reference: " + $imageReference)
            $lines += ("  Restart policy: " + $service.RestartPolicy)
            $lines += ("  Requires host gateway: " + [string]([bool]$service.RequiresHostGateway))
            if (@($service.ExposedPorts).Count -gt 0) {
                $lines += ("  Exposed ports: " + (@($service.ExposedPorts) -join ", "))
            }
            else {
                $lines += "  Exposed ports: none"
            }
            if ($service.ContainerName) {
                $lines += ("  Container name env: " + $service.ContainerName)
            }
            else {
                $lines += "  Container name env: none"
            }
            if (@($service.VolumeBindings).Count -gt 0) {
                $lines += ("  Volume bindings: " + (@($service.VolumeBindings) -join ", "))
            }
            else {
                $lines += "  Volume bindings: none"
            }
            $lines += ("  Notes: " + $service.Notes)
            $lines += ""
        }

        if ($selectedServices.Count -eq 0) {
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
    Write-Host ("Wrote service runtime plan to {0}" -f $resolvedOutputPath)
}
else {
    Write-Output $document
}
