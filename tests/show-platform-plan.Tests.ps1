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

$repoRoot = (Resolve-Path -Path (Join-Path $PSScriptRoot "..")).Path
$planScript = Join-Path $repoRoot "scripts\show-platform-plan.ps1"

Invoke-Test -Name "Full profile plan expands include-all directories" -Body {
    $document = (& $planScript -RepoRoot $repoRoot -Profile "full" -Format json | Out-String) | ConvertFrom-Json

    $expectedK8sDirectories = @(
        Get-ChildItem -Path (Join-Path $repoRoot "k8s") -Directory |
            Sort-Object Name |
            Select-Object -ExpandProperty Name
    )
    $expectedServiceDirectories = @(
        Get-ChildItem -Path (Join-Path $repoRoot "services") -Directory |
            Sort-Object Name |
            Select-Object -ExpandProperty Name
    )
    $componentDirectories = @($document.Components | Select-Object -ExpandProperty Directory)
    $helmReleaseNames = @($document.HelmReleases | Select-Object -ExpandProperty Name | Sort-Object)
    $optionalManifestPaths = @($document.OptionalManifests | Select-Object -ExpandProperty RelativePath | Sort-Object)

    Assert-SequenceEqual `
        -Expected $expectedK8sDirectories `
        -Actual @($document.K8sDirectories) `
        -Message "The full profile JSON plan should report effective Kubernetes directories."
    Assert-SequenceEqual `
        -Expected $expectedServiceDirectories `
        -Actual @($document.ServiceDirectories) `
        -Message "The full profile JSON plan should report effective service directories."
    Assert-SequenceEqual `
        -Expected $expectedK8sDirectories `
        -Actual $componentDirectories `
        -Message "The full profile components should be built from effective Kubernetes directories."
    Assert-SequenceEqual `
        -Expected @("external-dns", "harbor", "kubernetes-dashboard", "longhorn", "ngf", "vertical-pod-autoscaler") `
        -Actual $helmReleaseNames `
        -Message "The full profile should expose all Helm catalog entries that belong to included directories."
    Assert-SequenceEqual `
        -Expected @(
            "k8s\311_platform_kubernetes-dashboard\sample-admin-user.yaml",
            "k8s\311_platform_kubernetes-dashboard\sample-viewer-user.yaml",
            "k8s\312_platform_vertical-pod-autoscaler\example-nginx-web-vpa.yaml"
        ) `
        -Actual $optionalManifestPaths `
        -Message "The full profile should expose optional manifests for included directories."
    Assert-True `
        -Condition (@($document.RawPhases).Count -gt 0) `
        -Message "The full profile should include raw manifest phases."
}

if ($script:TestsFailed -gt 0) {
    throw ("{0} of {1} show-platform-plan test(s) failed." -f $script:TestsFailed, $script:TestsRun)
}

Write-Host ("All {0} show-platform-plan test(s) passed." -f $script:TestsRun)
