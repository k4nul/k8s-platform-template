param(
    [string]$Path,
    [switch]$FailOnHighFinding,
    [switch]$FailOnMediumFinding,
    [switch]$IncludeOptionalManifests
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "kubernetes-manifest-utils.ps1")
. (Join-Path $PSScriptRoot "platform-catalog.ps1")

function Get-NormalizedRelativePathKey {
    param(
        [string]$Path
    )

    if (-not $Path) {
        return ""
    }

    return $Path.Replace('\', '/').TrimStart('/').ToLowerInvariant()
}

function Get-FirstMatchLineNumber {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Content,

        [Parameter(Mandatory = $true)]
        [string]$Pattern
    )

    $lines = [regex]::Split($Content, "\r?\n")
    for ($index = 0; $index -lt $lines.Count; $index++) {
        if ($lines[$index] -match $Pattern) {
            return ($index + 1)
        }
    }

    return 0
}

function Add-Finding {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[object]]$Findings,

        [Parameter(Mandatory = $true)]
        [string]$Severity,

        [Parameter(Mandatory = $true)]
        [string]$Id,

        [Parameter(Mandatory = $true)]
        [string]$File,

        [int]$Line = 0,

        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter(Mandatory = $true)]
        [string]$Remediation
    )

    $Findings.Add([PSCustomObject]@{
        Severity = $Severity
        Id = $Id
        File = $File
        Line = $Line
        Message = $Message
        Remediation = $Remediation
    }) | Out-Null
}

function Add-RegexFinding {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[object]]$Findings,

        [Parameter(Mandatory = $true)]
        [string]$Content,

        [Parameter(Mandatory = $true)]
        [string]$Pattern,

        [Parameter(Mandatory = $true)]
        [string]$Severity,

        [Parameter(Mandatory = $true)]
        [string]$Id,

        [Parameter(Mandatory = $true)]
        [string]$File,

        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter(Mandatory = $true)]
        [string]$Remediation
    )

    if ($Content -match $Pattern) {
        Add-Finding `
            -Findings $Findings `
            -Severity $Severity `
            -Id $Id `
            -File $File `
            -Line (Get-FirstMatchLineNumber -Content $Content -Pattern $Pattern) `
            -Message $Message `
            -Remediation $Remediation
    }
}

function Get-IndentLength {
    param(
        [string]$Line
    )

    $match = [regex]::Match($Line, '^(\s*)')
    return $match.Groups[1].Value.Length
}

function Remove-YamlScalarQuotes {
    param(
        [AllowNull()]
        [string]$Value
    )

    if ($null -eq $Value) {
        return ""
    }

    $trimmedValue = $Value.Trim()
    if ($trimmedValue.Length -ge 2) {
        $firstCharacter = $trimmedValue.Substring(0, 1)
        $lastCharacter = $trimmedValue.Substring($trimmedValue.Length - 1, 1)

        if (($firstCharacter -eq '"' -and $lastCharacter -eq '"') -or
            ($firstCharacter -eq "'" -and $lastCharacter -eq "'")) {
            return $trimmedValue.Substring(1, $trimmedValue.Length - 2)
        }
    }

    return $trimmedValue
}

function Get-SecretDataEntries {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Content
    )

    $entries = New-Object System.Collections.Generic.List[object]
    $lines = [regex]::Split($Content, "\r?\n")
    $section = ""
    $sectionIndent = -1

    for ($index = 0; $index -lt $lines.Count; $index++) {
        $line = $lines[$index]
        if (-not $line.Trim()) {
            continue
        }

        if ($line -match '^(\s*)(data|stringData):\s*(?:#.*)?$') {
            $section = $Matches[2]
            $sectionIndent = $Matches[1].Length
            continue
        }

        if (-not $section) {
            continue
        }

        $indent = Get-IndentLength -Line $line
        if ($indent -le $sectionIndent) {
            $section = ""
            $sectionIndent = -1
            continue
        }

        if ($line -notmatch '^\s+([^:#][^:]*):\s*(.*)$') {
            continue
        }

        $key = Remove-YamlScalarQuotes -Value $Matches[1]
        $value = $Matches[2].Trim()
        if ($value -match '^[|>][-+]?$') {
            $blockLines = New-Object System.Collections.Generic.List[string]
            $valueIndent = $indent

            for ($blockIndex = $index + 1; $blockIndex -lt $lines.Count; $blockIndex++) {
                $blockLine = $lines[$blockIndex]
                if (-not $blockLine.Trim()) {
                    $blockLines.Add("") | Out-Null
                    continue
                }

                $blockIndent = Get-IndentLength -Line $blockLine
                if ($blockIndent -le $valueIndent) {
                    break
                }

                $blockLines.Add($blockLine.Trim()) | Out-Null
            }

            $value = ($blockLines -join "`n")
        }

        $entries.Add([PSCustomObject]@{
            Section = $section
            Key = $key
            Value = Remove-YamlScalarQuotes -Value $value
            Line = ($index + 1)
        }) | Out-Null
    }

    return $entries.ToArray()
}

function Test-SensitiveSecretKey {
    param(
        [string]$Key
    )

    return ($Key -match '(?i)(password|passwd|pwd|token|secret|credential|private|tls\.key|\.dockerconfigjson|auth|key$)')
}

function Test-PlaceholderSecretValue {
    param(
        [AllowNull()]
        [string]$Value
    )

    if (-not $Value) {
        return $true
    }

    $normalizedValue = $Value.Trim()
    $placeholderPatterns = @(
        '^__[A-Z0-9_]+__$',
        '^\$VERSION$',
        '(?i)^change-me-[a-z0-9-]+$',
        'REPLACE_WITH_[A-Z0-9_]+',
        'BASE64_ENCODED_[A-Z0-9_]+',
        '\{HTPASSWD_OUTPUT\}',
        'example\.com',
        '^<[^>]+>$'
    )

    foreach ($pattern in $placeholderPatterns) {
        if ($normalizedValue -match $pattern) {
            return $true
        }
    }

    return $false
}

if (-not $PSBoundParameters.ContainsKey("Path") -or -not $Path) {
    $Path = Join-Path $PSScriptRoot ".."
}

$root = (Resolve-Path -Path $Path).Path
$k8sRootCandidate = Join-Path $root "k8s"
$hasK8sRoot = Test-Path -Path $k8sRootCandidate -PathType Container
$primaryScanRoot = if ($hasK8sRoot) {
    $k8sRootCandidate
}
else {
    $root
}

$scanRoots = New-Object System.Collections.Generic.List[string]
$scanRoots.Add($primaryScanRoot) | Out-Null

if ($hasK8sRoot) {
    $bootstrapSecretRoot = Join-Path $root "cluster-bootstrap\secrets"
    if (Test-Path -Path $bootstrapSecretRoot -PathType Container) {
        $scanRoots.Add($bootstrapSecretRoot) | Out-Null
    }
}

$candidateYamlFiles = New-Object System.Collections.Generic.List[object]
foreach ($scanRoot in $scanRoots.ToArray()) {
    Get-ChildItem -Path $scanRoot -Recurse -File | ForEach-Object {
        $candidateYamlFiles.Add($_) | Out-Null
    }
}

$optionalManifestPathMap = @{}
if (-not $IncludeOptionalManifests) {
    foreach ($optionalPath in (Get-PlatformOptionalManifestCatalog).Keys) {
        $pathKey = Get-NormalizedRelativePathKey -Path $optionalPath
        if ($pathKey) {
            $optionalManifestPathMap[$pathKey] = $true
        }
    }
}

$yamlFiles = @(
    $candidateYamlFiles.ToArray() |
        Where-Object {
            $_.Extension.ToLowerInvariant() -in @(".yaml", ".yml") -and
            $_.Name -ne "values.yaml"
        } |
        Sort-Object FullName
)

if ($yamlFiles.Count -eq 0) {
    throw ("No Kubernetes YAML files were found under {0}." -f ($scanRoots.ToArray() -join ", "))
}

$findings = New-Object System.Collections.Generic.List[object]
$hasNetworkPolicy = $false
$skippedOptionalManifests = 0

foreach ($file in $yamlFiles) {
    $relativePath = Get-RelativePathFromRoot -Root $root -Path $file.FullName
    if ($hasK8sRoot -and -not $IncludeOptionalManifests) {
        $relativeK8sPath = Get-RelativePathFromRoot -Root $k8sRootCandidate -Path $file.FullName
        $relativeK8sPathKey = Get-NormalizedRelativePathKey -Path $relativeK8sPath
        if ($optionalManifestPathMap.ContainsKey($relativeK8sPathKey)) {
            $skippedOptionalManifests++
            continue
        }
    }

    $content = Get-Content -Path $file.FullName -Raw

    if ($content -match '(?m)^kind:\s*NetworkPolicy\s*$') {
        $hasNetworkPolicy = $true
    }

    if ($content -match '(?m)^kind:\s*Secret\s*$') {
        foreach ($entry in @(Get-SecretDataEntries -Content $content)) {
            if (-not (Test-SensitiveSecretKey -Key $entry.Key)) {
                continue
            }

            if (Test-PlaceholderSecretValue -Value $entry.Value) {
                continue
            }

            Add-Finding `
                -Findings $findings `
                -Severity "medium" `
                -Id "concrete-secret-template-value" `
                -File $relativePath `
                -Line $entry.Line `
                -Message ("A Secret manifest contains a non-placeholder sensitive value for key '{0}'." -f $entry.Key) `
                -Remediation "Keep repository and rendered bootstrap Secret templates placeholder-only; supply real values from untracked env files, external secret managers, or reviewed cluster bootstrap workflows."
        }
    }

    Add-RegexFinding `
        -Findings $findings `
        -Content $content `
        -Pattern '(?m)^\s*privileged:\s*true\s*$' `
        -Severity "high" `
        -Id "privileged-container" `
        -File $relativePath `
        -Message "A container explicitly enables privileged mode." `
        -Remediation "Remove privileged mode or isolate the workload behind a separately reviewed exception."

    Add-RegexFinding `
        -Findings $findings `
        -Content $content `
        -Pattern '(?m)^\s*allowPrivilegeEscalation:\s*true\s*$' `
        -Severity "high" `
        -Id "privilege-escalation" `
        -File $relativePath `
        -Message "A container explicitly allows privilege escalation." `
        -Remediation "Set allowPrivilegeEscalation to false unless a reviewed component requires it."

    Add-RegexFinding `
        -Findings $findings `
        -Content $content `
        -Pattern '(?m)^\s*host(Network|PID|IPC):\s*true\s*$' `
        -Severity "high" `
        -Id "host-namespace" `
        -File $relativePath `
        -Message "A workload explicitly joins a host namespace." `
        -Remediation "Disable host namespace access or document a narrowly scoped exception."

    Add-RegexFinding `
        -Findings $findings `
        -Content $content `
        -Pattern '(?m)^\s*hostPath:\s*$' `
        -Severity "high" `
        -Id "host-path-volume" `
        -File $relativePath `
        -Message "A manifest declares a hostPath volume." `
        -Remediation "Prefer PersistentVolumeClaims, ConfigMaps, Secrets, or projected volumes for template defaults."

    Add-RegexFinding `
        -Findings $findings `
        -Content $content `
        -Pattern '(?m)^\s*insecureSkipTLSVerify:\s*true\s*$' `
        -Severity "medium" `
        -Id "insecure-tls-skip-verify" `
        -File $relativePath `
        -Message "A Kubernetes APIService skips TLS verification." `
        -Remediation "Use a CA bundle or document the bootstrap-only exception before production use."

    Add-RegexFinding `
        -Findings $findings `
        -Content $content `
        -Pattern '(?m)^\s*image:\s*[^#\s]+:latest\s*$' `
        -Severity "medium" `
        -Id "latest-image-tag" `
        -File $relativePath `
        -Message "A container image uses the mutable latest tag." `
        -Remediation "Pin the image to a reviewable version tag."

    Add-RegexFinding `
        -Findings $findings `
        -Content $content `
        -Pattern '(?m)^\s*type:\s*(LoadBalancer|NodePort)\s*$' `
        -Severity "low" `
        -Id "externally-exposed-service" `
        -File $relativePath `
        -Message "A Service is externally exposed by type." `
        -Remediation "Confirm the exposure is intentional for the selected profile and environment."

    if ($content -match '(?ms)^kind:\s*ClusterRoleBinding\s+.*?roleRef:\s+.*?kind:\s*ClusterRole\s+.*?name:\s*cluster-admin\s*$') {
        Add-Finding `
            -Findings $findings `
            -Severity "high" `
            -Id "cluster-admin-binding" `
            -File $relativePath `
            -Line (Get-FirstMatchLineNumber -Content $content -Pattern '^\s*name:\s*cluster-admin\s*$') `
            -Message "A ClusterRoleBinding grants cluster-admin." `
            -Remediation "Keep sample admin bindings out of default bundles and require explicit operator review before use."
    }

    $isWorkload = $content -match '(?m)^kind:\s*(Deployment|StatefulSet|DaemonSet)\s*$'
    if (-not $isWorkload) {
        continue
    }

    if ($content -notmatch '(?m)^\s{8,}resources:\s*$') {
        Add-Finding `
            -Findings $findings `
            -Severity "medium" `
            -Id "missing-container-resources" `
            -File $relativePath `
            -Message "A workload container does not declare resource requests and limits." `
            -Remediation "Add conservative container resources for predictable scheduling and blast-radius control."
    }

    if ($content -notmatch '(?m)^\s{6,}securityContext:\s*$') {
        Add-Finding `
            -Findings $findings `
            -Severity "medium" `
            -Id "missing-security-context" `
            -File $relativePath `
            -Message "A workload does not declare a pod or container securityContext." `
            -Remediation "Add a securityContext after confirming the public image supports the intended user, filesystem, and capability settings."
    }

    if ($content -notmatch '(?m)^\s{8,}readinessProbe:\s*$') {
        Add-Finding `
            -Findings $findings `
            -Severity "medium" `
            -Id "missing-readiness-probe" `
            -File $relativePath `
            -Message "A workload does not declare a readinessProbe." `
            -Remediation "Add a readinessProbe that matches the service protocol before enabling rollout automation."
    }

    if ($content -notmatch '(?m)^\s{8,}livenessProbe:\s*$') {
        Add-Finding `
            -Findings $findings `
            -Severity "medium" `
            -Id "missing-liveness-probe" `
            -File $relativePath `
            -Message "A workload does not declare a livenessProbe." `
            -Remediation "Add a livenessProbe only after confirming it will not restart slow-starting components prematurely."
    }
}

if (-not $hasNetworkPolicy) {
    Add-Finding `
        -Findings $findings `
        -Severity "low" `
        -Id "missing-network-policy" `
        -File (Get-RelativePathFromRoot -Root $root -Path $primaryScanRoot) `
        -Message "No NetworkPolicy manifests were found in the scanned bundle." `
        -Remediation "Add environment-specific NetworkPolicy defaults or document why the selected cluster enforces network isolation elsewhere."
}

$highFindings = @($findings | Where-Object { $_.Severity -eq "high" })
$mediumFindings = @($findings | Where-Object { $_.Severity -eq "medium" })
$lowFindings = @($findings | Where-Object { $_.Severity -eq "low" })

Write-Host ("Kubernetes security baseline scanned files: {0}" -f $yamlFiles.Count)
Write-Host ("Kubernetes security baseline skipped optional manifests: {0}" -f $skippedOptionalManifests)
Write-Host ("Kubernetes security baseline findings: high={0}, medium={1}, low={2}" -f $highFindings.Count, $mediumFindings.Count, $lowFindings.Count)

if ($findings.Count -gt 0) {
    $findings |
        Sort-Object @{ Expression = {
            switch ($_.Severity) {
                "high" { 0 }
                "medium" { 1 }
                default { 2 }
            }
        } }, File, Id |
        Format-Table -AutoSize Severity, Id, File, Line, Message
}
else {
    Write-Host "Kubernetes security baseline validation completed without findings."
}

if ($FailOnHighFinding -and $highFindings.Count -gt 0) {
    throw "Kubernetes security baseline found high-severity findings."
}

if ($FailOnMediumFinding -and ($highFindings.Count -gt 0 -or $mediumFindings.Count -gt 0)) {
    throw "Kubernetes security baseline found high or medium findings."
}
