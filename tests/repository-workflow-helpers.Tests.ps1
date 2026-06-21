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
    $toolPath = Join-Path ([System.IO.Path]::GetTempPath()) ("repository-workflow-tools-" + [Guid]::NewGuid().ToString("N"))

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

function New-TestRepositoryValidationRepo {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Root
    )

    New-TestTextFile `
        -Root $Root `
        -RelativePath "config\platform-values.env.example" `
        -Lines @("PLATFORM_DOMAIN=public.example.com")
    New-TestTextFile `
        -Root $Root `
        -RelativePath "config\platform-values.private.env" `
        -Lines @("PLATFORM_DOMAIN=private.example.com")
    New-TestTextFile `
        -Root $Root `
        -RelativePath "config\platform-values.explicit.env" `
        -Lines @("PLATFORM_DOMAIN=explicit.example.com")
    New-TestTextFile `
        -Root $Root `
        -RelativePath "config\environments\dev.psd1" `
        -Lines @(
            "@{",
            "    ValuesFile = 'config\platform-values.private.env'",
            "    ValidationValuesFile = 'config\platform-values.env.example'",
            "    Version = '2.4.6-dev'",
            "    Profile = 'web-platform'",
            "    Applications = @('nginx-web,httpbin', ' whoami ')",
            "    DataServices = @('postgresql, redis')",
            "    IncludeJenkins = `$true",
            "    PrepareHelmRepos = `$true",
            "    Strict = `$true",
            "    ValidateCrdBackedResources = `$true",
            "    RequireBootstrapSecretsReady = `$true",
            "    SkipTemplateValidation = `$true",
            "    SkipWorkstationValidation = `$true",
            "}"
        )
    New-TestTextFile `
        -Root $Root `
        -RelativePath "scripts\validate-platform-assets.ps1" `
        -Lines @(
            "param(",
            "    [string]`$RepoRoot,",
            "    [string]`$ValuesFile,",
            "    [string]`$RenderedPath,",
            "    [string]`$HelmConfigFile,",
            "    [string]`$DockerRegistry = '',",
            "    [string]`$Version,",
            "    [string]`$Profile,",
            "    [string[]]`$Applications = @(),",
            "    [string[]]`$DataServices = @(),",
            "    [switch]`$IncludeJenkins,",
            "    [switch]`$PrepareHelmRepos,",
            "    [switch]`$Strict,",
            "    [switch]`$ValidateCrdBackedResources,",
            "    [ValidateSet('auto', 'kubeconform', 'kubectl')]",
            "    [string]`$SchemaValidator = 'auto',",
            "    [switch]`$RequireBootstrapSecretsReady",
            ")",
            "",
            "`$record = [PSCustomObject]@{",
            "    RepoRoot = `$RepoRoot",
            "    ValuesFile = `$ValuesFile",
            "    RenderedPath = `$RenderedPath",
            "    HelmConfigFile = `$HelmConfigFile",
            "    Version = `$Version",
            "    Profile = `$Profile",
            "    Applications = @(`$Applications)",
            "    DataServices = @(`$DataServices)",
            "    IncludeJenkins = [bool]`$IncludeJenkins",
            "    PrepareHelmRepos = [bool]`$PrepareHelmRepos",
            "    Strict = [bool]`$Strict",
            "    ValidateCrdBackedResources = [bool]`$ValidateCrdBackedResources",
            "    SchemaValidator = `$SchemaValidator",
            "    RequireBootstrapSecretsReady = [bool]`$RequireBootstrapSecretsReady",
            "}",
            "",
            "Add-Content -Path `$env:REPOSITORY_VALIDATION_ASSET_LOG -Value (`$record | ConvertTo-Json -Compress)"
        )
}

$repoRoot = (Resolve-Path -Path (Join-Path $PSScriptRoot "..")).Path
. (Join-Path $repoRoot "scripts\repository-workflow-helpers.ps1")
$repositoryValidation = Join-Path $repoRoot "scripts\invoke-repository-validation.ps1"

Invoke-Test -Name "Resolve-RepoPath roots relative paths and preserves absolute paths" -Body {
    $relativePath = "config\platform-values.env.example"
    $absolutePath = Join-Path $repoRoot $relativePath

    Assert-Equal `
        -Expected ([System.IO.Path]::GetFullPath($absolutePath)) `
        -Actual (Resolve-RepoPath -Root $repoRoot -Path $relativePath) `
        -Message "Relative paths should resolve from the repository root."

    Assert-Equal `
        -Expected ([System.IO.Path]::GetFullPath($absolutePath)) `
        -Actual (Resolve-RepoPath -Root $repoRoot -Path $absolutePath) `
        -Message "Absolute paths should not be rooted twice."
}

Invoke-Test -Name "Normalize-List trims comma-delimited values and skips blanks" -Body {
    $actual = @(
        Normalize-List -Values @(
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
        -Message "Normalized workflow lists should preserve input order after trimming."
}

Invoke-Test -Name "Get-ListText formats populated and empty lists" -Body {
    Assert-Equal `
        -Expected "nginx-web, httpbin" `
        -Actual (Get-ListText -Values @("nginx-web", "httpbin")) `
        -Message "Populated lists should be comma-delimited."

    Assert-Equal `
        -Expected "none" `
        -Actual (Get-ListText -Values @()) `
        -Message "Empty lists should use the default placeholder."
}

Invoke-Test -Name "Invoke-RepositoryWorkflowStep runs the provided action" -Body {
    $script:helperStepRan = $false

    Invoke-RepositoryWorkflowStep -Title "helper test step" -Action {
        $script:helperStepRan = $true
    }

    Assert-True -Condition $script:helperStepRan -Message "Workflow step helper should invoke the supplied action."
}

Invoke-Test -Name "Invoke-RepositoryWorkflowStep fails on nonzero child exit codes" -Body {
    $failed = $false

    try {
        Invoke-RepositoryWorkflowStep -Title "failing helper test step" -Action {
            $global:LASTEXITCODE = 23
        }
    }
    catch {
        $failed = $true
        Assert-Equal `
            -Expected "Repository workflow step 'failing helper test step' failed with exit code 23." `
            -Actual $_.Exception.Message `
            -Message "Workflow helper should turn nonzero child exit codes into terminating errors."
    }

    Assert-True -Condition $failed -Message "Workflow helper should fail the step when a child command leaves a nonzero exit code."
}

Invoke-Test -Name "Repository validation fails when strict workstation validation fails" -Body {
    $failed = Invoke-WithEmptyToolPath -Body {
        try {
            & $repositoryValidation `
                -RepoRoot $repoRoot `
                -SkipTemplateValidation `
                -SkipPlatformAssetValidation 3>&1 2>&1 | Out-String | Out-Null
            return $false
        }
        catch {
            Assert-True `
                -Condition $_.Exception.Message.Contains("Missing required workstation tools") `
                -Message "Repository validation should propagate strict workstation validation failures."
            return $true
        }
    }

    Assert-True -Condition $failed -Message "Repository validation should fail when required workstation tools are absent."
}

Invoke-Test -Name "Repository validation uses public preset values and normalized selections" -Body {
    $testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("repository-validation-test-" + [Guid]::NewGuid().ToString("N"))
    $logPath = Join-Path ([System.IO.Path]::GetTempPath()) ("repository-validation-log-" + [Guid]::NewGuid().ToString("N") + ".jsonl")

    try {
        New-TestRepositoryValidationRepo -Root $testRoot
        $env:REPOSITORY_VALIDATION_ASSET_LOG = $logPath

        & $repositoryValidation `
            -RepoRoot $testRoot `
            -EnvironmentPreset dev `
            -SchemaValidator kubeconform 3>&1 2>&1 | Out-String | Out-Null

        $records = @(Get-Content -Path $logPath | ForEach-Object { $_ | ConvertFrom-Json })
        $record = $records[0]
        $expectedValuesFile = Resolve-RepoPath -Root $testRoot -Path "config\platform-values.env.example"

        Assert-Equal -Expected 1 -Actual $records.Count -Message "Repository validation should run one platform asset validation step."
        Assert-Equal -Expected $testRoot -Actual $record.RepoRoot -Message "Repository validation should forward the selected repository root."
        Assert-Equal -Expected $expectedValuesFile -Actual $record.ValuesFile -Message "ValidationValuesFile should take precedence over private preset ValuesFile."
        Assert-Equal -Expected "2.4.6-dev" -Actual $record.Version -Message "Preset version should be forwarded."
        Assert-Equal -Expected "web-platform" -Actual $record.Profile -Message "Preset profile should be forwarded."
        Assert-SequenceEqual -Expected @("nginx-web", "httpbin", "whoami") -Actual @($record.Applications) -Message "Preset applications should be normalized before validation."
        Assert-SequenceEqual -Expected @("postgresql", "redis") -Actual @($record.DataServices) -Message "Preset data services should be normalized before validation."
        Assert-True -Condition $record.IncludeJenkins -Message "Preset IncludeJenkins should be forwarded."
        Assert-True -Condition $record.PrepareHelmRepos -Message "Preset PrepareHelmRepos should be forwarded."
        Assert-True -Condition $record.Strict -Message "Preset Strict should be forwarded."
        Assert-True -Condition $record.ValidateCrdBackedResources -Message "Preset CRD validation should be forwarded."
        Assert-Equal -Expected "kubeconform" -Actual $record.SchemaValidator -Message "Explicit schema validator should be forwarded with preset data."
        Assert-True -Condition $record.RequireBootstrapSecretsReady -Message "Preset bootstrap secret readiness should be forwarded."
    }
    finally {
        Remove-Item Env:REPOSITORY_VALIDATION_ASSET_LOG -ErrorAction SilentlyContinue
        if (Test-Path -LiteralPath $testRoot) {
            Remove-Item -LiteralPath $testRoot -Recurse -Force
        }
        if (Test-Path -LiteralPath $logPath) {
            Remove-Item -LiteralPath $logPath -Force
        }
    }
}

Invoke-Test -Name "Repository validation explicit values override preset validation values" -Body {
    $testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("repository-validation-test-" + [Guid]::NewGuid().ToString("N"))
    $logPath = Join-Path ([System.IO.Path]::GetTempPath()) ("repository-validation-log-" + [Guid]::NewGuid().ToString("N") + ".jsonl")
    $overrideValuesFile = "config\platform-values.explicit.env"

    try {
        New-TestRepositoryValidationRepo -Root $testRoot
        $env:REPOSITORY_VALIDATION_ASSET_LOG = $logPath

        & $repositoryValidation `
            -RepoRoot $testRoot `
            -EnvironmentPreset dev `
            -ValuesFile $overrideValuesFile 3>&1 2>&1 | Out-String | Out-Null

        $record = @(Get-Content -Path $logPath | ForEach-Object { $_ | ConvertFrom-Json })[0]
        $expectedValuesFile = Resolve-RepoPath -Root $testRoot -Path $overrideValuesFile

        Assert-Equal `
            -Expected $expectedValuesFile `
            -Actual $record.ValuesFile `
            -Message "Explicit ValuesFile should override preset ValidationValuesFile."
    }
    finally {
        Remove-Item Env:REPOSITORY_VALIDATION_ASSET_LOG -ErrorAction SilentlyContinue
        if (Test-Path -LiteralPath $testRoot) {
            Remove-Item -LiteralPath $testRoot -Recurse -Force
        }
        if (Test-Path -LiteralPath $logPath) {
            Remove-Item -LiteralPath $logPath -Force
        }
    }
}

Invoke-Test -Name "Repository validation forwards preset rendered path and Helm config" -Body {
    $testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("repository-validation-test-" + [Guid]::NewGuid().ToString("N"))
    $logPath = Join-Path ([System.IO.Path]::GetTempPath()) ("repository-validation-log-" + [Guid]::NewGuid().ToString("N") + ".jsonl")
    $renderedPath = "out\rendered-dev"
    $helmConfigFile = "config\helm-releases.psd1"

    try {
        New-TestRepositoryValidationRepo -Root $testRoot
        New-TestTextFile `
            -Root $testRoot `
            -RelativePath "config\environments\rendered.psd1" `
            -Lines @(
                "@{",
                "    ValuesFile = 'config\platform-values.private.env'",
                "    ValidationValuesFile = 'config\platform-values.env.example'",
                "    RenderedPath = '$renderedPath'",
                "    HelmConfigFile = '$helmConfigFile'",
                "    Profile = 'web-platform'",
                "    Applications = @('nginx-web')",
                "    SkipTemplateValidation = `$true",
                "    SkipWorkstationValidation = `$true",
                "}"
            )
        New-TestTextFile `
            -Root $testRoot `
            -RelativePath $helmConfigFile `
            -Lines @("@{}")
        New-Item -ItemType Directory -Path (Join-Path $testRoot $renderedPath) -Force | Out-Null
        $env:REPOSITORY_VALIDATION_ASSET_LOG = $logPath

        & $repositoryValidation `
            -RepoRoot $testRoot `
            -EnvironmentPreset rendered 3>&1 2>&1 | Out-String | Out-Null

        $record = @(Get-Content -Path $logPath | ForEach-Object { $_ | ConvertFrom-Json })[0]
        $expectedRenderedPath = Resolve-RepoPath -Root $testRoot -Path $renderedPath
        $expectedHelmConfigFile = Resolve-RepoPath -Root $testRoot -Path $helmConfigFile

        Assert-Equal `
            -Expected $expectedRenderedPath `
            -Actual $record.RenderedPath `
            -Message "Preset RenderedPath should resolve from the repository root before platform asset validation."
        Assert-Equal `
            -Expected $expectedHelmConfigFile `
            -Actual $record.HelmConfigFile `
            -Message "Preset HelmConfigFile should resolve from the repository root before platform asset validation."
    }
    finally {
        Remove-Item Env:REPOSITORY_VALIDATION_ASSET_LOG -ErrorAction SilentlyContinue
        if (Test-Path -LiteralPath $testRoot) {
            Remove-Item -LiteralPath $testRoot -Recurse -Force
        }
        if (Test-Path -LiteralPath $logPath) {
            Remove-Item -LiteralPath $logPath -Force
        }
    }
}

Invoke-Test -Name "Repository validation rejects missing rendered path before asset validation" -Body {
    $testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("repository-validation-test-" + [Guid]::NewGuid().ToString("N"))
    $logPath = Join-Path ([System.IO.Path]::GetTempPath()) ("repository-validation-log-" + [Guid]::NewGuid().ToString("N") + ".jsonl")
    $missingRenderedPath = "out\missing-rendered-dev"
    $failed = $false

    try {
        New-TestRepositoryValidationRepo -Root $testRoot
        $env:REPOSITORY_VALIDATION_ASSET_LOG = $logPath

        try {
            & $repositoryValidation `
                -RepoRoot $testRoot `
                -EnvironmentPreset dev `
                -RenderedPath $missingRenderedPath 3>&1 2>&1 | Out-String | Out-Null
        }
        catch {
            $failed = $true
            Assert-Equal `
                -Expected ("Rendered bundle path does not exist: {0}" -f (Resolve-RepoPath -Root $testRoot -Path $missingRenderedPath)) `
                -Actual $_.Exception.Message `
                -Message "Missing rendered bundle paths should fail before platform asset validation runs."
        }

        Assert-True -Condition $failed -Message "Repository validation should reject missing rendered bundle paths."
        Assert-False -Condition (Test-Path -LiteralPath $logPath) -Message "Asset validation should not run after rendered path validation fails."
    }
    finally {
        Remove-Item Env:REPOSITORY_VALIDATION_ASSET_LOG -ErrorAction SilentlyContinue
        if (Test-Path -LiteralPath $testRoot) {
            Remove-Item -LiteralPath $testRoot -Recurse -Force
        }
        if (Test-Path -LiteralPath $logPath) {
            Remove-Item -LiteralPath $logPath -Force
        }
    }
}

Invoke-Test -Name "Repository validation rejects bootstrap secret readiness when asset validation is skipped" -Body {
    $failed = $false

    try {
        & $repositoryValidation `
            -RepoRoot $repoRoot `
            -RequireBootstrapSecretsReady `
            -SkipPlatformAssetValidation `
            -SkipTemplateValidation `
            -SkipWorkstationValidation 3>&1 2>&1 | Out-String | Out-Null
    }
    catch {
        $failed = $true
        Assert-Equal `
            -Expected "-RequireBootstrapSecretsReady cannot be used together with -SkipPlatformAssetValidation." `
            -Actual $_.Exception.Message `
            -Message "Repository validation should fail before running a contradictory asset validation request."
    }

    Assert-True -Condition $failed -Message "Repository validation should reject bootstrap readiness when asset validation is skipped."
}

Invoke-Test -Name "Test-UnsafeDeletionTarget blocks root and repository paths" -Body {
    $safeChildPath = Join-Path $repoRoot "out\delivery\dev"

    Assert-True `
        -Condition (Test-UnsafeDeletionTarget -Path ([System.IO.Path]::GetPathRoot($repoRoot)) -RepoPath $repoRoot) `
        -Message "Filesystem roots should not be cleanable workflow targets."

    Assert-True `
        -Condition (Test-UnsafeDeletionTarget -Path $repoRoot -RepoPath $repoRoot) `
        -Message "The repository root should not be a cleanable workflow target."

    Assert-False `
        -Condition (Test-UnsafeDeletionTarget -Path $safeChildPath -RepoPath $repoRoot) `
        -Message "A nested delivery output path should be cleanable."
}

if ($script:TestsFailed -gt 0) {
    throw ("{0} of {1} repository workflow helper test(s) failed." -f $script:TestsFailed, $script:TestsRun)
}

Write-Host ("All {0} repository workflow helper test(s) passed." -f $script:TestsRun)
