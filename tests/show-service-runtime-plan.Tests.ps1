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
$runtimePlanScript = Join-Path $repoRoot "scripts\show-service-runtime-plan.ps1"

Invoke-Test -Name "Runtime markdown shows public image references from the catalog" -Body {
    $markdown = & $runtimePlanScript -RepoRoot $repoRoot -Format markdown | Out-String

    foreach ($imageReference in @(
        "adminer:5.3.0-standalone",
        "mccutchen/go-httpbin:v2.15.0",
        "nginx:1.28-alpine",
        "traefik/whoami:v1.10.4"
    )) {
        Assert-Contains `
            -Content $markdown `
            -Expected ("- Image reference: {0}" -f $imageReference) `
            -Message "Runtime markdown should expose the public image inventory."
    }

    Assert-NotContains `
        -Content $markdown `
        -Unexpected "- Image reference: not specified" `
        -Message "Runtime markdown should not hide cataloged public images."
}

Invoke-Test -Name "Runtime text output shows selected public image references" -Body {
    $text = & $runtimePlanScript -RepoRoot $repoRoot -ServiceNames nginx-web,whoami | Out-String

    Assert-Contains `
        -Content $text `
        -Expected "Image reference: nginx:1.28-alpine" `
        -Message "Text output should show the selected nginx-web public image."
    Assert-Contains `
        -Content $text `
        -Expected "Image reference: traefik/whoami:v1.10.4" `
        -Message "Text output should show the selected whoami public image."
    Assert-NotContains `
        -Content $text `
        -Unexpected "Image reference: not specified" `
        -Message "Text output should not hide selected public images."
}

if ($script:TestsFailed -gt 0) {
    throw ("{0} of {1} service runtime plan test(s) failed." -f $script:TestsFailed, $script:TestsRun)
}

Write-Host ("All {0} service runtime plan test(s) passed." -f $script:TestsRun)
