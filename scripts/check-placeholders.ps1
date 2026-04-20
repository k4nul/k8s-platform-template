param(
    [string]$Path = ".",
    [switch]$FailOnMatch
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$root = (Resolve-Path -Path $Path).Path
$includeExtensions = @(".yaml", ".yml", ".json", ".ini", ".env", ".conf", ".properties")
$includeFileNames = @("Jenkinsfile")
$excludePathFragments = @("\.git\", "\out\", "\__pycache__\")

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
    $excludedMatches = @($excludePathFragments | Where-Object { $filePath.Contains($_.ToLowerInvariant()) })
    $isExcludedPath = $excludedMatches.Count -gt 0
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
    exit 0
}

$matches |
    Sort-Object File, Line |
    Format-Table -AutoSize

Write-Warning ("Found {0} placeholder matches. Review them before deployment." -f $matches.Count)

if ($FailOnMatch) {
    exit 1
}
