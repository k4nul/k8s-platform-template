param(
    [Parameter(Mandatory = $true)]
    [string]$BaselinePath,

    [Parameter(Mandatory = $true)]
    [string]$CandidatePath,

    [string]$ApprovalFile,

    [ValidateSet("text", "json")]
    [string]$Format = "text"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-ManifestInventory {
    param([Parameter(Mandatory = $true)][string]$RootPath)

    $root = (Resolve-Path -LiteralPath $RootPath).Path
    $inventory = @{}
    $files = @(Get-ChildItem -LiteralPath $root -Recurse -File | Where-Object { $_.Extension -in @(".yaml", ".yml") })

    foreach ($file in $files) {
        $relativePath = [System.IO.Path]::GetRelativePath($root, $file.FullName).Replace('\', '/')
        $documents = @([regex]::Split((Get-Content -LiteralPath $file.FullName -Raw), '(?m)^\s*---\s*$'))
        foreach ($document in $documents) {
            $normalized = $document.Trim()
            if (-not $normalized) {
                continue
            }

            $kindMatch = [regex]::Match($normalized, '(?m)^kind:\s*(?<value>[^\s#]+)\s*$')
            $metadataMatch = [regex]::Match($normalized, '(?ms)^metadata:\s*\r?\n(?<body>(?:[ \t]+[^\r\n]*(?:\r?\n|$))*)')
            if (-not $kindMatch.Success -or -not $metadataMatch.Success) {
                throw "Manifest document lacks kind or metadata: $relativePath"
            }

            $metadata = $metadataMatch.Groups['body'].Value
            $nameMatch = [regex]::Match($metadata, '(?m)^\s+name:\s*(?<value>[^\s#]+)\s*$')
            $namespaceMatch = [regex]::Match($metadata, '(?m)^\s+namespace:\s*(?<value>[^\s#]+)\s*$')
            if (-not $nameMatch.Success) {
                throw "Manifest document lacks metadata.name: $relativePath"
            }

            $kind = $kindMatch.Groups['value'].Value
            $namespace = if ($namespaceMatch.Success) { $namespaceMatch.Groups['value'].Value } else { "_cluster" }
            $resource = "{0}/{1}/{2}" -f $kind, $namespace, $nameMatch.Groups['value'].Value
            if ($inventory.ContainsKey($resource)) {
                throw "Duplicate rendered resource identity: $resource"
            }

            $inventory[$resource] = [pscustomobject]@{
                Resource = $resource
                Kind = $kind
                Path = $relativePath
                Content = $normalized
            }
        }
    }

    return $inventory
}

function Get-ChangedFields {
    param(
        [Parameter(Mandatory = $true)][object]$Baseline,
        [Parameter(Mandatory = $true)][object]$Candidate
    )

    $sensitiveKeys = @(
        "securityContext", "privileged", "allowPrivilegeEscalation", "runAsUser",
        "runAsNonRoot", "readOnlyRootFilesystem", "capabilities", "hostNetwork",
        "hostPID", "hostIPC", "serviceAccountName", "automountServiceAccountToken",
        "resources", "requests", "limits", "image"
    )
    $keyPattern = '^\s*(?<key>{0})\s*:' -f (($sensitiveKeys | ForEach-Object { [regex]::Escape($_) }) -join '|')
    $changedLines = @(
        Compare-Object `
            -ReferenceObject @($Baseline.Content -split "`r?`n") `
            -DifferenceObject @($Candidate.Content -split "`r?`n") |
            ForEach-Object { [string]$_.InputObject }
    )
    $fields = @(
        foreach ($line in $changedLines) {
            $match = [regex]::Match($line, $keyPattern)
            if ($match.Success) {
                $match.Groups['key'].Value
            }
        }
    )
    if ($Baseline.Kind -match '^(ClusterRole|ClusterRoleBinding|Role|RoleBinding)$') {
        $fields += "rbac"
    }
    if ($Baseline.Kind -eq "NetworkPolicy") {
        $fields += "networkPolicy"
    }
    if ($fields.Count -eq 0) {
        $fields = @("content")
    }

    return @($fields | Sort-Object -Unique)
}

function Get-ApprovalKeys {
    param([string]$Path)

    $keys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    if (-not $Path) {
        return ,$keys
    }

    $approval = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    $topLevelNames = @($approval.PSObject.Properties.Name)
    $unexpectedTopLevel = @($topLevelNames | Where-Object { $_ -notin @("schemaVersion", "approvedDifferences") })
    if ($unexpectedTopLevel.Count -gt 0 -or $approval.schemaVersion -ne "1.0.0") {
        throw "Drift approval file must use schemaVersion 1.0.0 and only approvedDifferences."
    }

    foreach ($entry in @($approval.approvedDifferences)) {
        $propertyNames = @($entry.PSObject.Properties.Name)
        $unexpectedProperties = @($propertyNames | Where-Object { $_ -notin @("type", "resource", "fields", "reason") })
        if ($unexpectedProperties.Count -gt 0) {
            throw "Drift approval entries may contain only type, resource, fields, and reason."
        }
        $type = ([string]$entry.type).Trim().ToLowerInvariant()
        $resource = ([string]$entry.resource).Trim()
        $reason = ([string]$entry.reason).Trim()
        $fields = @($entry.fields | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ })
        if ($type -notin @("added", "removed", "modified") -or -not $resource -or -not $reason -or $fields.Count -eq 0) {
            throw "Drift approval entries require a supported type, resource, fields, and reason."
        }
        foreach ($field in $fields) {
            [void]$keys.Add("$type|$resource|$field")
        }
    }

    return ,$keys
}

$baseline = Get-ManifestInventory -RootPath $BaselinePath
$candidate = Get-ManifestInventory -RootPath $CandidatePath
$approvalKeys = Get-ApprovalKeys -Path $ApprovalFile
$differences = @()

foreach ($resource in @($baseline.Keys + $candidate.Keys | Sort-Object -Unique)) {
    if (-not $baseline.ContainsKey($resource)) {
        $differences += [pscustomobject]@{ Type = "added"; Resource = $resource; Path = $candidate[$resource].Path; Fields = @("resource") }
        continue
    }
    if (-not $candidate.ContainsKey($resource)) {
        $differences += [pscustomobject]@{ Type = "removed"; Resource = $resource; Path = $baseline[$resource].Path; Fields = @("resource") }
        continue
    }
    if ($baseline[$resource].Content -ne $candidate[$resource].Content) {
        $differences += [pscustomobject]@{
            Type = "modified"
            Resource = $resource
            Path = $candidate[$resource].Path
            Fields = @(Get-ChangedFields -Baseline $baseline[$resource] -Candidate $candidate[$resource])
        }
    }
}

$actualKeys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
$results = @(
    foreach ($difference in $differences) {
        $requiredKeys = @($difference.Fields | ForEach-Object { "$($difference.Type)|$($difference.Resource)|$_" })
        foreach ($key in $requiredKeys) {
            [void]$actualKeys.Add($key)
        }
        [pscustomobject]@{
            type = $difference.Type
            resource = $difference.Resource
            path = $difference.Path
            fields = $difference.Fields
            approved = @($requiredKeys | Where-Object { -not $approvalKeys.Contains($_) }).Count -eq 0
        }
    }
)

$staleApprovals = @($approvalKeys | Where-Object { -not $actualKeys.Contains($_) })
if ($staleApprovals.Count -gt 0) {
    throw "Drift approval file contains stale or mismatched entries: $($staleApprovals -join ', ')"
}

if ($Format -eq "json") {
    [pscustomobject]@{
        baselineResourceCount = $baseline.Count
        candidateResourceCount = $candidate.Count
        differenceCount = $results.Count
        unexpectedCount = @($results | Where-Object { -not $_.approved }).Count
        differences = $results
    } | ConvertTo-Json -Depth 8
}
else {
    foreach ($result in $results) {
        $label = if ($result.approved) { "APPROVED" } else { "UNEXPECTED" }
        Write-Output ("[{0}] {1} {2} fields={3} path={4}" -f $label, $result.type, $result.resource, ($result.fields -join ","), $result.path)
    }
    Write-Output ("Rendered drift summary: baseline={0} candidate={1} differences={2} unexpected={3}" -f $baseline.Count, $candidate.Count, $results.Count, @($results | Where-Object { -not $_.approved }).Count)
}

$unexpected = @($results | Where-Object { -not $_.approved })
if ($unexpected.Count -gt 0) {
    throw "Rendered environment drift rejected: $($unexpected.Count) unexpected difference(s)."
}
