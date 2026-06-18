Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$script:TestsRun = 0
$script:TestsFailed = 0

function Assert-Equal {
    param(
        [object]$Expected,
        [object]$Actual,
        [string]$Message
    )

    if ($Expected -ne $Actual) {
        throw ("{0} Expected '{1}', got '{2}'." -f $Message, $Expected, $Actual)
    }
}

function Assert-True {
    param(
        [bool]$Condition,
        [string]$Message
    )

    if (-not $Condition) {
        throw $Message
    }
}

function Assert-Contains {
    param(
        [string]$Content,
        [string]$Expected,
        [string]$Message
    )

    if (-not $Content.Contains($Expected)) {
        throw ("{0} Expected to find '{1}'." -f $Message, $Expected)
    }
}

function Assert-NotContains {
    param(
        [string]$Content,
        [string]$Unexpected,
        [string]$Message
    )

    if ($Content.Contains($Unexpected)) {
        throw ("{0} Expected not to find '{1}'." -f $Message, $Unexpected)
    }
}

function Assert-SequenceEqual {
    param(
        [object[]]$Expected,
        [object[]]$Actual,
        [string]$Message
    )

    $expectedValues = @($Expected)
    $actualValues = @($Actual)

    if ($expectedValues.Count -ne $actualValues.Count) {
        throw ("{0} Expected {1} item(s) [{2}], got {3} item(s) [{4}]." -f $Message, $expectedValues.Count, ($expectedValues -join ", "), $actualValues.Count, ($actualValues -join ", "))
    }

    for ($index = 0; $index -lt $expectedValues.Count; $index++) {
        if ($expectedValues[$index] -ne $actualValues[$index]) {
            throw ("{0} At index {1}, expected '{2}', got '{3}'." -f $Message, $index, $expectedValues[$index], $actualValues[$index])
        }
    }
}

function Invoke-Test {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [scriptblock]$Body
    )

    $script:TestsRun++
    try {
        & $Body
        Write-Host ("[PASS] {0}" -f $Name)
    }
    catch {
        $script:TestsFailed++
        Write-Host ("[FAIL] {0}" -f $Name)
        Write-Host ("       {0}" -f $_.Exception.Message)
    }
}

function Invoke-WithEmptyToolPath {
    param(
        [Parameter(Mandatory = $true)]
        [scriptblock]$Body
    )

    $previousPath = $env:PATH
    $toolPath = Join-Path ([System.IO.Path]::GetTempPath()) ("validation-readiness-tools-" + [Guid]::NewGuid().ToString("N"))

    try {
        New-Item -ItemType Directory -Path $toolPath -Force | Out-Null
        $env:PATH = $toolPath
        & $Body
    }
    finally {
        $env:PATH = $previousPath
        if (Test-Path -LiteralPath $toolPath) {
            Remove-Item -LiteralPath $toolPath -Recurse -Force
        }
    }
}

$repoRoot = (Resolve-Path -Path (Join-Path $PSScriptRoot "..")).Path
$readinessScript = Join-Path $repoRoot "scripts\show-validation-readiness.ps1"
$publicValuesFile = Join-Path $repoRoot "config\platform-values.env.example"

Invoke-Test -Name "Readiness JSON groups alternative schema validators as one missing requirement" -Body {
    $document = Invoke-WithEmptyToolPath -Body {
        $json = & $readinessScript `
            -RepoRoot $repoRoot `
            -ValuesFile $publicValuesFile `
            -Profile "web-platform" `
            -Applications @("nginx-web", "httpbin", "whoami") `
            -DataServices @("redis") `
            -Format json | Out-String

        return ($json | ConvertFrom-Json)
    }

    Assert-Equal `
        -Expected "repository-only-validation-available" `
        -Actual $document.ReadinessStatus `
        -Message "Without schema validators or helm, readiness should be repository-only."
    Assert-SequenceEqual `
        -Expected @("kubeconform or kubectl", "helm") `
        -Actual @($document.MissingRequiredToolRequirements) `
        -Message "Missing requirement text should group the schema-validator alternatives."
    Assert-SequenceEqual `
        -Expected @("helm") `
        -Actual @($document.MissingRequiredTools) `
        -Message "Missing direct required tools should not list both schema-validator alternatives as mandatory."
    Assert-Equal `
        -Expected $true `
        -Actual $document.SchemaValidatorRequirement.Required `
        -Message "Raw manifests should require a schema-validator path."
    Assert-Equal `
        -Expected $false `
        -Actual $document.SchemaValidatorRequirement.Satisfied `
        -Message "The schema-validator requirement should not be satisfied with an empty tool path."
    Assert-Equal `
        -Expected "kubeconform or kubectl" `
        -Actual $document.SchemaValidatorRequirement.MissingRequirement `
        -Message "The schema-validator requirement should name the accepted alternatives."
    Assert-SequenceEqual `
        -Expected @() `
        -Actual @($document.SchemaValidatorRequirement.InstalledValidators) `
        -Message "No schema validators should be reported from the empty tool path."
    Assert-Equal `
        -Expected $true `
        -Actual $document.HelmRequirement.Required `
        -Message "The selected web-platform bundle should include Helm validation."
    Assert-Equal `
        -Expected "helm" `
        -Actual $document.HelmRequirement.MissingRequirement `
        -Message "Missing Helm should remain a separate requirement."
    Assert-SequenceEqual `
        -Expected @() `
        -Actual @($document.HelmRequirement.InstalledTools) `
        -Message "No Helm tools should be reported from the empty tool path."
    $kubectlReport = @($document.ToolReport | Where-Object { $_.Tool -eq "kubectl" })[0]
    $kubeconformReport = @($document.ToolReport | Where-Object { $_.Tool -eq "kubeconform" })[0]
    $helmReport = @($document.ToolReport | Where-Object { $_.Tool -eq "helm" })[0]
    Assert-Equal `
        -Expected "schema-validator alternative" `
        -Actual $kubectlReport.RequirementRole `
        -Message "kubectl should be labeled as one accepted schema-validator alternative."
    Assert-Equal `
        -Expected "schema-validator alternative" `
        -Actual $kubeconformReport.RequirementRole `
        -Message "kubeconform should be labeled as one accepted schema-validator alternative."
    Assert-Equal `
        -Expected "required" `
        -Actual $helmReport.RequirementRole `
        -Message "helm should remain a direct required tool for Helm-backed bundles."
    Assert-NotContains `
        -Content ([string]$document.RecommendedValidationCommand) `
        -Unexpected "-ValidateCrdBackedResources" `
        -Message "Default readiness validation should not opt into CRD-backed resources."
    Assert-Contains `
        -Content ([string]$document.RecommendedCrdBackedValidationCommand) `
        -Expected "-ValidateCrdBackedResources" `
        -Message "Readiness JSON should expose CRD-backed validation as an explicit follow-up command."
}

Invoke-Test -Name "Readiness markdown shows grouped missing requirements" -Body {
    $markdown = Invoke-WithEmptyToolPath -Body {
        & $readinessScript `
            -RepoRoot $repoRoot `
            -ValuesFile $publicValuesFile `
            -Profile "web-platform" `
            -Applications @("nginx-web", "httpbin", "whoami") `
            -DataServices @("redis") `
            -Format markdown | Out-String
    }

    Assert-Contains `
        -Content $markdown `
        -Expected "Missing required tool requirements for this bundle: kubeconform or kubectl, helm" `
        -Message "Markdown summary should show missing tool requirements at requirement granularity."
    Assert-Contains `
        -Content $markdown `
        -Expected "Missing direct required tools for this bundle: helm" `
        -Message "Markdown summary should avoid listing both schema-validator alternatives as individually required."
    Assert-Contains `
        -Content $markdown `
        -Expected "| Tool | Installed | Requirement Role | Purpose |" `
        -Message "Markdown tool table should describe each tool role instead of a misleading required flag."
    Assert-Contains `
        -Content $markdown `
        -Expected "| kubectl | no | schema-validator alternative |" `
        -Message "Markdown should label kubectl as a schema-validator alternative."
    Assert-Contains `
        -Content $markdown `
        -Expected "| kubeconform | no | schema-validator alternative |" `
        -Message "Markdown should label kubeconform as a schema-validator alternative."
    Assert-Contains `
        -Content $markdown `
        -Expected "Rendered schema validator: blocked until kubeconform or kubectl is installed" `
        -Message "Markdown should explain the schema-validator alternative."
    Assert-Contains `
        -Content $markdown `
        -Expected "Helm validation: blocked until helm is installed" `
        -Message "Markdown should keep Helm as its own blocked requirement."
    Assert-Contains `
        -Content $markdown `
        -Expected "# Optional after CRD schemas are available:" `
        -Message "Markdown recommended commands should label CRD-backed validation as optional."
    Assert-Contains `
        -Content $markdown `
        -Expected "-ValidateCrdBackedResources" `
        -Message "Markdown should still show the opt-in CRD-backed validation command."
}

Invoke-Test -Name "Readiness resolves relative input paths from the repository root" -Body {
    $outsideRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("validation-readiness-cwd-" + [Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $outsideRoot -Force | Out-Null

    try {
        Push-Location -Path $outsideRoot
        $json = & $readinessScript `
            -RepoRoot $repoRoot `
            -ValuesFile "config/platform-values.env.example" `
            -HelmConfigFile "config/helm-releases.psd1" `
            -Profile "web-platform" `
            -Applications @("nginx-web", "httpbin", "whoami") `
            -DataServices @("redis") `
            -Format json | Out-String
        Pop-Location

        $document = $json | ConvertFrom-Json
        Assert-Equal `
            -Expected ([System.IO.Path]::GetFullPath((Join-Path $repoRoot "config/platform-values.env.example"))) `
            -Actual $document.ValuesFile `
            -Message "Relative values files should resolve from RepoRoot, not the caller working directory."
    }
    finally {
        if ((Get-Location).Path -eq $outsideRoot) {
            Pop-Location
        }

        if (Test-Path -LiteralPath $outsideRoot) {
            Remove-Item -LiteralPath $outsideRoot -Recurse -Force
        }
    }
}

if ($script:TestsFailed -gt 0) {
    throw ("{0} of {1} validation readiness test(s) failed." -f $script:TestsFailed, $script:TestsRun)
}

Write-Host ("All {0} validation readiness test(s) passed." -f $script:TestsRun)
