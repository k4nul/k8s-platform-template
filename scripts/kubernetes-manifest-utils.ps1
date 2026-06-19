Set-StrictMode -Version Latest

function Get-RelativePathFromRoot {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Root,

        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $resolvedRoot = [System.IO.Path]::GetFullPath($Root).TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
    $resolvedPath = [System.IO.Path]::GetFullPath($Path)
    $rootPrefix = $resolvedRoot + [System.IO.Path]::DirectorySeparatorChar

    if ($resolvedPath.StartsWith($rootPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $resolvedPath.Substring($rootPrefix.Length)
    }

    return $resolvedPath
}

function Get-BuiltInApiGroups {
    return @(
        "admissionregistration.k8s.io",
        "apiextensions.k8s.io",
        "apiregistration.k8s.io",
        "apps",
        "authentication.k8s.io",
        "authorization.k8s.io",
        "autoscaling",
        "batch",
        "certificates.k8s.io",
        "coordination.k8s.io",
        "discovery.k8s.io",
        "events.k8s.io",
        "extensions",
        "flowcontrol.apiserver.k8s.io",
        "networking.k8s.io",
        "node.k8s.io",
        "policy",
        "rbac.authorization.k8s.io",
        "scheduling.k8s.io",
        "storage.k8s.io"
    )
}

function Normalize-ApiVersionValue {
    param(
        [string]$Value
    )

    if (-not $Value) {
        return ""
    }

    $withoutComment = ($Value -split '\s+#', 2)[0].Trim()
    return $withoutComment.Trim([char[]]@('"', "'"))
}

function Normalize-YamlScalarValue {
    param(
        [string]$Value
    )

    if (-not $Value) {
        return ""
    }

    $normalized = ($Value -replace '\s+#.*$', '').Trim()
    if ($normalized -match '^&[A-Za-z0-9_-]+\s+(.+)$') {
        $normalized = $Matches[1].Trim()
    }

    if ($normalized -match '^\*[A-Za-z0-9_-]+$') {
        return ""
    }

    if (
        ($normalized.StartsWith('"') -and $normalized.EndsWith('"')) -or
        ($normalized.StartsWith("'") -and $normalized.EndsWith("'"))
    ) {
        $normalized = $normalized.Substring(1, $normalized.Length - 2)
    }

    return $normalized.Trim()
}

function Test-MeaningfulYamlDocument {
    param(
        [string]$Content
    )

    foreach ($line in ($Content -split "`r?`n")) {
        $trimmed = $line.Trim()
        if ($trimmed -and -not $trimmed.StartsWith("#")) {
            return $true
        }
    }

    return $false
}

function Get-YamlDocumentBlocks {
    param(
        [string]$Content
    )

    $normalized = $Content -replace "`r`n?", "`n"
    return @(
        [regex]::Split($normalized, '(?m)^\s*---\s*(?:#.*)?$') |
            ForEach-Object { $_.Trim() } |
            Where-Object { Test-MeaningfulYamlDocument -Content $_ }
    )
}

function Get-YamlDocumentMetadata {
    param(
        [string]$Document
    )

    $apiVersion = ""
    $kind = ""
    $name = ""
    $namespace = ""

    $apiVersionMatch = [regex]::Match($Document, '(?m)^apiVersion:\s*(.+)$')
    if ($apiVersionMatch.Success) {
        $apiVersion = Normalize-YamlScalarValue -Value $apiVersionMatch.Groups[1].Value
    }

    $kindMatch = [regex]::Match($Document, '(?m)^kind:\s*(.+)$')
    if ($kindMatch.Success) {
        $kind = Normalize-YamlScalarValue -Value $kindMatch.Groups[1].Value
    }

    $metadataMatch = [regex]::Match($Document, '(?ms)^metadata:\s*\r?\n(?<body>(?:[ \t].*(?:\r?\n|$))*)')
    if ($metadataMatch.Success) {
        $metadataBody = $metadataMatch.Groups["body"].Value

        $nameMatch = [regex]::Match($metadataBody, '(?m)^\s*name:\s*(.+)$')
        if ($nameMatch.Success) {
            $name = Normalize-YamlScalarValue -Value $nameMatch.Groups[1].Value
        }

        $namespaceMatch = [regex]::Match($metadataBody, '(?m)^\s*namespace:\s*(.+)$')
        if ($namespaceMatch.Success) {
            $namespace = Normalize-YamlScalarValue -Value $namespaceMatch.Groups[1].Value
        }
    }

    return [PSCustomObject]@{
        ApiVersion = $apiVersion
        Kind = $kind
        Name = $name
        Namespace = $namespace
    }
}

function Get-CrdBackedApiGroupsFromContent {
    param(
        [string]$Content
    )

    $builtInApiGroups = @(Get-BuiltInApiGroups)
    $apiGroups = New-Object System.Collections.Generic.List[string]

    foreach ($match in [regex]::Matches($Content, '(?m)^apiVersion:\s*(.+)$')) {
        $apiVersion = Normalize-YamlScalarValue -Value $match.Groups[1].Value
        if ($apiVersion -notmatch '^([^/]+)/') {
            continue
        }

        $apiGroup = $Matches[1]
        if ($builtInApiGroups -notcontains $apiGroup) {
            $apiGroups.Add($apiGroup) | Out-Null
        }
    }

    return @($apiGroups | Sort-Object -Unique)
}
