param(
    [Parameter(Mandatory = $true)]
    [string]$InputPath,

    [Parameter(Mandatory = $true)]
    [string]$OutputPath,

    [string]$DockerRegistry,

    [string]$Version,
    [string]$ValuesFile,
    [switch]$FailOnUnresolvedToken
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "..\scripts\template-rendering.ps1")

function Render-ManifestFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourcePath,

        [Parameter(Mandatory = $true)]
        [string]$DestinationPath,

        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$ReplacementMap
    )

    $content = Get-Content -Path $SourcePath -Raw
    $content = Expand-TemplateContent -Content $content -ReplacementMap $ReplacementMap

    $destinationDir = Split-Path -Path $DestinationPath -Parent
    if ($destinationDir) {
        New-Item -ItemType Directory -Path $destinationDir -Force | Out-Null
    }

    Set-Content -Path $DestinationPath -Value $content -NoNewline
    return $DestinationPath
}

$resolvedInput = (Resolve-Path -Path $InputPath).Path
$replacementMap = Get-TemplateReplacementMap -ValuesFile $ValuesFile -DockerRegistry $DockerRegistry -Version $Version
$renderedPaths = New-Object System.Collections.Generic.List[string]

if (Test-Path -Path $resolvedInput -PathType Leaf) {
    $renderedPaths.Add(
        (Render-ManifestFile -SourcePath $resolvedInput -DestinationPath $OutputPath -ReplacementMap $replacementMap)
    ) | Out-Null
}
else {
    $sourceRoot = [System.IO.Path]::GetFullPath($resolvedInput)
    $targetRoot = [System.IO.Path]::GetFullPath($OutputPath)

    Get-ChildItem -Path $sourceRoot -Recurse -File | Where-Object {
        $_.Extension -in @(".yaml", ".yml")
    } | ForEach-Object {
        $relativePath = Get-RelativePathCompat -BasePath $sourceRoot -TargetPath $_.FullName
        $destinationPath = Join-Path -Path $targetRoot -ChildPath $relativePath
        $renderedPaths.Add(
            (Render-ManifestFile -SourcePath $_.FullName -DestinationPath $destinationPath -ReplacementMap $replacementMap)
        ) | Out-Null
    }
}

$unresolvedMatches = @(Get-UnresolvedTemplateMatches -Paths $renderedPaths.ToArray())
if ($unresolvedMatches.Count -gt 0) {
    $message = ($unresolvedMatches | ForEach-Object {
        "{0}:{1}:{2}" -f $_.Path, $_.LineNumber, $_.Line.Trim()
    }) -join [Environment]::NewLine

    if ($FailOnUnresolvedToken) {
        Write-Error ("Rendered manifest output still contains unresolved template tokens:`n{0}" -f $message)
    }
    else {
        Write-Warning ("Rendered manifest output still contains unresolved template tokens:`n{0}" -f $message)
    }
}

if (Test-Path -Path $resolvedInput -PathType Leaf) {
    exit 0
}
