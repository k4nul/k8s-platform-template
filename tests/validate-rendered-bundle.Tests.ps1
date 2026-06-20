Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$script:TestsRun = 0
$script:TestsFailed = 0

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
        throw ("{0} Did not expect to find '{1}'." -f $Message, $Unexpected)
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

function New-TestRenderedBundle {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Root
    )

    $k8sRoot = Join-Path $Root "k8s"
    New-Item -ItemType Directory -Path $k8sRoot -Force | Out-Null
    Set-Content `
        -Path (Join-Path $k8sRoot "configmap.yaml") `
        -Value "apiVersion: v1`nkind: ConfigMap`nmetadata:`n  name: rendered-validator-test`n" `
        -NoNewline
}

function New-TestYamlFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Root,

        [Parameter(Mandatory = $true)]
        [string]$RelativePath,

        [Parameter(Mandatory = $true)]
        [string]$Content
    )

    $filePath = Join-Path $Root $RelativePath
    $directory = Split-Path -Path $filePath -Parent
    if ($directory) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    Set-Content -Path $filePath -Value $Content -NoNewline
}

function New-TestRenderedBundleWithMixedTargets {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Root
    )

    New-TestYamlFile `
        -Root $Root `
        -RelativePath "k8s\configmap.yaml" `
        -Content "apiVersion: v1`nkind: ConfigMap`nmetadata:`n  name: rendered-validator-test`n"
    New-TestYamlFile `
        -Root $Root `
        -RelativePath "k8s\chart\values.yaml" `
        -Content "replicaCount: 1`n"
    New-TestYamlFile `
        -Root $Root `
        -RelativePath "k8s\custom-resource.yaml" `
        -Content "apiVersion: example.platform.test/v1`nkind: ExampleResource`nmetadata:`n  name: crd-backed-test`n"
    New-TestYamlFile `
        -Root $Root `
        -RelativePath "cluster-bootstrap\namespaces\platform.yaml" `
        -Content "apiVersion: v1`nkind: Namespace`nmetadata:`n  name: platform`n"
    New-TestYamlFile `
        -Root $Root `
        -RelativePath "cluster-bootstrap\secrets\platform\secret.yaml" `
        -Content "apiVersion: v1`nkind: Secret`nmetadata:`n  name: placeholder-secret`ntype: Opaque`nstringData:`n  password: change-me`n"
}

function Invoke-WithEmptyToolPath {
    param(
        [Parameter(Mandatory = $true)]
        [scriptblock]$Body
    )

    $previousPath = $env:PATH
    $toolPath = Join-Path ([System.IO.Path]::GetTempPath()) ("rendered-validator-tools-" + [Guid]::NewGuid().ToString("N"))

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

function Invoke-WithToolPath {
    param(
        [Parameter(Mandatory = $true)]
        [scriptblock]$Body
    )

    $previousPath = $env:PATH
    $toolPath = Join-Path ([System.IO.Path]::GetTempPath()) ("rendered-validator-tools-" + [Guid]::NewGuid().ToString("N"))

    try {
        New-Item -ItemType Directory -Path $toolPath -Force | Out-Null
        $env:PATH = $toolPath
        & $Body -ToolPath $toolPath
    }
    finally {
        $env:PATH = $previousPath
        if (Test-Path -LiteralPath $toolPath) {
            Remove-Item -LiteralPath $toolPath -Recurse -Force
        }
    }
}

function New-TestValidatorTool {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ToolPath,

        [Parameter(Mandatory = $true)]
        [string]$Name,

        [int]$ExitCode = 0
    )

    $toolFile = Join-Path $ToolPath $Name
    Set-Content `
        -Path $toolFile `
        -Value @(
            "#!/bin/sh",
            "printf '%s %s\n' '$Name' ""`$*"" >> ""`$RENDERED_VALIDATOR_LOG""",
            "exit $ExitCode"
        )
    & /bin/chmod +x $toolFile
}

$repoRoot = (Resolve-Path -Path (Join-Path $PSScriptRoot "..")).Path
$validateRenderedScript = Join-Path $repoRoot "scripts\validate-rendered-bundle.ps1"

Invoke-Test -Name "Rendered bundle validation skips schema validation without tools in non-strict mode" -Body {
    $testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("rendered-validator-test-" + [Guid]::NewGuid().ToString("N"))

    try {
        New-TestRenderedBundle -Root $testRoot

        Invoke-WithEmptyToolPath -Body {
            $output = (& $validateRenderedScript -RenderedPath $testRoot 6>&1 3>&1 2>&1 | Out-String)
            Assert-Contains -Content $output -Expected "Skipping rendered manifest validation" -Message "Non-strict validation should explain the skipped schema gate."
            Assert-Contains -Content $output -Expected "Built-in rendered manifest structural preflight" -Message "Non-strict validation should still run a repository-local structural preflight."
            Assert-Contains -Content $output -Expected "Structurally validated Kubernetes manifests: 1" -Message "The structural preflight should validate the rendered Kubernetes manifest target."
        }
    }
    finally {
        if (Test-Path -LiteralPath $testRoot) {
            Remove-Item -LiteralPath $testRoot -Recurse -Force
        }
    }
}

Invoke-Test -Name "Rendered bundle validation structural preflight reports malformed YAML targets" -Body {
    $testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("rendered-validator-test-" + [Guid]::NewGuid().ToString("N"))

    try {
        New-TestYamlFile `
            -Root $testRoot `
            -RelativePath "k8s\configmap.yaml" `
            -Content "apiVersion: v1`nkind: ConfigMap`nmetadata:`n  labels:`n    app: malformed`n"

        $failed = Invoke-WithEmptyToolPath -Body {
            try {
                $output = & $validateRenderedScript -RenderedPath $testRoot 6>&1 3>&1 2>&1
                $outputText = ($output | Out-String)
                Assert-Contains -Content $outputText -Expected "k8s/configmap.yaml" -Message "Structural preflight output should include the malformed relative YAML path."
                return $false
            }
            catch {
                Assert-Contains -Content $_.Exception.Message -Expected "Rendered manifest structural preflight failed" -Message "Malformed YAML should fail the built-in structural preflight."
                return $true
            }
        }

        Assert-True -Condition $failed -Message "A malformed rendered manifest should fail without requiring external schema tools."
    }
    finally {
        if (Test-Path -LiteralPath $testRoot) {
            Remove-Item -LiteralPath $testRoot -Recurse -Force
        }
    }
}

Invoke-Test -Name "Rendered bundle structural preflight accepts shared YAML metadata parsing" -Body {
    $testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("rendered-validator-test-" + [Guid]::NewGuid().ToString("N"))

    try {
        New-TestYamlFile `
            -Root $testRoot `
            -RelativePath "k8s\configmap.yaml" `
            -Content "# rendered test document`n--- # first document`napiVersion: v1 # built-in API`nkind: ConfigMap`nmetadata:`n  name: &config_name 'rendered-validator-test'`n---`n# comment-only document`n"

        Invoke-WithEmptyToolPath -Body {
            $output = (& $validateRenderedScript -RenderedPath $testRoot 6>&1 3>&1 2>&1 | Out-String)
            Assert-Contains -Content $output -Expected "Structurally validated Kubernetes manifests: 1" -Message "Shared metadata parser should support comments, quoted scalar values, anchors, and comment-only documents."
        }
    }
    finally {
        if (Test-Path -LiteralPath $testRoot) {
            Remove-Item -LiteralPath $testRoot -Recurse -Force
        }
    }
}

Invoke-Test -Name "Rendered bundle structural preflight skips CRD-backed resources by default" -Body {
    $testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("rendered-validator-test-" + [Guid]::NewGuid().ToString("N"))

    try {
        New-TestRenderedBundleWithMixedTargets -Root $testRoot

        Invoke-WithEmptyToolPath -Body {
            $output = (& $validateRenderedScript -RenderedPath $testRoot 6>&1 3>&1 2>&1 | Out-String)

            Assert-Contains -Content $output -Expected "Structurally validated Kubernetes manifests: 1" -Message "Structural preflight should validate built-in Kubernetes manifests."
            Assert-Contains -Content $output -Expected "Skipped rendered YAML files: 1" -Message "Structural preflight should report skipped CRD-backed manifests."
            Assert-Contains -Content $output -Expected "k8s/custom-resource.yaml" -Message "Structural preflight skip output should include the CRD-backed relative path."
        }
    }
    finally {
        if (Test-Path -LiteralPath $testRoot) {
            Remove-Item -LiteralPath $testRoot -Recurse -Force
        }
    }
}

Invoke-Test -Name "Rendered bundle validation fails without tools in strict mode" -Body {
    $testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("rendered-validator-test-" + [Guid]::NewGuid().ToString("N"))

    try {
        New-TestRenderedBundle -Root $testRoot

        $failed = Invoke-WithEmptyToolPath -Body {
            try {
                & $validateRenderedScript -RenderedPath $testRoot -Strict 3>&1 2>&1 | Out-String | Out-Null
                return $false
            }
            catch {
                Assert-Contains -Content $_.Exception.Message -Expected "kubeconform or kubectl is required" -Message "Strict validation should require an offline schema validator or kubectl."
                return $true
            }
        }

        Assert-True -Condition $failed -Message "Strict validation should fail when no rendered manifest validator is installed."
    }
    finally {
        if (Test-Path -LiteralPath $testRoot) {
            Remove-Item -LiteralPath $testRoot -Recurse -Force
        }
    }
}

Invoke-Test -Name "Rendered bundle validation fails clearly when requested kubectl is missing" -Body {
    $testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("rendered-validator-test-" + [Guid]::NewGuid().ToString("N"))

    try {
        New-TestRenderedBundle -Root $testRoot

        $failed = Invoke-WithEmptyToolPath -Body {
            try {
                & $validateRenderedScript -RenderedPath $testRoot -SchemaValidator kubectl -Strict 3>&1 2>&1 | Out-String | Out-Null
                return $false
            }
            catch {
                Assert-Contains -Content $_.Exception.Message -Expected "kubectl is required" -Message "Requested kubectl validation should fail with a validator-specific message."
                return $true
            }
        }

        Assert-True -Condition $failed -Message "Strict requested kubectl validation should fail when kubectl is not installed."
    }
    finally {
        if (Test-Path -LiteralPath $testRoot) {
            Remove-Item -LiteralPath $testRoot -Recurse -Force
        }
    }
}

Invoke-Test -Name "Rendered bundle validation auto mode prefers kubeconform over kubectl" -Body {
    $testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("rendered-validator-test-" + [Guid]::NewGuid().ToString("N"))
    $logPath = Join-Path ([System.IO.Path]::GetTempPath()) ("rendered-validator-log-" + [Guid]::NewGuid().ToString("N") + ".txt")

    try {
        New-TestRenderedBundle -Root $testRoot

        Invoke-WithToolPath -Body {
            param([string]$ToolPath)

            New-TestValidatorTool -ToolPath $ToolPath -Name "kubeconform"
            New-TestValidatorTool -ToolPath $ToolPath -Name "kubectl"
            $env:RENDERED_VALIDATOR_LOG = $logPath

            $output = (& $validateRenderedScript -RenderedPath $testRoot 6>&1 3>&1 2>&1 | Out-String)
            $logContent = Get-Content -Path $logPath -Raw

            Assert-Contains -Content $output -Expected "Rendered manifest validator: kubeconform" -Message "Auto mode should choose kubeconform when both validators are available."
            Assert-Contains -Content $logContent -Expected "kubeconform -strict -summary" -Message "kubeconform should receive strict summary arguments."
            Assert-NotContains -Content $logContent -Unexpected "kubectl apply" -Message "kubectl should not run when kubeconform is available."
        }
    }
    finally {
        if (Test-Path -LiteralPath $testRoot) {
            Remove-Item -LiteralPath $testRoot -Recurse -Force
        }
        if (Test-Path -LiteralPath $logPath) {
            Remove-Item -LiteralPath $logPath -Force
        }
        Remove-Item Env:RENDERED_VALIDATOR_LOG -ErrorAction SilentlyContinue
    }
}

Invoke-Test -Name "Rendered bundle validation auto mode falls back to kubectl" -Body {
    $testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("rendered-validator-test-" + [Guid]::NewGuid().ToString("N"))
    $logPath = Join-Path ([System.IO.Path]::GetTempPath()) ("rendered-validator-log-" + [Guid]::NewGuid().ToString("N") + ".txt")

    try {
        New-TestRenderedBundle -Root $testRoot

        Invoke-WithToolPath -Body {
            param([string]$ToolPath)

            New-TestValidatorTool -ToolPath $ToolPath -Name "kubectl"
            $env:RENDERED_VALIDATOR_LOG = $logPath

            $output = (& $validateRenderedScript -RenderedPath $testRoot 6>&1 3>&1 2>&1 | Out-String)
            $logContent = Get-Content -Path $logPath -Raw

            Assert-Contains -Content $output -Expected "Rendered manifest validator: kubectl" -Message "Auto mode should choose kubectl when kubeconform is absent."
            Assert-Contains -Content $logContent -Expected "kubectl apply --dry-run=client --validate=true -f" -Message "kubectl should receive client dry-run validation arguments."
        }
    }
    finally {
        if (Test-Path -LiteralPath $testRoot) {
            Remove-Item -LiteralPath $testRoot -Recurse -Force
        }
        if (Test-Path -LiteralPath $logPath) {
            Remove-Item -LiteralPath $logPath -Force
        }
        Remove-Item Env:RENDERED_VALIDATOR_LOG -ErrorAction SilentlyContinue
    }
}

Invoke-Test -Name "Rendered bundle validation targets Kubernetes and bootstrap YAML while skipping CRDs by default" -Body {
    $testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("rendered-validator-test-" + [Guid]::NewGuid().ToString("N"))
    $logPath = Join-Path ([System.IO.Path]::GetTempPath()) ("rendered-validator-log-" + [Guid]::NewGuid().ToString("N") + ".txt")

    try {
        New-TestRenderedBundleWithMixedTargets -Root $testRoot

        Invoke-WithToolPath -Body {
            param([string]$ToolPath)

            New-TestValidatorTool -ToolPath $ToolPath -Name "kubeconform"
            $env:RENDERED_VALIDATOR_LOG = $logPath

            & $validateRenderedScript -RenderedPath $testRoot 6>&1 3>&1 2>&1 | Out-String | Out-Null
            $logContent = Get-Content -Path $logPath -Raw

            Assert-Contains -Content $logContent -Expected "configmap.yaml" -Message "Built-in Kubernetes manifests should be passed to the validator."
            Assert-Contains -Content $logContent -Expected "platform.yaml" -Message "Bootstrap namespace YAML should be passed to the validator."
            Assert-Contains -Content $logContent -Expected "secret.yaml" -Message "Bootstrap secret YAML should be passed to the validator."
            Assert-NotContains -Content $logContent -Unexpected "values.yaml" -Message "Helm values files should not be schema validation targets."
            Assert-NotContains -Content $logContent -Unexpected "custom-resource.yaml" -Message "CRD-backed resources should not be passed to validators by default."
        }
    }
    finally {
        if (Test-Path -LiteralPath $testRoot) {
            Remove-Item -LiteralPath $testRoot -Recurse -Force
        }
        if (Test-Path -LiteralPath $logPath) {
            Remove-Item -LiteralPath $logPath -Force
        }
        Remove-Item Env:RENDERED_VALIDATOR_LOG -ErrorAction SilentlyContinue
    }
}

Invoke-Test -Name "Rendered bundle validation includes CRD-backed resources when requested" -Body {
    $testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("rendered-validator-test-" + [Guid]::NewGuid().ToString("N"))
    $logPath = Join-Path ([System.IO.Path]::GetTempPath()) ("rendered-validator-log-" + [Guid]::NewGuid().ToString("N") + ".txt")

    try {
        New-TestRenderedBundleWithMixedTargets -Root $testRoot

        Invoke-WithToolPath -Body {
            param([string]$ToolPath)

            New-TestValidatorTool -ToolPath $ToolPath -Name "kubeconform"
            $env:RENDERED_VALIDATOR_LOG = $logPath

            $output = (& $validateRenderedScript -RenderedPath $testRoot -ValidateCrdBackedResources 6>&1 3>&1 2>&1 | Out-String)
            $logContent = Get-Content -Path $logPath -Raw

            Assert-Contains -Content $output -Expected "Validated Kubernetes manifests: 2" -Message "CRD-backed resources should be included when requested."
            Assert-Contains -Content $logContent -Expected "custom-resource.yaml" -Message "The CRD-backed manifest should be passed to the validator when requested."
            Assert-NotContains -Content $output -Unexpected "Skipped rendered YAML files" -Message "No rendered YAML should be skipped when CRD-backed validation is requested."
        }
    }
    finally {
        if (Test-Path -LiteralPath $testRoot) {
            Remove-Item -LiteralPath $testRoot -Recurse -Force
        }
        if (Test-Path -LiteralPath $logPath) {
            Remove-Item -LiteralPath $logPath -Force
        }
        Remove-Item Env:RENDERED_VALIDATOR_LOG -ErrorAction SilentlyContinue
    }
}

Invoke-Test -Name "Rendered bundle validation reports failing relative YAML paths" -Body {
    $testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("rendered-validator-test-" + [Guid]::NewGuid().ToString("N"))
    $logPath = Join-Path ([System.IO.Path]::GetTempPath()) ("rendered-validator-log-" + [Guid]::NewGuid().ToString("N") + ".txt")

    try {
        New-TestRenderedBundle -Root $testRoot

        $failed = Invoke-WithToolPath -Body {
            param([string]$ToolPath)

            New-TestValidatorTool -ToolPath $ToolPath -Name "kubeconform" -ExitCode 1
            $env:RENDERED_VALIDATOR_LOG = $logPath

            try {
                $output = & $validateRenderedScript -RenderedPath $testRoot 6>&1 3>&1 2>&1
                $outputText = ($output | Out-String)
                Assert-Contains -Content $outputText -Expected "k8s/configmap.yaml" -Message "Failed validation output should include the relative YAML path."
                return $false
            }
            catch {
                Assert-Contains -Content $_.Exception.Message -Expected "Rendered manifest validation failed" -Message "Validator failures should throw the rendered manifest failure message."
                return $true
            }
        }

        Assert-True -Condition $failed -Message "A failing external validator should fail rendered bundle validation."
    }
    finally {
        if (Test-Path -LiteralPath $testRoot) {
            Remove-Item -LiteralPath $testRoot -Recurse -Force
        }
        if (Test-Path -LiteralPath $logPath) {
            Remove-Item -LiteralPath $logPath -Force
        }
        Remove-Item Env:RENDERED_VALIDATOR_LOG -ErrorAction SilentlyContinue
    }
}

if ($script:TestsFailed -gt 0) {
    throw ("{0} of {1} rendered bundle validator test(s) failed." -f $script:TestsFailed, $script:TestsRun)
}

Write-Host ("All {0} rendered bundle validator test(s) passed." -f $script:TestsRun)
