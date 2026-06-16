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
