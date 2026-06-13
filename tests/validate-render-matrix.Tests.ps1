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

function Assert-False {
    param(
        [bool]$Condition,
        [string]$Message
    )

    if ($Condition) {
        throw $Message
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
. (Join-Path $repoRoot "scripts\render-matrix-catalog.ps1")

Invoke-Test -Name "ConvertTo-RenderMatrixList trims comma-delimited values and skips blanks" -Body {
    $actual = @(
        ConvertTo-RenderMatrixList -Values @(
            "nginx-web, httpbin",
            $null,
            "",
            " whoami ",
            "mysql,postgresql, redis"
        )
    )

    Assert-SequenceEqual `
        -Expected @("nginx-web", "httpbin", "whoami", "mysql", "postgresql", "redis") `
        -Actual $actual `
        -Message "Normalized matrix list should preserve input order after trimming."
}

Invoke-Test -Name "New-RenderMatrixEntry normalizes applications, data services, and flags" -Body {
    $entry = New-RenderMatrixEntry `
        -Scope "profile" `
        -Name "custom" `
        -ValuesFile "config\platform-values.env.example" `
        -Version "9.9.9-test" `
        -Profile "web-platform" `
        -Applications @("nginx-web,httpbin", " whoami ") `
        -DataServices @("postgresql, redis") `
        -IncludeJenkins

    Assert-Equal -Expected "profile" -Actual $entry.Scope -Message "Scope should be retained."
    Assert-Equal -Expected "custom" -Actual $entry.Name -Message "Name should be retained."
    Assert-Equal -Expected "config\platform-values.env.example" -Actual $entry.ValuesFile -Message "Values file should be retained."
    Assert-Equal -Expected "9.9.9-test" -Actual $entry.Version -Message "Version should be retained."
    Assert-Equal -Expected "web-platform" -Actual $entry.Profile -Message "Profile should be retained."
    Assert-SequenceEqual -Expected @("nginx-web", "httpbin", "whoami") -Actual @($entry.Applications) -Message "Applications should be normalized."
    Assert-SequenceEqual -Expected @("postgresql", "redis") -Actual @($entry.DataServices) -Message "Data services should be normalized."
    Assert-Equal -Expected $true -Actual $entry.IncludeJenkins -Message "IncludeJenkins should be true."
}

Invoke-Test -Name "Profile render matrix covers every configured public profile" -Body {
    $valuesFile = "config\platform-values.env.example"
    $entries = @(Get-ProfileRenderMatrix -ValuesFile $valuesFile)
    $expectedProfileNames = @(
        Get-ChildItem -Path (Join-Path $repoRoot "config\profiles") -File -Filter "*.psd1" |
            Sort-Object BaseName |
            Select-Object -ExpandProperty BaseName
    )
    $actualProfileNames = @($entries | Sort-Object Name | Select-Object -ExpandProperty Name)

    Assert-SequenceEqual -Expected $expectedProfileNames -Actual $actualProfileNames -Message "Profile matrix names should match config/profiles."

    $entriesByName = @{}
    foreach ($entry in $entries) {
        Assert-Equal -Expected "profile" -Actual $entry.Scope -Message ("{0} should be a profile matrix entry." -f $entry.Name)
        Assert-Equal -Expected $valuesFile -Actual $entry.ValuesFile -Message ("{0} should use the requested values file." -f $entry.Name)
        Assert-False -Condition $entry.IncludeJenkins -Message ("{0} should not opt into Jenkins by default." -f $entry.Name)
        $entriesByName[$entry.Name] = $entry
    }

    Assert-SequenceEqual -Expected @("nginx-web", "whoami") -Actual @($entriesByName["minimal-application"].Applications) -Message "Minimal profile application defaults should stay public and small."
    Assert-SequenceEqual -Expected @() -Actual @($entriesByName["minimal-application"].DataServices) -Message "Minimal profile should not add data services."
    Assert-SequenceEqual -Expected @("nginx-web", "httpbin", "whoami") -Actual @($entriesByName["web-platform"].Applications) -Message "Web platform profile should render public web demo apps."
    Assert-SequenceEqual -Expected @("redis") -Actual @($entriesByName["web-platform"].DataServices) -Message "Web platform profile should include Redis."
    Assert-SequenceEqual -Expected @("nginx-web", "httpbin", "whoami", "adminer") -Actual @($entriesByName["full"].Applications) -Message "Full profile matrix should render all public app examples."
    Assert-SequenceEqual -Expected @("mysql", "postgresql", "redis") -Actual @($entriesByName["full"].DataServices) -Message "Full profile matrix should render all public data services."
}

Invoke-Test -Name "Environment render matrix prefers validation values and supports override values" -Body {
    $defaultValuesFile = "config\platform-values.env.example"
    $entries = @(Get-EnvironmentRenderMatrix -Root $repoRoot -DefaultValuesFile $defaultValuesFile)
    $expectedEnvironmentNames = @(
        Get-ChildItem -Path (Join-Path $repoRoot "config\environments") -File -Filter "*.psd1" |
            Sort-Object BaseName |
            Select-Object -ExpandProperty BaseName
    )
    $actualEnvironmentNames = @($entries | Sort-Object Name | Select-Object -ExpandProperty Name)

    Assert-SequenceEqual -Expected $expectedEnvironmentNames -Actual $actualEnvironmentNames -Message "Environment matrix names should match config/environments."

    $entriesByName = @{}
    foreach ($entry in $entries) {
        Assert-Equal -Expected "environment" -Actual $entry.Scope -Message ("{0} should be an environment matrix entry." -f $entry.Name)
        Assert-Equal -Expected $defaultValuesFile -Actual $entry.ValuesFile -Message ("{0} should prefer ValidationValuesFile for public validation." -f $entry.Name)
        $entriesByName[$entry.Name] = $entry
    }

    Assert-Equal -Expected "web-platform" -Actual $entriesByName["dev"].Profile -Message "Dev preset should render the web platform profile."
    Assert-SequenceEqual -Expected @("nginx-web", "httpbin", "whoami") -Actual @($entriesByName["dev"].Applications) -Message "Dev preset applications should be normalized."
    Assert-SequenceEqual -Expected @("redis") -Actual @($entriesByName["dev"].DataServices) -Message "Dev preset data services should be normalized."
    Assert-Equal -Expected "shared-services" -Actual $entriesByName["prod"].Profile -Message "Prod preset should render the shared services profile."
    Assert-SequenceEqual -Expected @("postgresql", "redis") -Actual @($entriesByName["prod"].DataServices) -Message "Prod preset data services should be normalized."

    $overrideEntries = @(Get-EnvironmentRenderMatrix -Root $repoRoot -DefaultValuesFile $defaultValuesFile -OverrideValuesFile "custom.env")
    foreach ($entry in $overrideEntries) {
        Assert-Equal -Expected "custom.env" -Actual $entry.ValuesFile -Message ("{0} should use the explicit values file override." -f $entry.Name)
    }
}

if ($script:TestsFailed -gt 0) {
    throw ("{0} of {1} render matrix test(s) failed." -f $script:TestsFailed, $script:TestsRun)
}

Write-Host ("All {0} render matrix test(s) passed." -f $script:TestsRun)
