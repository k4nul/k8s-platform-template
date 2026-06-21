Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$script:TestsRun = 0
$script:TestsFailed = 0

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
$dependencyPlanScript = Join-Path $repoRoot "scripts\show-service-dependency-plan.ps1"

Invoke-Test -Name "Dependency markdown exposes selected service image provenance" -Body {
    $markdown = & $dependencyPlanScript `
        -RepoRoot $repoRoot `
        -Profile web-platform `
        -Applications nginx-web,httpbin,whoami `
        -DataServices redis `
        -Format markdown | Out-String

    foreach ($imageReference in @(
        "mccutchen/go-httpbin:v2.15.0",
        "nginx:1.28-alpine",
        "traefik/whoami:v1.10.4"
    )) {
        Assert-Contains `
            -Content $markdown `
            -Expected ("- Build public image: {0}" -f $imageReference) `
            -Message "Dependency markdown should expose build image provenance."
        Assert-Contains `
            -Content $markdown `
            -Expected ("- Runtime public image: {0}" -f $imageReference) `
            -Message "Dependency markdown should expose runtime image provenance."
    }

    Assert-Contains `
        -Content $markdown `
        -Expected "- Image provenance status: catalog-aligned" `
        -Message "Dependency markdown should report aligned public image catalogs."
}

Invoke-Test -Name "Dependency JSON exposes Helm source and version-pin status" -Body {
    $document = (& $dependencyPlanScript -RepoRoot $repoRoot -Profile full -Format json | Out-String) | ConvertFrom-Json
    $releaseMap = @{}
    foreach ($release in @($document.HelmReleases)) {
        $releaseMap[$release.Name] = $release
    }

    Assert-Equal `
        -Expected "helm-repo" `
        -Actual $releaseMap["external-dns"].ChartSourceType `
        -Message "ExternalDNS should report a Helm repository source."
    Assert-Equal `
        -Expected "oci" `
        -Actual $releaseMap["ngf"].ChartSourceType `
        -Message "NGINX Gateway Fabric should report an OCI chart source."
    Assert-Equal `
        -Expected "unpinned" `
        -Actual $releaseMap["harbor"].VersionPinStatus `
        -Message "Enabled chart references without ChartVersion should be flagged as unpinned."
    Assert-Equal `
        -Expected "k8s\307_platform_harbor\values.yaml" `
        -Actual $releaseMap["harbor"].ValuesRelativePath `
        -Message "Helm dependency output should expose the local values file path."
    Assert-Equal `
        -Expected "present" `
        -Actual $releaseMap["harbor"].ValuesFileStatus `
        -Message "Helm dependency output should verify that local values files exist."
    Assert-Equal `
        -Expected "not-configured" `
        -Actual $releaseMap["vertical-pod-autoscaler"].VersionPinStatus `
        -Message "Disabled scaffold chart references should remain not configured."
    Assert-Equal `
        -Expected "present" `
        -Actual $releaseMap["vertical-pod-autoscaler"].ValuesFileStatus `
        -Message "Disabled scaffold chart entries should still report local values-file status."
}

if ($script:TestsFailed -gt 0) {
    throw ("{0} of {1} service dependency plan test(s) failed." -f $script:TestsFailed, $script:TestsRun)
}

Write-Host ("All {0} service dependency plan test(s) passed." -f $script:TestsRun)
