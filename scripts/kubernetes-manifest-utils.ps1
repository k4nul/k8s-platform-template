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

function Get-CrdBackedApiGroupsFromContent {
    param(
        [string]$Content
    )

    $builtInApiGroups = @(Get-BuiltInApiGroups)
    $apiGroups = New-Object System.Collections.Generic.List[string]

    foreach ($match in [regex]::Matches($Content, '(?m)^apiVersion:\s*(.+)$')) {
        $apiVersion = Normalize-ApiVersionValue -Value $match.Groups[1].Value
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
