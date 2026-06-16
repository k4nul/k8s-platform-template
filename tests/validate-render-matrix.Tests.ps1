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

function Invoke-WithEmptyToolPath {
    param(
        [Parameter(Mandatory = $true)]
        [scriptblock]$Body
    )

    $previousPath = $env:PATH
    $toolPath = Join-Path ([System.IO.Path]::GetTempPath()) ("render-matrix-tools-" + [Guid]::NewGuid().ToString("N"))

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

function New-TestEnvironmentPreset {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Root,

        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [string[]]$Lines
    )

    $environmentRoot = Join-Path $Root "config\environments"
    New-Item -ItemType Directory -Path $environmentRoot -Force | Out-Null
    Set-Content `
        -Path (Join-Path $environmentRoot ("{0}.psd1" -f $Name)) `
        -Value $Lines
}

function New-TestProfileDefinition {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Root,

        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [string[]]$Lines
    )

    $profileRoot = Join-Path $Root "config\profiles"
    New-Item -ItemType Directory -Path $profileRoot -Force | Out-Null
    Set-Content `
        -Path (Join-Path $profileRoot ("{0}.psd1" -f $Name)) `
        -Value $Lines
}

$repoRoot = (Resolve-Path -Path (Join-Path $PSScriptRoot "..")).Path
. (Join-Path $repoRoot "scripts\render-matrix-catalog.ps1")
$platformAssetsValidation = Join-Path $repoRoot "scripts\validate-platform-assets.ps1"
$renderMatrixValidation = Join-Path $repoRoot "scripts\validate-render-matrix.ps1"
$repositoryValidation = Join-Path $repoRoot "scripts\invoke-repository-validation.ps1"

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

Invoke-Test -Name "Profile render matrix requires explicit public data service selections" -Body {
    $failed = $false

    try {
        Get-RequiredProfileMatrixList `
            -Definition @{ ValidationApplications = @("nginx-web") } `
            -ProfileName "custom-profile" `
            -Key "ValidationDataServices" | Out-Null
    }
    catch {
        $failed = $true
        Assert-Contains `
            -Content $_.Exception.Message `
            -Expected "Profile 'custom-profile' is missing 'ValidationDataServices'" `
            -Message "Missing profile data service metadata should be rejected."
        Assert-Contains `
            -Content $_.Exception.Message `
            -Expected "config/profiles/custom-profile.psd1" `
            -Message "The failure should point maintainers to the profile metadata file."
    }

    Assert-True -Condition $failed -Message "Profiles without explicit validation data services should fail matrix construction."
}

Invoke-Test -Name "Profile render matrix orders known profiles before sorted custom profiles" -Body {
    $testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("render-matrix-profile-test-" + [Guid]::NewGuid().ToString("N"))

    try {
        New-TestProfileDefinition `
            -Root $testRoot `
            -Name "zeta-custom" `
            -Lines @(
                "@{",
                "    ValidationApplications = @('whoami')",
                "    ValidationDataServices = @()",
                "}"
            )
        New-TestProfileDefinition `
            -Root $testRoot `
            -Name "minimal-application" `
            -Lines @(
                "@{",
                "    ValidationApplications = @('nginx-web')",
                "    ValidationDataServices = @()",
                "}"
            )
        New-TestProfileDefinition `
            -Root $testRoot `
            -Name "alpha-custom" `
            -Lines @(
                "@{",
                "    ValidationApplications = @('httpbin')",
                "    ValidationDataServices = @('redis')",
                "}"
            )
        New-TestProfileDefinition `
            -Root $testRoot `
            -Name "web-platform" `
            -Lines @(
                "@{",
                "    ValidationApplications = @('nginx-web', 'httpbin')",
                "    ValidationDataServices = @('redis')",
                "}"
            )

        $entries = @(Get-ProfileRenderMatrix -Root $testRoot -ValuesFile "config\platform-values.env.example")

        Assert-SequenceEqual `
            -Expected @("minimal-application", "web-platform", "alpha-custom", "zeta-custom") `
            -Actual @($entries | Select-Object -ExpandProperty Name) `
            -Message "Known profile names should keep the preferred validation order before custom profiles sorted by name."
    }
    finally {
        if (Test-Path -LiteralPath $testRoot) {
            Remove-Item -LiteralPath $testRoot -Recurse -Force
        }
    }
}

Invoke-Test -Name "Profile render matrix preserves explicit profile validation selections and flags" -Body {
    $testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("render-matrix-profile-test-" + [Guid]::NewGuid().ToString("N"))

    try {
        New-TestProfileDefinition `
            -Root $testRoot `
            -Name "custom-profile" `
            -Lines @(
                "@{",
                "    ValidationApplications = @('nginx-web,httpbin', ' whoami ')",
                "    ValidationDataServices = @('postgresql, redis')",
                "    ValidationIncludeJenkins = `$true",
                "}"
            )

        $entry = @(Get-ProfileRenderMatrix -Root $testRoot -ValuesFile "config\platform-values.env.example")[0]

        Assert-Equal -Expected "profile" -Actual $entry.Scope -Message "Custom profile should be a profile matrix entry."
        Assert-Equal -Expected "custom-profile" -Actual $entry.Name -Message "Custom profile name should be retained."
        Assert-Equal -Expected "custom-profile" -Actual $entry.Profile -Message "Profile argument should match the profile name."
        Assert-SequenceEqual -Expected @("nginx-web", "httpbin", "whoami") -Actual @($entry.Applications) -Message "Profile validation applications should be normalized."
        Assert-SequenceEqual -Expected @("postgresql", "redis") -Actual @($entry.DataServices) -Message "Profile validation data services should be normalized."
        Assert-True -Condition $entry.IncludeJenkins -Message "Profile ValidationIncludeJenkins should be forwarded to render validation."
    }
    finally {
        if (Test-Path -LiteralPath $testRoot) {
            Remove-Item -LiteralPath $testRoot -Recurse -Force
        }
    }
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

Invoke-Test -Name "Environment render matrix resolves public values file precedence" -Body {
    $testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("render-matrix-env-test-" + [Guid]::NewGuid().ToString("N"))
    $defaultValuesFile = "config\platform-values.env.example"

    try {
        New-TestEnvironmentPreset `
            -Root $testRoot `
            -Name "default-only" `
            -Lines @(
                "@{",
                "    Description = 'Uses default public values'",
                "    Profile = 'minimal-application'",
                "}"
            )
        New-TestEnvironmentPreset `
            -Root $testRoot `
            -Name "validation-values" `
            -Lines @(
                "@{",
                "    Description = 'Uses explicit validation values'",
                "    ValuesFile = 'config\private.env'",
                "    ValidationValuesFile = 'config\public-validation.env'",
                "}"
            )
        New-TestEnvironmentPreset `
            -Root $testRoot `
            -Name "values-only" `
            -Lines @(
                "@{",
                "    Description = 'Falls back to normal values'",
                "    ValuesFile = 'config\regular.env'",
                "}"
            )

        $entries = @(Get-EnvironmentRenderMatrix -Root $testRoot -DefaultValuesFile $defaultValuesFile)
        $entriesByName = @{}
        foreach ($entry in $entries) {
            $entriesByName[$entry.Name] = $entry
        }

        Assert-SequenceEqual `
            -Expected @("default-only", "validation-values", "values-only") `
            -Actual @($entries | Select-Object -ExpandProperty Name) `
            -Message "Environment presets should be processed in stable name order."
        Assert-Equal `
            -Expected $defaultValuesFile `
            -Actual $entriesByName["default-only"].ValuesFile `
            -Message "Environment presets without values metadata should use the public default values file."
        Assert-Equal `
            -Expected "config\public-validation.env" `
            -Actual $entriesByName["validation-values"].ValuesFile `
            -Message "ValidationValuesFile should take precedence over a private ValuesFile."
        Assert-Equal `
            -Expected "config\regular.env" `
            -Actual $entriesByName["values-only"].ValuesFile `
            -Message "ValuesFile should be used only when ValidationValuesFile is absent."
    }
    finally {
        if (Test-Path -LiteralPath $testRoot) {
            Remove-Item -LiteralPath $testRoot -Recurse -Force
        }
    }
}

Invoke-Test -Name "Environment render matrix applies metadata defaults and explicit flags" -Body {
    $testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("render-matrix-env-test-" + [Guid]::NewGuid().ToString("N"))
    $defaultValuesFile = "config\platform-values.env.example"

    try {
        New-TestEnvironmentPreset `
            -Root $testRoot `
            -Name "defaults" `
            -Lines @(
                "@{",
                "    Description = 'Uses matrix defaults'",
                "}"
            )
        New-TestEnvironmentPreset `
            -Root $testRoot `
            -Name "explicit" `
            -Lines @(
                "@{",
                "    Description = 'Uses explicit metadata'",
                "    Version = '2.3.4-test'",
                "    Profile = 'web-platform'",
                "    Applications = @('nginx-web,httpbin', ' whoami ')",
                "    DataServices = @('postgresql, redis')",
                "    IncludeJenkins = `$true",
                "}"
            )

        $entries = @(Get-EnvironmentRenderMatrix -Root $testRoot -DefaultValuesFile $defaultValuesFile)
        $entriesByName = @{}
        foreach ($entry in $entries) {
            $entriesByName[$entry.Name] = $entry
        }

        Assert-Equal -Expected "0.0.0-defaults-matrix" -Actual $entriesByName["defaults"].Version -Message "Missing versions should get an environment-specific matrix version."
        Assert-Equal -Expected "full" -Actual $entriesByName["defaults"].Profile -Message "Missing profiles should default to full."
        Assert-SequenceEqual -Expected @() -Actual @($entriesByName["defaults"].Applications) -Message "Missing applications should become an empty list."
        Assert-SequenceEqual -Expected @() -Actual @($entriesByName["defaults"].DataServices) -Message "Missing data services should become an empty list."
        Assert-False -Condition $entriesByName["defaults"].IncludeJenkins -Message "IncludeJenkins should be false by default."

        Assert-Equal -Expected "2.3.4-test" -Actual $entriesByName["explicit"].Version -Message "Explicit versions should be retained."
        Assert-Equal -Expected "web-platform" -Actual $entriesByName["explicit"].Profile -Message "Explicit profiles should be retained."
        Assert-SequenceEqual -Expected @("nginx-web", "httpbin", "whoami") -Actual @($entriesByName["explicit"].Applications) -Message "Applications should be normalized from environment metadata."
        Assert-SequenceEqual -Expected @("postgresql", "redis") -Actual @($entriesByName["explicit"].DataServices) -Message "Data services should be normalized from environment metadata."
        Assert-True -Condition $entriesByName["explicit"].IncludeJenkins -Message "Explicit IncludeJenkins should be retained."
    }
    finally {
        if (Test-Path -LiteralPath $testRoot) {
            Remove-Item -LiteralPath $testRoot -Recurse -Force
        }
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

Invoke-Test -Name "Platform asset validation forwards requested schema validator" -Body {
    $failed = Invoke-WithEmptyToolPath -Body {
        try {
            & $platformAssetsValidation `
                -RepoRoot $repoRoot `
                -ValuesFile "config\platform-values.env.example" `
                -Profile "data-services" `
                -DataServices @("mysql") `
                -SchemaValidator kubeconform `
                -Strict 3>&1 2>&1 | Out-String | Out-Null
            return $false
        }
        catch {
            Assert-Contains `
                -Content $_.Exception.Message `
                -Expected "kubeconform is required" `
                -Message "Requested kubeconform validation should be forwarded to rendered bundle validation."
            return $true
        }
    }

    Assert-True -Condition $failed -Message "Platform asset validation should fail when requested kubeconform is unavailable in strict mode."
}

Invoke-Test -Name "Render matrix validation forwards requested schema validator" -Body {
    $failed = Invoke-WithEmptyToolPath -Body {
        try {
            & $renderMatrixValidation `
                -RepoRoot $repoRoot `
                -ValuesFile "config\platform-values.env.example" `
                -SchemaValidator kubeconform `
                -Strict 3>&1 2>&1 | Out-String | Out-Null
            return $false
        }
        catch {
            Assert-Contains `
                -Content $_.Exception.Message `
                -Expected "kubeconform is required" `
                -Message "Render matrix validation should pass the requested schema validator to each platform asset check."
            return $true
        }
    }

    Assert-True -Condition $failed -Message "Render matrix validation should fail when requested kubeconform is unavailable in strict mode."
}

Invoke-Test -Name "Repository validation forwards requested schema validator" -Body {
    $failed = Invoke-WithEmptyToolPath -Body {
        try {
            & $repositoryValidation `
                -RepoRoot $repoRoot `
                -Profile "data-services" `
                -DataServices @("mysql") `
                -SchemaValidator kubeconform `
                -Strict `
                -SkipTemplateValidation `
                -SkipWorkstationValidation 3>&1 2>&1 | Out-String | Out-Null
            return $false
        }
        catch {
            Assert-Contains `
                -Content $_.Exception.Message `
                -Expected "kubeconform is required" `
                -Message "Repository validation should pass the requested schema validator to rendered bundle validation."
            return $true
        }
    }

    Assert-True -Condition $failed -Message "Repository validation should fail when requested kubeconform is unavailable in strict mode."
}

if ($script:TestsFailed -gt 0) {
    throw ("{0} of {1} render matrix test(s) failed." -f $script:TestsFailed, $script:TestsRun)
}

Write-Host ("All {0} render matrix test(s) passed." -f $script:TestsRun)
