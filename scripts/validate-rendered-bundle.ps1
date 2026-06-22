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

function Get-RenderedValidationCategoryCount {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[object]]$Items,

        [Parameter(Mandatory = $true)]
        [string]$Category
    )

    return @($Items | Where-Object { $_.Category -eq $Category }).Count
}

function Add-RenderedManifestSkip {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[object]]$Skipped,

        [Parameter(Mandatory = $true)]
        [object]$Target
    )

    $Skipped.Add([PSCustomObject]@{
        Category = $Target.Category
        File = $Target.RelativePath
        Reason = "Skipped CRD-backed resource validation. Use -ValidateCrdBackedResources to include it."
    }) | Out-Null
}

function Add-RenderedManifestValidationSuccess {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[object]]$Validated,

        [Parameter(Mandatory = $true)]
        [object]$Target
    )

    $Validated.Add([PSCustomObject]@{
        Category = $Target.Category
        File = $Target.RelativePath
    }) | Out-Null
}

function Add-RenderedManifestValidationFailure {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[object]]$Failed,

        [Parameter(Mandatory = $true)]
        [object]$Target,

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Message
    )

    $Failed.Add([PSCustomObject]@{
        Category = $Target.Category
        File = $Target.RelativePath
        Message = $Message
    }) | Out-Null
}

function New-RenderedManifestValidationState {
    return [PSCustomObject]@{
        Validated = New-Object System.Collections.Generic.List[object]
        Skipped = New-Object System.Collections.Generic.List[object]
        Failed = New-Object System.Collections.Generic.List[object]
    }
}

function Add-RenderedManifestSkipIfRequired {
    param(
        [Parameter(Mandatory = $true)]
        [object]$State,

        [Parameter(Mandatory = $true)]
        [object]$Target,

        [switch]$ValidateCrdBackedResources
    )

    if ($Target.RequiresCrd -and -not $ValidateCrdBackedResources) {
        Add-RenderedManifestSkip -Skipped $State.Skipped -Target $Target
        return $true
    }

    return $false
}

function Invoke-RenderedManifestTargetValidation {
    param(
        [Parameter(Mandatory = $true)]
        [object]$State,

        [Parameter(Mandatory = $true)]
        [System.Collections.Generic.List[object]]$Targets,

        [Parameter(Mandatory = $true)]
        [scriptblock]$ValidateTarget,

        [switch]$ValidateCrdBackedResources
    )

    foreach ($target in $Targets) {
        if (Add-RenderedManifestSkipIfRequired -State $State -Target $target -ValidateCrdBackedResources:$ValidateCrdBackedResources) {
            continue
        }

        & $ValidateTarget -State $State -Target $target
    }
}

function Test-RenderedManifestTargetHasFailure {
    param(
        [Parameter(Mandatory = $true)]
        [object]$State,

        [Parameter(Mandatory = $true)]
        [object]$Target
    )

    return (@($State.Failed | Where-Object { $_.File -eq $Target.RelativePath }).Count -gt 0)
}

function Write-RenderedManifestValidationResult {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[object]]$Validated,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[object]]$Skipped,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[object]]$Failed,

        [Parameter(Mandatory = $true)]
        [string]$ValidatedLabel,

        [Parameter(Mandatory = $true)]
        [string]$FailureMessage,

        [Parameter(Mandatory = $true)]
        [string]$SuccessMessage,

        [switch]$AppendFailedFilesToFailure
    )

    $validatedK8sCount = Get-RenderedValidationCategoryCount -Items $Validated -Category "Kubernetes manifests"
    $validatedBootstrapNamespaceCount = Get-RenderedValidationCategoryCount -Items $Validated -Category "Bootstrap namespace templates"
    $validatedBootstrapSecretCount = Get-RenderedValidationCategoryCount -Items $Validated -Category "Bootstrap secret templates"

    Write-Host ("{0} Kubernetes manifests: {1}" -f $ValidatedLabel, $validatedK8sCount)
    Write-Host ("{0} bootstrap namespace templates: {1}" -f $ValidatedLabel, $validatedBootstrapNamespaceCount)
    Write-Host ("{0} bootstrap secret templates: {1}" -f $ValidatedLabel, $validatedBootstrapSecretCount)

    if ($Skipped.Count -gt 0) {
        Write-Host ("Skipped rendered YAML files: {0}" -f $Skipped.Count)
        $Skipped | Format-Table -AutoSize
    }

    if ($Failed.Count -gt 0) {
        Write-Host ("Failed rendered YAML files: {0}" -f $Failed.Count)
        $Failed | Format-Table -AutoSize

        if ($AppendFailedFilesToFailure) {
            $failedFiles = @($Failed | Select-Object -ExpandProperty File -Unique)
            throw ("{0}: {1}" -f $FailureMessage, ($failedFiles -join ", "))
        }

        throw $FailureMessage
    }

    Write-Host $SuccessMessage
}

function Invoke-RenderedManifestStructuralPreflight {
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.Generic.List[object]]$Targets,

        [switch]$ValidateCrdBackedResources
    )

    $state = New-RenderedManifestValidationState

    Write-Host "Built-in rendered manifest structural preflight: apiVersion, kind, and metadata.name"

    Invoke-RenderedManifestTargetValidation `
        -State $state `
        -Targets $Targets `
        -ValidateCrdBackedResources:$ValidateCrdBackedResources `
        -ValidateTarget {
        param(
            [Parameter(Mandatory = $true)]
            [object]$State,

            [Parameter(Mandatory = $true)]
            [object]$Target
        )

        $content = Get-Content -Path $Target.File -Raw
        $documents = @(Get-YamlDocumentBlocks -Content $content)

        if ($documents.Count -eq 0) {
            Add-RenderedManifestValidationFailure `
                -Failed $State.Failed `
                -Target $Target `
                -Message "YAML file did not contain a Kubernetes document."
            return
        }

        $documentIndex = 0
        foreach ($document in $documents) {
            $documentIndex++
            $metadata = Get-YamlDocumentMetadata -Document $document
            $missingFields = @()

            if (-not $metadata.ApiVersion) {
                $missingFields += "apiVersion"
            }

            if (-not $metadata.Kind) {
                $missingFields += "kind"
            }

            if (-not $metadata.Name) {
                $missingFields += "metadata.name"
            }

            if ($missingFields.Count -gt 0) {
                Add-RenderedManifestValidationFailure `
                    -Failed $State.Failed `
                    -Target $Target `
                    -Message ("Document {0} is missing: {1}" -f $documentIndex, ($missingFields -join ", "))
            }
        }

        if (-not (Test-RenderedManifestTargetHasFailure -State $State -Target $Target)) {
            Add-RenderedManifestValidationSuccess -Validated $State.Validated -Target $Target
        }
    }

    Write-RenderedManifestValidationResult `
        -Validated $state.Validated `
        -Skipped $state.Skipped `
        -Failed $state.Failed `
        -ValidatedLabel "Structurally validated" `
        -FailureMessage "Rendered manifest structural preflight failed" `
        -SuccessMessage "Rendered manifest structural preflight completed successfully." `
        -AppendFailedFilesToFailure
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

function Get-RenderedManifestValidationTargets {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Root
    )

    $k8sRoot = Join-Path $Root "k8s"
    if (-not (Test-Path -Path $k8sRoot -PathType Container)) {
        throw ("Rendered bundle does not contain a k8s directory: {0}" -f $k8sRoot)
    }

    $targets = New-Object System.Collections.Generic.List[object]

    Add-RenderedYamlValidationTargets `
        -Targets $targets `
        -Root $Root `
        -SearchRoot $k8sRoot `
        -Category "Kubernetes manifests" `
        -DetectCrdBackedResources

    $bootstrapNamespaceRoot = Join-Path $Root "cluster-bootstrap\namespaces"
    Add-RenderedYamlValidationTargets `
        -Targets $targets `
        -Root $Root `
        -SearchRoot $bootstrapNamespaceRoot `
        -Category "Bootstrap namespace templates"

    $bootstrapSecretRoot = Join-Path $Root "cluster-bootstrap\secrets"
    Add-RenderedYamlValidationTargets `
        -Targets $targets `
        -Root $Root `
        -SearchRoot $bootstrapSecretRoot `
        -Category "Bootstrap secret templates"

    return $targets
}

$root = (Resolve-Path -Path $RenderedPath).Path
$validationTargets = Get-RenderedManifestValidationTargets -Root $root
$state = New-RenderedManifestValidationState
$validator = Get-RenderedManifestValidator -RequestedValidator $SchemaValidator -Strict:$Strict

if (-not $validator) {
    Invoke-RenderedManifestStructuralPreflight `
        -Targets $validationTargets `
        -ValidateCrdBackedResources:$ValidateCrdBackedResources
    return
}

Write-Host ("Rendered manifest validator: {0}" -f $validator)

Invoke-RenderedManifestTargetValidation `
    -State $state `
    -Targets $validationTargets `
    -ValidateCrdBackedResources:$ValidateCrdBackedResources `
    -ValidateTarget {
    param(
        [Parameter(Mandatory = $true)]
        [object]$State,

        [Parameter(Mandatory = $true)]
        [object]$Target
    )

    $output = Invoke-RenderedManifestValidator -Validator $validator -File $Target.File

    if ($LASTEXITCODE -eq 0) {
        Add-RenderedManifestValidationSuccess -Validated $State.Validated -Target $Target
    }
    else {
        Add-RenderedManifestValidationFailure `
            -Failed $State.Failed `
            -Target $Target `
            -Message $output.Trim()
    }
}

Write-RenderedManifestValidationResult `
    -Validated $state.Validated `
    -Skipped $state.Skipped `
    -Failed $state.Failed `
    -ValidatedLabel "Validated" `
    -FailureMessage "Rendered manifest validation failed." `
    -SuccessMessage "Rendered manifest validation completed successfully."
