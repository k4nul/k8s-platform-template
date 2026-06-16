param(
    [Parameter(Mandatory = $true)]
    [string]$RenderedPath,

    [switch]$Strict,
    [switch]$ValidateCrdBackedResources,

    [ValidateSet("auto", "kubeconform", "kubectl")]
    [string]$SchemaValidator = "auto"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "kubernetes-manifest-utils.ps1")

function Get-RenderedManifestValidatorDefinitions {
    return @(
        [PSCustomObject]@{
            Name = "kubeconform"
            Command = "kubeconform"
            MissingStrictMessage = "kubeconform is required for rendered manifest validation."
            MissingWarning = "kubeconform is not installed. Skipping rendered manifest validation."
        },
        [PSCustomObject]@{
            Name = "kubectl"
            Command = "kubectl"
            MissingStrictMessage = "kubectl is required for rendered manifest validation."
            MissingWarning = "kubectl is not installed. Skipping rendered manifest validation."
        }
    )
}

function Test-RenderedManifestValidatorAvailable {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Definition
    )

    return ($null -ne (Get-Command $Definition.Command -ErrorAction SilentlyContinue))
}

function Get-RenderedManifestValidator {
    param(
        [string]$RequestedValidator,
        [switch]$Strict
    )

    $definitions = @(Get-RenderedManifestValidatorDefinitions)
    $definitionsByName = @{}

    foreach ($definition in $definitions) {
        $definitionsByName[$definition.Name] = $definition
    }

    if ($RequestedValidator -ne "auto") {
        $requestedDefinition = $definitionsByName[$RequestedValidator]
        if (Test-RenderedManifestValidatorAvailable -Definition $requestedDefinition) {
            return $requestedDefinition.Name
        }

        if ($Strict) {
            throw $requestedDefinition.MissingStrictMessage
        }

        Write-Warning $requestedDefinition.MissingWarning
        return ""
    }

    foreach ($definition in $definitions) {
        if (Test-RenderedManifestValidatorAvailable -Definition $definition) {
            return $definition.Name
        }
    }

    if ($Strict) {
        throw "kubeconform or kubectl is required for rendered manifest validation."
    }

    Write-Warning "Neither kubeconform nor kubectl is installed. Skipping rendered manifest validation."
    return ""
}

function Invoke-RenderedManifestValidator {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Validator,

        [Parameter(Mandatory = $true)]
        [string]$File
    )

    if ($Validator -eq "kubeconform") {
        return (& kubeconform -strict -summary $File 2>&1 | Out-String)
    }

    if ($Validator -eq "kubectl") {
        return (& kubectl apply --dry-run=client --validate=true -f $File 2>&1 | Out-String)
    }

    throw ("Unsupported rendered manifest validator: {0}" -f $Validator)
}

function Add-RenderedYamlValidationTargets {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[object]]$Targets,

        [Parameter(Mandatory = $true)]
        [string]$Root,

        [Parameter(Mandatory = $true)]
        [string]$SearchRoot,

        [Parameter(Mandatory = $true)]
        [string]$Category,

        [switch]$DetectCrdBackedResources
    )

    if (-not (Test-Path -Path $SearchRoot -PathType Container)) {
        return
    }

    Get-ChildItem -Path $SearchRoot -Recurse -File | Where-Object {
        $_.Extension.ToLowerInvariant() -in @(".yaml", ".yml") -and $_.Name -ne "values.yaml"
    } | ForEach-Object {
        $crdBackedApiGroups = @()
        if ($DetectCrdBackedResources) {
            $content = Get-Content -Path $_.FullName -Raw
            $crdBackedApiGroups = @(Get-CrdBackedApiGroupsFromContent -Content $content)
        }

        $Targets.Add([PSCustomObject]@{
            Category = $Category
            File = $_.FullName
            RelativePath = Get-RelativePathFromRoot -Root $Root -Path $_.FullName
            RequiresCrd = (@($crdBackedApiGroups).Count -gt 0)
        }) | Out-Null
    }
}

$root = (Resolve-Path -Path $RenderedPath).Path
$k8sRoot = Join-Path $root "k8s"
if (-not (Test-Path -Path $k8sRoot -PathType Container)) {
    throw ("Rendered bundle does not contain a k8s directory: {0}" -f $k8sRoot)
}

$validationTargets = New-Object System.Collections.Generic.List[object]

Add-RenderedYamlValidationTargets `
    -Targets $validationTargets `
    -Root $root `
    -SearchRoot $k8sRoot `
    -Category "Kubernetes manifests" `
    -DetectCrdBackedResources

$bootstrapNamespaceRoot = Join-Path $root "cluster-bootstrap\namespaces"
Add-RenderedYamlValidationTargets `
    -Targets $validationTargets `
    -Root $root `
    -SearchRoot $bootstrapNamespaceRoot `
    -Category "Bootstrap namespace templates"

$bootstrapSecretRoot = Join-Path $root "cluster-bootstrap\secrets"
Add-RenderedYamlValidationTargets `
    -Targets $validationTargets `
    -Root $root `
    -SearchRoot $bootstrapSecretRoot `
    -Category "Bootstrap secret templates"

$validated = New-Object System.Collections.Generic.List[object]
$skipped = New-Object System.Collections.Generic.List[object]
$failed = New-Object System.Collections.Generic.List[object]
$validator = Get-RenderedManifestValidator -RequestedValidator $SchemaValidator -Strict:$Strict

if (-not $validator) {
    return
}

Write-Host ("Rendered manifest validator: {0}" -f $validator)

foreach ($target in $validationTargets) {
    if ($target.RequiresCrd -and -not $ValidateCrdBackedResources) {
        $skipped.Add([PSCustomObject]@{
            Category = $target.Category
            File = $target.RelativePath
            Reason = "Skipped CRD-backed resource validation. Use -ValidateCrdBackedResources to include it."
        }) | Out-Null
        continue
    }

    $output = Invoke-RenderedManifestValidator -Validator $validator -File $target.File

    if ($LASTEXITCODE -eq 0) {
        $validated.Add([PSCustomObject]@{
            Category = $target.Category
            File = $target.RelativePath
        }) | Out-Null
    }
    else {
        $failed.Add([PSCustomObject]@{
            Category = $target.Category
            File = $target.RelativePath
            Message = $output.Trim()
        }) | Out-Null
    }
}

$validatedK8sCount = @($validated | Where-Object { $_.Category -eq "Kubernetes manifests" }).Count
$validatedBootstrapNamespaceCount = @($validated | Where-Object { $_.Category -eq "Bootstrap namespace templates" }).Count
$validatedBootstrapSecretCount = @($validated | Where-Object { $_.Category -eq "Bootstrap secret templates" }).Count

Write-Host ("Validated Kubernetes manifests: {0}" -f $validatedK8sCount)
Write-Host ("Validated bootstrap namespace templates: {0}" -f $validatedBootstrapNamespaceCount)
Write-Host ("Validated bootstrap secret templates: {0}" -f $validatedBootstrapSecretCount)

if ($skipped.Count -gt 0) {
    Write-Host ("Skipped rendered YAML files: {0}" -f $skipped.Count)
    $skipped | Format-Table -AutoSize
}

if ($failed.Count -gt 0) {
    Write-Host ("Failed rendered YAML files: {0}" -f $failed.Count)
    $failed | Format-Table -AutoSize
    throw "Rendered manifest validation failed."
}

Write-Host "Rendered manifest validation completed successfully."
