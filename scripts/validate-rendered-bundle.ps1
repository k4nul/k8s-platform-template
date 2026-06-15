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

function Get-RenderedManifestValidator {
    param(
        [string]$RequestedValidator,
        [switch]$Strict
    )

    $kubeconform = Get-Command kubeconform -ErrorAction SilentlyContinue
    $kubectl = Get-Command kubectl -ErrorAction SilentlyContinue

    if ($RequestedValidator -eq "kubeconform") {
        if ($null -ne $kubeconform) {
            return "kubeconform"
        }

        if ($Strict) {
            throw "kubeconform is required for rendered manifest validation."
        }

        Write-Warning "kubeconform is not installed. Skipping rendered manifest validation."
        return ""
    }

    if ($RequestedValidator -eq "kubectl") {
        if ($null -ne $kubectl) {
            return "kubectl"
        }

        if ($Strict) {
            throw "kubectl is required for rendered manifest validation."
        }

        Write-Warning "kubectl is not installed. Skipping rendered manifest validation."
        return ""
    }

    if ($null -ne $kubeconform) {
        return "kubeconform"
    }

    if ($null -ne $kubectl) {
        return "kubectl"
    }

    if ($Strict) {
        throw "kubeconform or kubectl is required for rendered manifest validation."
    }

    Write-Warning "Neither kubeconform nor kubectl is installed. Skipping rendered manifest validation."
    return ""
}

$root = (Resolve-Path -Path $RenderedPath).Path
$k8sRoot = Join-Path $root "k8s"
if (-not (Test-Path -Path $k8sRoot -PathType Container)) {
    Write-Error ("Rendered bundle does not contain a k8s directory: {0}" -f $k8sRoot)
}

$validationTargets = New-Object System.Collections.Generic.List[object]

Get-ChildItem -Path $k8sRoot -Recurse -File | Where-Object {
    $_.Extension.ToLowerInvariant() -in @(".yaml", ".yml") -and $_.Name -ne "values.yaml"
} | ForEach-Object {
    $content = Get-Content -Path $_.FullName -Raw
    $crdBackedApiGroups = @(Get-CrdBackedApiGroupsFromContent -Content $content)

    $validationTargets.Add([PSCustomObject]@{
        Category = "Kubernetes manifests"
        File = $_.FullName
        RelativePath = Get-RelativePathFromRoot -Root $root -Path $_.FullName
        RequiresCrd = ($crdBackedApiGroups.Count -gt 0)
    }) | Out-Null
}

$bootstrapNamespaceRoot = Join-Path $root "cluster-bootstrap\namespaces"
if (Test-Path -Path $bootstrapNamespaceRoot -PathType Container) {
    Get-ChildItem -Path $bootstrapNamespaceRoot -Recurse -File | Where-Object {
        $_.Extension.ToLowerInvariant() -in @(".yaml", ".yml")
    } | ForEach-Object {
        $validationTargets.Add([PSCustomObject]@{
            Category = "Bootstrap namespace templates"
            File = $_.FullName
            RelativePath = Get-RelativePathFromRoot -Root $root -Path $_.FullName
            RequiresCrd = $false
        }) | Out-Null
    }
}

$bootstrapSecretRoot = Join-Path $root "cluster-bootstrap\secrets"
if (Test-Path -Path $bootstrapSecretRoot -PathType Container) {
    Get-ChildItem -Path $bootstrapSecretRoot -Recurse -File | Where-Object {
        $_.Extension.ToLowerInvariant() -in @(".yaml", ".yml")
    } | ForEach-Object {
        $validationTargets.Add([PSCustomObject]@{
            Category = "Bootstrap secret templates"
            File = $_.FullName
            RelativePath = Get-RelativePathFromRoot -Root $root -Path $_.FullName
            RequiresCrd = $false
        }) | Out-Null
    }
}

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

    if ($validator -eq "kubeconform") {
        $output = & kubeconform -strict -summary $target.File 2>&1 | Out-String
    }
    else {
        $output = & kubectl apply --dry-run=client --validate=true -f $target.File 2>&1 | Out-String
    }

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
