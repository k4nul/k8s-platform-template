Set-StrictMode -Version Latest

function Resolve-RepoPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Root,

        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if ([System.IO.Path]::IsPathRooted($Path)) {
        return [System.IO.Path]::GetFullPath($Path)
    }

    return [System.IO.Path]::GetFullPath((Join-Path $Root $Path))
}

function Normalize-List {
    param(
        [string[]]$Values = @()
    )

    $normalized = New-Object System.Collections.Generic.List[string]

    foreach ($value in @($Values)) {
        if ($null -eq $value) {
            continue
        }

        foreach ($entry in ($value -split ",")) {
            $trimmed = $entry.Trim()
            if ($trimmed) {
                $normalized.Add($trimmed) | Out-Null
            }
        }
    }

    return @($normalized)
}

function Get-ListText {
    param(
        [string[]]$Values = @(),
        [string]$Empty = "none"
    )

    if (@($Values).Count -gt 0) {
        return (@($Values) -join ", ")
    }

    return $Empty
}

function Invoke-RepositoryWorkflowStep {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Title,

        [Parameter(Mandatory = $true)]
        [ScriptBlock]$Action
    )

    Write-Host ("== {0} ==" -f $Title)
    $global:LASTEXITCODE = 0
    & $Action
    if ($null -ne $global:LASTEXITCODE -and $global:LASTEXITCODE -ne 0) {
        throw ("Repository workflow step '{0}' failed with exit code {1}." -f $Title, $global:LASTEXITCODE)
    }

    Write-Host ("Completed: {0}" -f $Title)
    Write-Host ""
}

function Test-UnsafeDeletionTarget {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$RepoPath
    )

    $resolvedPath = [System.IO.Path]::GetFullPath($Path).TrimEnd('\')
    $resolvedRepoPath = [System.IO.Path]::GetFullPath($RepoPath).TrimEnd('\')
    $pathRoot = [System.IO.Path]::GetPathRoot($resolvedPath).TrimEnd('\')

    if (-not $resolvedPath -or $resolvedPath.Length -le ($pathRoot.Length + 1)) {
        return $true
    }

    if ($resolvedPath -eq $resolvedRepoPath) {
        return $true
    }

    return $false
}
