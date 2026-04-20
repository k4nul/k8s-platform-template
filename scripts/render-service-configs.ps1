param(
    [string]$InputPath,

    [Parameter(Mandatory = $true)]
    [string]$OutputPath,

    [string]$ValuesFile,
    [string]$DockerRegistry,
    [string]$Version,
    [switch]$FailOnUnresolvedToken
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "template-rendering.ps1")

if (-not $PSBoundParameters.ContainsKey("InputPath") -or -not $InputPath) {
    $InputPath = Join-Path $PSScriptRoot "..\services"
}

$resolvedInput = (Resolve-Path -Path $InputPath).Path
$sourceRoot = [System.IO.Path]::GetFullPath($resolvedInput)
$targetRoot = [System.IO.Path]::GetFullPath($OutputPath)
$replacementMap = Get-TemplateReplacementMap -ValuesFile $ValuesFile -DockerRegistry $DockerRegistry -Version $Version
$renderedPaths = New-Object System.Collections.Generic.List[string]

Get-ChildItem -Path $sourceRoot -Recurse -File | ForEach-Object {
    $relativePath = Get-RelativePathCompat -BasePath $sourceRoot -TargetPath $_.FullName
    $destinationPath = Join-Path -Path $targetRoot -ChildPath $relativePath
    $destinationDir = Split-Path -Path $destinationPath -Parent

    if ($destinationDir) {
        New-Item -ItemType Directory -Path $destinationDir -Force | Out-Null
    }

    $content = Get-Content -Path $_.FullName -Raw
    $content = Expand-TemplateContent -Content $content -ReplacementMap $replacementMap
    Set-Content -Path $destinationPath -Value $content -NoNewline
    $renderedPaths.Add($destinationPath) | Out-Null
}

$unresolvedMatches = @(Get-UnresolvedTemplateMatches -Paths $renderedPaths.ToArray())
if ($unresolvedMatches.Count -gt 0) {
    $message = ($unresolvedMatches | ForEach-Object {
        "{0}:{1}:{2}" -f $_.Path, $_.LineNumber, $_.Line.Trim()
    }) -join [Environment]::NewLine

    if ($FailOnUnresolvedToken) {
        Write-Error ("Rendered service output still contains unresolved template tokens:`n{0}" -f $message)
    }
    else {
        Write-Warning ("Rendered service output still contains unresolved template tokens:`n{0}" -f $message)
    }
}

Write-Host ("Rendered {0} service template files to {1}" -f $renderedPaths.Count, $targetRoot)
