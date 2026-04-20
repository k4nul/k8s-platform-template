Set-StrictMode -Version Latest

function Get-RelativePathCompat {
    param(
        [Parameter(Mandatory = $true)]
        [string]$BasePath,

        [Parameter(Mandatory = $true)]
        [string]$TargetPath
    )

    $normalizedBase = [System.IO.Path]::GetFullPath($BasePath).TrimEnd('\') + '\'
    $baseUri = New-Object System.Uri($normalizedBase)
    $targetUri = New-Object System.Uri([System.IO.Path]::GetFullPath($TargetPath))

    return [System.Uri]::UnescapeDataString(
        $baseUri.MakeRelativeUri($targetUri).ToString()
    ).Replace('/', [System.IO.Path]::DirectorySeparatorChar)
}

function Get-TemplateReplacementMap {
    param(
        [string]$ValuesFile,
        [string]$DockerRegistry,
        [string]$Version
    )

    $replacementMap = [ordered]@{}

    if ($PSBoundParameters.ContainsKey("ValuesFile") -and $ValuesFile) {
        $resolvedValuesFile = (Resolve-Path -Path $ValuesFile).Path
        foreach ($line in Get-Content -Path $resolvedValuesFile) {
            $trimmedLine = $line.Trim()
            if (-not $trimmedLine -or $trimmedLine.StartsWith("#")) {
                continue
            }

            $delimiterIndex = $trimmedLine.IndexOf("=")
            if ($delimiterIndex -lt 1) {
                throw "Invalid values file entry: $trimmedLine"
            }

            $key = $trimmedLine.Substring(0, $delimiterIndex).Trim()
            $value = $trimmedLine.Substring($delimiterIndex + 1)

            if ($key -notmatch '^[A-Z0-9_]+$') {
                throw "Unsupported values file key: $key"
            }

            $replacementMap["__{0}__" -f $key] = $value
        }
    }

    if ($PSBoundParameters.ContainsKey("DockerRegistry") -and $DockerRegistry) {
        $replacementMap["__DOCKER_REGISTRY__"] = $DockerRegistry
    }

    if ($PSBoundParameters.ContainsKey("Version") -and $Version) {
        $replacementMap['$VERSION'] = $Version
    }

    return $replacementMap
}

function Expand-TemplateContent {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Content,

        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$ReplacementMap
    )

    $expandedContent = $Content
    foreach ($replacement in $ReplacementMap.GetEnumerator()) {
        $expandedContent = $expandedContent.Replace([string]$replacement.Key, [string]$replacement.Value)
    }

    return $expandedContent
}

function Get-UnresolvedTemplateMatches {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Paths
    )

    $existingPaths = @($Paths | Where-Object { $_ -and (Test-Path -Path $_ -PathType Leaf) })
    if ($existingPaths.Count -eq 0) {
        return @()
    }

    return @(Select-String -Path $existingPaths -Pattern '__[A-Z0-9_]+__|\$VERSION' -CaseSensitive -ErrorAction SilentlyContinue)
}
