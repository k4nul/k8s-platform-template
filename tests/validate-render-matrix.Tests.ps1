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

function New-TestTextFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Root,

        [Parameter(Mandatory = $true)]
        [string]$RelativePath,

        [string[]]$Lines
    )

    $targetPath = Join-Path $Root $RelativePath
    $targetDirectory = Split-Path -Path $targetPath -Parent
    if ($targetDirectory) {
        New-Item -ItemType Directory -Path $targetDirectory -Force | Out-Null
    }

    Set-Content -Path $targetPath -Value $Lines
}

function New-TestPlatformAssetsRecorder {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Root
    )

    New-TestTextFile `
        -Root $Root `
        -RelativePath "scripts\validate-platform-assets.ps1" `
        -Lines @(
            "param(",
            "    [string]`$RepoRoot,",
            "    [string]`$ValuesFile,",
            "    [string]`$Version,",
            "    [string]`$Profile,",
            "    [string[]]`$Applications = @(),",
            "    [string[]]`$DataServices = @(),",
            "    [switch]`$IncludeJenkins,",
            "    [switch]`$Strict,",
            "    [switch]`$ValidateCrdBackedResources,",
            "    [ValidateSet('auto', 'kubeconform', 'kubectl')]",
            "    [string]`$SchemaValidator = 'auto',",
            "    [switch]`$FailOnHighSecurityBaselineFinding",
            ")",
            "",
            "`$record = [PSCustomObject]@{",
            "    RepoRoot = `$RepoRoot",
            "    ValuesFile = `$ValuesFile",
            "    Version = `$Version",
            "    Profile = `$Profile",
            "    Applications = @(`$Applications)",
            "    DataServices = @(`$DataServices)",
            "    IncludeJenkins = [bool]`$IncludeJenkins",
            "    Strict = [bool]`$Strict",
            "    ValidateCrdBackedResources = [bool]`$ValidateCrdBackedResources",
            "    SchemaValidator = `$SchemaValidator",
            "    FailOnHighSecurityBaselineFinding = [bool]`$FailOnHighSecurityBaselineFinding",
            "}",
            "",
            "Add-Content -Path `$env:RENDER_MATRIX_ASSET_LOG -Value (`$record | ConvertTo-Json -Compress)"
        )
}

function New-TestRenderMatrixRepo {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Root
    )

    New-TestTextFile `
        -Root $Root `
        -RelativePath "config\platform-values.env.example" `
        -Lines @("PLATFORM_DOMAIN=example.com")

    New-TestEnvironmentPreset `
        -Root $Root `
        -Name "dev" `
        -Lines @(
            "@{",
            "    Version = '1.2.3-dev'",
            "    Profile = 'web-platform'",
            "    Applications = @('nginx-web,httpbin', ' whoami ')",
            "    DataServices = @('redis')",
            "    IncludeJenkins = `$true",
            "    ValidationValuesFile = 'config\platform-values.env.example'",
            "}"
        )

    New-TestProfileDefinition `
        -Root $Root `
        -Name "minimal-application" `
        -Lines @(
            "@{",
            "    ValidationApplications = @('nginx-web')",
            "    ValidationDataServices = @()",
            "}"
        )

    New-TestPlatformAssetsRecorder -Root $Root
}

$repoRoot = (Resolve-Path -Path (Join-Path $PSScriptRoot "..")).Path
. (Join-Path $repoRoot "scripts\render-matrix-catalog.ps1")
$platformAssetsValidation = Join-Path $repoRoot "scripts\validate-platform-assets.ps1"
$renderMatrixShow = Join-Path $repoRoot "scripts\show-render-matrix.ps1"
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

Invoke-Test -Name "Combined render validation matrix keeps public environment values and profile defaults" -Body {
    $testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("render-matrix-combined-test-" + [Guid]::NewGuid().ToString("N"))
    $defaultValuesFile = "config\platform-values.env.example"

    try {
        New-TestEnvironmentPreset `
            -Root $testRoot `
            -Name "dev" `
            -Lines @(
                "@{",
                "    ValuesFile = 'config\platform-values.dev.env'",
                "    ValidationValuesFile = 'config\platform-values.env.example'",
                "    Profile = 'web-platform'",
                "    Applications = @('nginx-web')",
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

        $entries = @(Get-RenderValidationMatrix -Root $testRoot -DefaultValuesFile $defaultValuesFile)
        $environmentEntry = @($entries | Where-Object { $_.Scope -eq "environment" })[0]
        $profileEntry = @($entries | Where-Object { $_.Scope -eq "profile" })[0]

        Assert-Equal `
            -Expected $defaultValuesFile `
            -Actual $environmentEntry.ValuesFile `
            -Message "Combined matrix environment entries should prefer ValidationValuesFile over private delivery values."
        Assert-Equal `
            -Expected $defaultValuesFile `
            -Actual $profileEntry.ValuesFile `
            -Message "Combined matrix profile entries should use the public default values file."
        Assert-SequenceEqual `
            -Expected @("environment", "profile") `
            -Actual @($entries | Select-Object -ExpandProperty Scope) `
            -Message "Combined matrix should keep environments before profiles."
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

Invoke-Test -Name "Render validation matrix entries resolve to valid platform selections" -Body {
    $entries = @(Get-RenderValidationMatrix -Root $repoRoot -DefaultValuesFile "config\platform-values.env.example")

    foreach ($entry in $entries) {
        $selection = Resolve-PlatformSelection `
            -Profile $entry.Profile `
            -Applications @($entry.Applications) `
            -DataServices @($entry.DataServices) `
            -IncludeJenkins:$entry.IncludeJenkins

        Assert-Equal `
            -Expected $entry.Profile `
            -Actual $selection.Profile `
            -Message ("{0} '{1}' should use a known platform profile." -f $entry.Scope, $entry.Name)
        Assert-SequenceEqual `
            -Expected @($entry.Applications | Sort-Object -Unique) `
            -Actual @($selection.Applications) `
            -Message ("{0} '{1}' should use known validation applications." -f $entry.Scope, $entry.Name)
        Assert-SequenceEqual `
            -Expected @($entry.DataServices | Sort-Object -Unique) `
            -Actual @($selection.DataServices) `
            -Message ("{0} '{1}' should use known validation data services." -f $entry.Scope, $entry.Name)
    }
}

Invoke-Test -Name "Render matrix report lists environment and profile entries as JSON" -Body {
    $testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("render-matrix-report-test-" + [Guid]::NewGuid().ToString("N"))

    try {
        New-TestRenderMatrixRepo -Root $testRoot

        $json = (& $renderMatrixShow -RepoRoot $testRoot -Format json | Out-String)
        $document = $json | ConvertFrom-Json
        $entries = @($document.Entries)
        $environmentEntry = @($entries | Where-Object { $_.Scope -eq "environment" })[0]
        $profileEntry = @($entries | Where-Object { $_.Scope -eq "profile" })[0]
        $expectedValuesFile = Resolve-RenderMatrixRepoPath -Root $testRoot -Path "config\platform-values.env.example"

        Assert-Equal -Expected 2 -Actual $document.EntryCount -Message "The report should include one environment and one profile entry for the test repository."
        Assert-Equal -Expected 1 -Actual $document.EnvironmentEntryCount -Message "The report should count environment entries."
        Assert-Equal -Expected 1 -Actual $document.ProfileEntryCount -Message "The report should count profile entries."
        Assert-Equal -Expected "dev" -Actual $environmentEntry.Name -Message "Environment entry names should be preserved."
        Assert-Equal -Expected "minimal-application" -Actual $profileEntry.Name -Message "Profile entry names should be preserved."
        Assert-Equal -Expected $expectedValuesFile -Actual $environmentEntry.ValuesFileResolved -Message "The report should include resolved values paths."
        Assert-True -Condition $environmentEntry.ValuesFileExists -Message "Existing values files should be marked present."
        Assert-SequenceEqual -Expected @("nginx-web", "httpbin", "whoami") -Actual @($environmentEntry.Applications) -Message "Environment applications should be reported."
        Assert-SequenceEqual -Expected @("nginx-web") -Actual @($profileEntry.Applications) -Message "Profile applications should be reported."
    }
    finally {
        if (Test-Path -LiteralPath $testRoot) {
            Remove-Item -LiteralPath $testRoot -Recurse -Force
        }
    }
}

Invoke-Test -Name "Render matrix report marks missing environment validation values" -Body {
    $testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("render-matrix-report-test-" + [Guid]::NewGuid().ToString("N"))

    try {
        New-TestTextFile `
            -Root $testRoot `
            -RelativePath "config\platform-values.env.example" `
            -Lines @("PLATFORM_DOMAIN=example.com")
        New-TestEnvironmentPreset `
            -Root $testRoot `
            -Name "dev" `
            -Lines @(
                "@{",
                "    ValidationValuesFile = 'config\missing-public-values.env'",
                "    Profile = 'minimal-application'",
                "    Applications = @('nginx-web')",
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

        $json = (& $renderMatrixShow -RepoRoot $testRoot -Format json | Out-String)
        $document = $json | ConvertFrom-Json
        $environmentEntry = @($document.Entries | Where-Object { $_.Scope -eq "environment" })[0]
        $profileEntry = @($document.Entries | Where-Object { $_.Scope -eq "profile" })[0]
        $expectedMissingValuesFile = Resolve-RenderMatrixRepoPath -Root $testRoot -Path "config\missing-public-values.env"
        $expectedPublicValuesFile = Resolve-RenderMatrixRepoPath -Root $testRoot -Path "config\platform-values.env.example"

        Assert-Equal -Expected "dev" -Actual $environmentEntry.Name -Message "Environment entry names should be preserved when validation values are missing."
        Assert-Equal -Expected "config\missing-public-values.env" -Actual $environmentEntry.ValuesFile -Message "The report should retain the missing environment validation values path."
        Assert-Equal -Expected $expectedMissingValuesFile -Actual $environmentEntry.ValuesFileResolved -Message "The report should resolve missing validation values from the repository root."
        Assert-False -Condition $environmentEntry.ValuesFileExists -Message "Missing environment validation values should be visible in the report."

        Assert-Equal -Expected "minimal-application" -Actual $profileEntry.Name -Message "Profile entries should still be reported."
        Assert-Equal -Expected $expectedPublicValuesFile -Actual $profileEntry.ValuesFileResolved -Message "Profile entries should keep using public defaults."
        Assert-True -Condition $profileEntry.ValuesFileExists -Message "Existing profile values should be marked present."
    }
    finally {
        if (Test-Path -LiteralPath $testRoot) {
            Remove-Item -LiteralPath $testRoot -Recurse -Force
        }
    }
}

Invoke-Test -Name "Render matrix report writes markdown coverage table" -Body {
    $testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("render-matrix-report-test-" + [Guid]::NewGuid().ToString("N"))
    $outputPath = Join-Path ([System.IO.Path]::GetTempPath()) ("render-matrix-report-" + [Guid]::NewGuid().ToString("N") + ".md")

    try {
        New-TestRenderMatrixRepo -Root $testRoot

        & $renderMatrixShow -RepoRoot $testRoot -Format markdown -OutputPath $outputPath
        $content = Get-Content -Path $outputPath -Raw

        Assert-Contains -Content $content -Expected "# Render Validation Matrix" -Message "Markdown output should include a title."
        Assert-Contains -Content $content -Expected "| environment | dev | web-platform |" -Message "Markdown output should include the environment matrix row."
        Assert-Contains -Content $content -Expected "| profile | minimal-application | minimal-application |" -Message "Markdown output should include the profile matrix row."
    }
    finally {
        if (Test-Path -LiteralPath $testRoot) {
            Remove-Item -LiteralPath $testRoot -Recurse -Force
        }
        if (Test-Path -LiteralPath $outputPath) {
            Remove-Item -LiteralPath $outputPath -Force
        }
    }
}

Invoke-Test -Name "Render matrix validation forwards validator and security options to each entry" -Body {
    $testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("render-matrix-validation-test-" + [Guid]::NewGuid().ToString("N"))
    $logPath = Join-Path ([System.IO.Path]::GetTempPath()) ("render-matrix-validation-log-" + [Guid]::NewGuid().ToString("N") + ".jsonl")

    try {
        New-TestRenderMatrixRepo -Root $testRoot
        $env:RENDER_MATRIX_ASSET_LOG = $logPath

        & $renderMatrixValidation `
            -RepoRoot $testRoot `
            -Strict `
            -ValidateCrdBackedResources `
            -SchemaValidator kubectl `
            -FailOnHighSecurityBaselineFinding 3>&1 2>&1 | Out-String | Out-Null

        $records = @(Get-Content -Path $logPath | ForEach-Object { $_ | ConvertFrom-Json })

        Assert-Equal -Expected 2 -Actual $records.Count -Message "The validation command should invoke asset validation for each environment and profile matrix entry."
        foreach ($record in $records) {
            Assert-True -Condition $record.Strict -Message ("Strict mode should be forwarded for {0}." -f $record.Profile)
            Assert-True -Condition $record.ValidateCrdBackedResources -Message ("CRD-backed resource validation should be forwarded for {0}." -f $record.Profile)
            Assert-Equal -Expected "kubectl" -Actual $record.SchemaValidator -Message ("Schema validator selection should be forwarded for {0}." -f $record.Profile)
            Assert-True -Condition $record.FailOnHighSecurityBaselineFinding -Message ("Security baseline fail-on-high should be forwarded for {0}." -f $record.Profile)
        }
    }
    finally {
        Remove-Item Env:RENDER_MATRIX_ASSET_LOG -ErrorAction SilentlyContinue
        if (Test-Path -LiteralPath $testRoot) {
            Remove-Item -LiteralPath $testRoot -Recurse -Force
        }
        if (Test-Path -LiteralPath $logPath) {
            Remove-Item -LiteralPath $logPath -Force
        }
    }
}

Invoke-Test -Name "Render matrix validation forwards normalized environment and profile metadata" -Body {
    $testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("render-matrix-validation-test-" + [Guid]::NewGuid().ToString("N"))
    $logPath = Join-Path ([System.IO.Path]::GetTempPath()) ("render-matrix-validation-log-" + [Guid]::NewGuid().ToString("N") + ".jsonl")

    try {
        New-TestRenderMatrixRepo -Root $testRoot
        $env:RENDER_MATRIX_ASSET_LOG = $logPath

        & $renderMatrixValidation `
            -RepoRoot $testRoot 3>&1 2>&1 | Out-String | Out-Null

        $records = @(Get-Content -Path $logPath | ForEach-Object { $_ | ConvertFrom-Json })
        $environmentRecord = @($records | Where-Object { $_.Profile -eq "web-platform" })[0]
        $profileRecord = @($records | Where-Object { $_.Profile -eq "minimal-application" })[0]
        $expectedValuesFile = Resolve-RenderMatrixRepoPath -Root $testRoot -Path "config\platform-values.env.example"

        Assert-Equal -Expected $testRoot -Actual $environmentRecord.RepoRoot -Message "Asset validation should receive the selected repository root."
        Assert-Equal -Expected $expectedValuesFile -Actual $environmentRecord.ValuesFile -Message "Environment values files should be resolved before asset validation."
        Assert-Equal -Expected "1.2.3-dev" -Actual $environmentRecord.Version -Message "Environment versions should be forwarded."
        Assert-SequenceEqual -Expected @("nginx-web", "httpbin", "whoami") -Actual @($environmentRecord.Applications) -Message "Environment applications should be normalized before asset validation."
        Assert-SequenceEqual -Expected @("redis") -Actual @($environmentRecord.DataServices) -Message "Environment data services should be normalized before asset validation."
        Assert-True -Condition $environmentRecord.IncludeJenkins -Message "Environment IncludeJenkins should be forwarded."

        Assert-Equal -Expected $expectedValuesFile -Actual $profileRecord.ValuesFile -Message "Profile entries should use the public default values file."
        Assert-Equal -Expected "0.0.0-matrix" -Actual $profileRecord.Version -Message "Profile entries should use the default matrix version."
        Assert-SequenceEqual -Expected @("nginx-web") -Actual @($profileRecord.Applications) -Message "Profile validation applications should be forwarded."
        Assert-SequenceEqual -Expected @() -Actual @($profileRecord.DataServices) -Message "Profile validation data services should be forwarded."
        Assert-False -Condition $profileRecord.IncludeJenkins -Message "Profile IncludeJenkins should be false unless explicitly configured."
    }
    finally {
        Remove-Item Env:RENDER_MATRIX_ASSET_LOG -ErrorAction SilentlyContinue
        if (Test-Path -LiteralPath $testRoot) {
            Remove-Item -LiteralPath $testRoot -Recurse -Force
        }
        if (Test-Path -LiteralPath $logPath) {
            Remove-Item -LiteralPath $logPath -Force
        }
    }
}

Invoke-Test -Name "Render matrix validation applies explicit values override to every matrix entry" -Body {
    $testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("render-matrix-validation-test-" + [Guid]::NewGuid().ToString("N"))
    $logPath = Join-Path ([System.IO.Path]::GetTempPath()) ("render-matrix-validation-log-" + [Guid]::NewGuid().ToString("N") + ".jsonl")
    $overrideValuesFile = "config\custom-public.env"

    try {
        New-TestRenderMatrixRepo -Root $testRoot
        New-TestTextFile `
            -Root $testRoot `
            -RelativePath $overrideValuesFile `
            -Lines @("PLATFORM_DOMAIN=custom.example.com")
        $env:RENDER_MATRIX_ASSET_LOG = $logPath

        & $renderMatrixValidation `
            -RepoRoot $testRoot `
            -ValuesFile $overrideValuesFile 3>&1 2>&1 | Out-String | Out-Null

        $records = @(Get-Content -Path $logPath | ForEach-Object { $_ | ConvertFrom-Json })
        $expectedValuesFile = Resolve-RenderMatrixRepoPath -Root $testRoot -Path $overrideValuesFile

        Assert-Equal -Expected 2 -Actual $records.Count -Message "The validation command should invoke asset validation for every matrix entry."
        foreach ($record in $records) {
            Assert-Equal `
                -Expected $expectedValuesFile `
                -Actual $record.ValuesFile `
                -Message ("Explicit values override should be forwarded to {0}." -f $record.Profile)
        }
    }
    finally {
        Remove-Item Env:RENDER_MATRIX_ASSET_LOG -ErrorAction SilentlyContinue
        if (Test-Path -LiteralPath $testRoot) {
            Remove-Item -LiteralPath $testRoot -Recurse -Force
        }
        if (Test-Path -LiteralPath $logPath) {
            Remove-Item -LiteralPath $logPath -Force
        }
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

Invoke-Test -Name "Render matrix validation fails before rendering when an environment validation values file is missing" -Body {
    $testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("render-matrix-validation-test-" + [Guid]::NewGuid().ToString("N"))
    $logPath = Join-Path ([System.IO.Path]::GetTempPath()) ("render-matrix-validation-log-" + [Guid]::NewGuid().ToString("N") + ".jsonl")
    $missingValuesFile = "config\missing-public-values.env"
    $failed = $false

    try {
        New-TestTextFile `
            -Root $testRoot `
            -RelativePath "config\platform-values.env.example" `
            -Lines @("PLATFORM_DOMAIN=example.com")
        New-TestEnvironmentPreset `
            -Root $testRoot `
            -Name "dev" `
            -Lines @(
                "@{",
                "    ValidationValuesFile = 'config\missing-public-values.env'",
                "    Profile = 'minimal-application'",
                "    Applications = @('nginx-web')",
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
        New-TestPlatformAssetsRecorder -Root $testRoot
        $env:RENDER_MATRIX_ASSET_LOG = $logPath

        try {
            & $renderMatrixValidation `
                -RepoRoot $testRoot 3>&1 2>&1 | Out-String | Out-Null
        }
        catch {
            $failed = $true
            Assert-Contains `
                -Content $_.Exception.Message `
                -Expected "Render matrix values file was not found for environment 'dev'" `
                -Message "The failure should identify the environment entry with missing validation values."
            Assert-Contains `
                -Content $_.Exception.Message `
                -Expected (Resolve-RenderMatrixRepoPath -Root $testRoot -Path $missingValuesFile) `
                -Message "The failure should include the resolved missing values file path."
        }

        Assert-True -Condition $failed -Message "Render matrix validation should fail on missing environment validation values."
        Assert-False -Condition (Test-Path -LiteralPath $logPath) -Message "Asset validation should not run after a missing matrix values file is detected."
    }
    finally {
        Remove-Item Env:RENDER_MATRIX_ASSET_LOG -ErrorAction SilentlyContinue
        if (Test-Path -LiteralPath $testRoot) {
            Remove-Item -LiteralPath $testRoot -Recurse -Force
        }
        if (Test-Path -LiteralPath $logPath) {
            Remove-Item -LiteralPath $logPath -Force
        }
    }
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
