param(
    [string]$Path = ".",
    [switch]$FailOnMatch
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$root = (Resolve-Path -Path $Path).Path
$includeExtensions = @(".yaml", ".yml", ".json", ".ini", ".env", ".conf", ".properties")
$includeFileNames = @("Jenkinsfile")
$excludedDirectoryNames = @(".git", "__pycache__")

function Get-NormalizedRelativePath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Root,

        [Parameter(Mandatory = $true)]
        [string]$ChildPath
    )

    return ([System.IO.Path]::GetRelativePath($Root, $ChildPath)).Replace('\', '/')
}

function Test-ExcludedPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Root,

        [Parameter(Mandatory = $true)]
        [string]$ChildPath
    )

    $relativePath = Get-NormalizedRelativePath -Root $Root -ChildPath $ChildPath
    $segments = @($relativePath -split "/" | Where-Object { $_ })

    if ($segments.Count -eq 0) {
        return $false
    }

    if ($excludedDirectoryNames -contains $segments[0]) {
        return $true
    }

    foreach ($segment in $segments) {
        if ($excludedDirectoryNames -contains $segment) {
            return $true
        }
    }

    return ($segments[0] -eq "out")
}

$patterns = @(
    @{ Name = "Example Domain"; Regex = "example\.com" },
    @{ Name = "Placeholder Password"; Regex = "CHANGE_ME|change-me-[a-z0-9-]+" },
    @{ Name = "Provider Placeholder"; Regex = "__REPLACE_WITH_PROVIDER_NAME__" },
    @{ Name = "Example Registry"; Regex = "registry\.example\.com" },
    @{ Name = "Example NFS Host"; Regex = "nfs\.example\.internal" },
    @{ Name = "Example Database Host"; Regex = "(staging-)?db\.example\.internal" },
    @{ Name = "Example Update Domain"; Regex = "(staging-)?updates\.example\.com" },
    @{ Name = "Placeholder Secret Key"; Regex = "change-me-secret" }
)

$files = Get-ChildItem -Path $root -Recurse -File | Where-Object {
    $filePath = $_.FullName.ToLowerInvariant()
    $isIncludedExtension = $includeExtensions -contains $_.Extension.ToLowerInvariant()
    $isIncludedName = $includeFileNames -contains $_.Name
    $isIncludedExampleEnv = $filePath.EndsWith(".env.example")
    $isExcludedPath = Test-ExcludedPath -Root $root -ChildPath $_.FullName
    ($isIncludedExtension -or $isIncludedName -or $isIncludedExampleEnv) -and -not $isExcludedPath
}

$matches = New-Object System.Collections.Generic.List[object]

foreach ($file in $files) {
    foreach ($pattern in $patterns) {
        $results = Select-String -Path $file.FullName -Pattern $pattern.Regex
        foreach ($result in $results) {
            $matches.Add([PSCustomObject]@{
                Type = $pattern.Name
                File = $file.FullName
                Line = $result.LineNumber
                Text = $result.Line.Trim()
            })
        }
    }
}

if ($matches.Count -eq 0) {
    Write-Host "No tracked placeholder values were found."
    return
}

$matches |
    Sort-Object File, Line |
    Format-Table -AutoSize

Write-Warning ("Found {0} placeholder matches. Review them before deployment." -f $matches.Count)

if ($FailOnMatch) {
    throw ("Placeholder scan found {0} placeholder match(es)." -f $matches.Count)
}
