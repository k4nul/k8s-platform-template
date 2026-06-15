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
$platformAssetsValidation = Join-Path $repoRoot "scripts\validate-platform-assets.ps1"
$renderMatrixValidation = Join-Path $repoRoot "scripts\validate-render-matrix.ps1"

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

Invoke-Test -Name "Resolve-RenderMatrixRepoPath keeps absolute paths and roots relative paths" -Body {
    $relativePath = "config\platform-values.env.example"
    $absolutePath = Join-Path $repoRoot $relativePath

    Assert-Equal `
        -Expected ([System.IO.Path]::GetFullPath($absolutePath)) `
        -Actual (Resolve-RenderMatrixRepoPath -Root $repoRoot -Path $absolutePath) `
        -Message "Absolute matrix values paths should not be rooted twice."

    Assert-Equal `
        -Expected ([System.IO.Path]::GetFullPath($absolutePath)) `
        -Actual (Resolve-RenderMatrixRepoPath -Root $repoRoot -Path $relativePath) `
        -Message "Relative matrix values paths should resolve from the repository root."
}

Invoke-Test -Name "Profile render matrix requires explicit public validation selections" -Body {
    $failed = $false

    try {
        Get-RequiredProfileMatrixList `
            -Definition @{ Description = "Missing validation metadata" } `
            -ProfileName "custom-profile" `
            -Key "ValidationApplications" | Out-Null
    }
    catch {
        $failed = $true
        Assert-Contains `
            -Content $_.Exception.Message `
            -Expected "Profile 'custom-profile' is missing 'ValidationApplications'" `
            -Message "Missing profile application metadata should be rejected."
        Assert-Contains `
            -Content $_.Exception.Message `
            -Expected "config/profiles/custom-profile.psd1" `
            -Message "The failure should point maintainers to the profile metadata file."
    }

    Assert-True -Condition $failed -Message "Profiles without explicit validation applications should fail matrix construction."
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

    $profileDefinitions = Get-PlatformProfileDefinitions -ProfileDirectory (Join-Path $repoRoot "config\profiles")
    foreach ($profileName in $expectedProfileNames) {
        $definition = $profileDefinitions[$profileName]
        $entry = $entriesByName[$profileName]

        Assert-SequenceEqual `
            -Expected @(ConvertTo-RenderMatrixList -Values @($definition["ValidationApplications"])) `
            -Actual @($entry.Applications) `
            -Message ("{0} should derive validation applications from profile metadata." -f $profileName)
        Assert-SequenceEqual `
            -Expected @(ConvertTo-RenderMatrixList -Values @($definition["ValidationDataServices"])) `
            -Actual @($entry.DataServices) `
            -Message ("{0} should derive validation data services from profile metadata." -f $profileName)
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

Invoke-Test -Name "Combined render validation matrix is ordered and overrideable" -Body {
    $defaultValuesFile = "config\platform-values.env.example"
    $entries = @(Get-RenderValidationMatrix -Root $repoRoot -DefaultValuesFile $defaultValuesFile)
    $expectedEnvironmentNames = @(
        Get-ChildItem -Path (Join-Path $repoRoot "config\environments") -File -Filter "*.psd1" |
            Sort-Object BaseName |
            Select-Object -ExpandProperty BaseName
    )
    $expectedProfileNames = @(
        Get-ProfileRenderMatrix -ValuesFile $defaultValuesFile |
            Select-Object -ExpandProperty Name
    )
    $expectedNames = @($expectedEnvironmentNames) + @($expectedProfileNames)
    $expectedScopes = @()

    foreach ($name in $expectedEnvironmentNames) {
        $expectedScopes += "environment"
    }

    foreach ($name in $expectedProfileNames) {
        $expectedScopes += "profile"
    }

    Assert-SequenceEqual -Expected $expectedNames -Actual @($entries | Select-Object -ExpandProperty Name) -Message "Combined matrix names should list environments before profiles."
    Assert-SequenceEqual -Expected $expectedScopes -Actual @($entries | Select-Object -ExpandProperty Scope) -Message "Combined matrix scopes should preserve the environment/profile split."

    $overrideEntries = @(Get-RenderValidationMatrix -Root $repoRoot -DefaultValuesFile $defaultValuesFile -ValuesFile "custom.env")
    foreach ($entry in $overrideEntries) {
        Assert-Equal -Expected "custom.env" -Actual $entry.ValuesFile -Message ("{0} should use the explicit values file override." -f $entry.Name)
    }
}

Invoke-Test -Name "Render matrix validation fails before rendering when a matrix values file is missing" -Body {
    $missingValuesFile = "config\missing-public-values.env"
    $resolvedMissingValuesFile = Resolve-RenderMatrixRepoPath -Root $repoRoot -Path $missingValuesFile
    $failed = $false

    try {
        & $renderMatrixValidation `
            -RepoRoot $repoRoot `
            -ValuesFile $missingValuesFile 3>&1 2>&1 | Out-String | Out-Null
    }
    catch {
        $failed = $true
        Assert-Contains `
            -Content $_.Exception.Message `
            -Expected "Render matrix values file was not found" `
            -Message "Missing values files should fail before any render attempt."
        Assert-Contains `
            -Content $_.Exception.Message `
            -Expected $resolvedMissingValuesFile `
            -Message "The failure should include the resolved missing values file path."
    }

    Assert-True -Condition $failed -Message "Render matrix validation should fail when the selected values file is absent."
}

Invoke-Test -Name "Strict platform asset validation promotes selection warnings before rendering" -Body {
    $failed = $false

    try {
        & $platformAssetsValidation `
            -RepoRoot $repoRoot `
            -ValuesFile "config\platform-values.env.example" `
            -Profile "minimal-application" `
            -Applications @("nginx-web", "whoami") `
            -DataServices @() `
            -Strict 3>&1 2>&1 | Out-String | Out-Null
    }
    catch {
        $failed = $true
        Assert-Contains `
            -Content $_.Exception.Message `
            -Expected "Warnings promoted to errors" `
            -Message "Strict asset validation should forward strict mode to platform selection."
        Assert-Contains `
            -Content $_.Exception.Message `
            -Expected "missing recommended Kubernetes add-ons" `
            -Message "Strict asset validation should fail on selection warnings before rendered schema validation."
    }

    Assert-True -Condition $failed -Message "Strict asset validation should fail on public profile selection warnings."
}

if ($script:TestsFailed -gt 0) {
    throw ("{0} of {1} render matrix test(s) failed." -f $script:TestsFailed, $script:TestsRun)
}

Write-Host ("All {0} render matrix test(s) passed." -f $script:TestsRun)
