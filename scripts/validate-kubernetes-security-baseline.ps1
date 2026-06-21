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

function Get-YamlDocuments {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Content
    )

    $documents = New-Object System.Collections.Generic.List[object]
    $lines = [regex]::Split($Content, "\r?\n")
    $documentLines = New-Object System.Collections.Generic.List[string]
    $startLine = 1

    for ($index = 0; $index -lt $lines.Count; $index++) {
        $line = $lines[$index]
        if ($line -match '^\s*---\s*(?:#.*)?$') {
            if (@($documentLines.ToArray() | Where-Object { $_.Trim() }).Count -gt 0) {
                $documents.Add([PSCustomObject]@{
                    StartLine = $startLine
                    Lines = @($documentLines.ToArray())
                    Content = ($documentLines.ToArray() -join "`n")
                }) | Out-Null
            }

            $documentLines.Clear()
            $startLine = $index + 2
            continue
        }

        $documentLines.Add($line) | Out-Null
    }

    if (@($documentLines.ToArray() | Where-Object { $_.Trim() }).Count -gt 0) {
        $documents.Add([PSCustomObject]@{
            StartLine = $startLine
            Lines = @($documentLines.ToArray())
            Content = ($documentLines.ToArray() -join "`n")
        }) | Out-Null
    }

    return $documents.ToArray()
}

function Test-YamlWildcardScalar {
    param(
        [AllowNull()]
        [string]$Value
    )

    if ($null -eq $Value) {
        return $false
    }

    $normalizedValue = ($Value -replace '\s+#.*$', '').Trim()
    if (-not $normalizedValue) {
        return $false
    }

    if ($normalizedValue -match '^\[(.*)\]$') {
        foreach ($item in @($Matches[1] -split ",")) {
            if ((Remove-YamlScalarQuotes -Value $item) -eq "*") {
                return $true
            }
        }

        return $false
    }

    return ((Remove-YamlScalarQuotes -Value $normalizedValue) -eq "*")
}

function Get-FirstYamlSectionWildcardLineNumber {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string[]]$Lines,

        [Parameter(Mandatory = $true)]
        [int]$StartLine,

        [Parameter(Mandatory = $true)]
        [string]$SectionName
    )

    $sectionPattern = '^\s*(?:-\s*)?' + [regex]::Escape($SectionName) + ':\s*(.*)$'
    $sectionIndent = -1

    for ($index = 0; $index -lt $Lines.Count; $index++) {
        $line = $Lines[$index]
        if ($line -match $sectionPattern) {
            if (Test-YamlWildcardScalar -Value $Matches[1]) {
                return ($StartLine + $index)
            }

            $sectionIndent = Get-IndentLength -Line $line
            continue
        }

        if ($sectionIndent -lt 0) {
            continue
        }

        if (-not $line.Trim()) {
            continue
        }

        $indent = Get-IndentLength -Line $line
        if ($indent -lt $sectionIndent) {
            $sectionIndent = -1
            continue
        }

        if ($line -match '^\s*-\s*(.+)$' -and (Test-YamlWildcardScalar -Value $Matches[1])) {
            return ($StartLine + $index)
        }

        if ($indent -eq $sectionIndent) {
            $sectionIndent = -1
            continue
        }
    }

    return 0
}

function Add-RbacWildcardFindings {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[object]]$Findings,

        [Parameter(Mandatory = $true)]
        [string]$Content,

        [Parameter(Mandatory = $true)]
        [string]$File
    )

    $checks = @(
        @{
            Section = "verbs"
            Severity = "high"
            Id = "wildcard-rbac-verbs"
            Message = "A Role or ClusterRole rule grants wildcard verbs."
            Remediation = "Replace wildcard verbs with the minimum required operations such as get, list, watch, create, update, patch, or delete."
        },
        @{
            Section = "resources"
            Severity = "high"
            Id = "wildcard-rbac-resources"
            Message = "A Role or ClusterRole rule grants access to wildcard resources."
            Remediation = "Replace wildcard resources with the narrow resource names required by the component."
        },
        @{
            Section = "apiGroups"
            Severity = "medium"
            Id = "wildcard-rbac-api-groups"
            Message = "A Role or ClusterRole rule applies to wildcard API groups."
            Remediation = "List the specific API groups required by the component instead of using a wildcard."
        }
    )

    foreach ($document in @(Get-YamlDocuments -Content $Content)) {
        if ([string]$document.Content -notmatch '(?m)^kind:\s*(ClusterRole|Role)\s*$') {
            continue
        }

        foreach ($check in $checks) {
            $line = Get-FirstYamlSectionWildcardLineNumber `
                -Lines @($document.Lines) `
                -StartLine ([int]$document.StartLine) `
                -SectionName ([string]$check.Section)

            if ($line -le 0) {
                continue
            }

            Add-Finding `
                -Findings $Findings `
                -Severity ([string]$check.Severity) `
                -Id ([string]$check.Id) `
                -File $File `
                -Line $line `
                -Message ([string]$check.Message) `
                -Remediation ([string]$check.Remediation)
        }
    }
}

function Add-SecretCommandArgumentFindings {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[object]]$Findings,

        [Parameter(Mandatory = $true)]
        [string]$Content,

        [Parameter(Mandatory = $true)]
        [string]$File
    )

    $checks = @(
        @{
            Pattern = '(?m)^\s*-\s*.*--requirepass\s+("[^"]+"|''[^'']+''|\S+)'
            Id = "secret-command-argument"
        },
        @{
            Pattern = '(?m)^\s*-\s*.*\bredis-cli\s+.*\s-a\s+("[^"]+"|''[^'']+''|\S+)'
            Id = "secret-command-argument"
        }
    )

    foreach ($check in $checks) {
        Add-RegexFinding `
            -Findings $Findings `
            -Content $Content `
            -Pattern ([string]$check.Pattern) `
            -Severity "medium" `
            -Id ([string]$check.Id) `
            -File $File `
            -Message "A workload command passes a secret-bearing value through process arguments." `
            -Remediation "Move secret material into a mounted config or ACL file, or use a client-supported environment variable instead of secret-bearing command arguments."
    }
}

function Get-YamlListItemBlocks {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string[]]$Lines,

        [Parameter(Mandatory = $true)]
        [int]$StartLine,

        [Parameter(Mandatory = $true)]
        [string]$SectionName
    )

    $blocks = New-Object System.Collections.Generic.List[object]
    $sectionPattern = '^\s*' + [regex]::Escape($SectionName) + ':\s*(?:#.*)?$'
    $inSection = $false
    $sectionIndent = -1
    $itemIndent = -1
    $currentLines = New-Object System.Collections.Generic.List[string]
    $currentStartLine = 0

    for ($index = 0; $index -lt $Lines.Count; $index++) {
        $line = $Lines[$index]

        if (-not $inSection) {
            if ($line -match $sectionPattern) {
                $inSection = $true
                $sectionIndent = Get-IndentLength -Line $line
                $itemIndent = -1
            }

            continue
        }

        if (-not $line.Trim()) {
            if ($currentLines.Count -gt 0) {
                $currentLines.Add($line) | Out-Null
            }

            continue
        }

        $indent = Get-IndentLength -Line $line

        if ($itemIndent -lt 0) {
            if ($indent -lt $sectionIndent -or ($indent -eq $sectionIndent -and $line -notmatch '^\s*-\s+')) {
                $inSection = $false
                $sectionIndent = -1
                continue
            }

            if ($line -match '^\s*-\s+') {
                $itemIndent = $indent
                $currentStartLine = $StartLine + $index
                $currentLines.Clear()
                $currentLines.Add($line) | Out-Null
            }

            continue
        }

        if ($indent -lt $itemIndent -or ($indent -eq $itemIndent -and $line -notmatch '^\s*-\s+')) {
            if ($currentLines.Count -gt 0) {
                $blocks.Add([PSCustomObject]@{
                    StartLine = $currentStartLine
                    ItemIndent = $itemIndent
                    Lines = @($currentLines.ToArray())
                }) | Out-Null
                $currentLines.Clear()
            }

            $inSection = $false
            $sectionIndent = -1
            $itemIndent = -1
            continue
        }

        if ($indent -eq $itemIndent -and $line -match '^\s*-\s+') {
            if ($currentLines.Count -gt 0) {
                $blocks.Add([PSCustomObject]@{
                    StartLine = $currentStartLine
                    ItemIndent = $itemIndent
                    Lines = @($currentLines.ToArray())
                }) | Out-Null
            }

            $currentStartLine = $StartLine + $index
            $currentLines.Clear()
            $currentLines.Add($line) | Out-Null
            continue
        }

        if ($currentLines.Count -gt 0) {
            $currentLines.Add($line) | Out-Null
        }
    }

    if ($currentLines.Count -gt 0) {
        $blocks.Add([PSCustomObject]@{
            StartLine = $currentStartLine
            ItemIndent = $itemIndent
            Lines = @($currentLines.ToArray())
        }) | Out-Null
    }

    return $blocks.ToArray()
}

function Get-YamlListItemPropertyLineNumber {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Block,

        [Parameter(Mandatory = $true)]
        [string]$PropertyName
    )

    $propertyPattern = '^\s*' + [regex]::Escape($PropertyName) + ':\s*(?:.*)$'
    $listItemPropertyPattern = '^\s*-\s*' + [regex]::Escape($PropertyName) + ':\s*(?:.*)$'
    $topLevelIndent = [int]$Block.ItemIndent + 2
    $lines = @($Block.Lines)

    for ($index = 0; $index -lt $lines.Count; $index++) {
        $line = $lines[$index]
        if ($index -eq 0 -and $line -match $listItemPropertyPattern) {
            return ([int]$Block.StartLine + $index)
        }

        if ((Get-IndentLength -Line $line) -eq $topLevelIndent -and $line -match $propertyPattern) {
            return ([int]$Block.StartLine + $index)
        }
    }

    return 0
}

function Get-YamlListItemDisplayName {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Block
    )

    $lines = @($Block.Lines)
    $topLevelIndent = [int]$Block.ItemIndent + 2
    if ($lines.Count -gt 0 -and $lines[0] -match '^\s*-\s*name:\s*(.+)$') {
        return (Remove-YamlScalarQuotes -Value $Matches[1])
    }

    foreach ($line in $lines) {
        if ((Get-IndentLength -Line $line) -eq $topLevelIndent -and $line -match '^\s*name:\s*(.+)$') {
            return (Remove-YamlScalarQuotes -Value $Matches[1])
        }
    }

    return ""
}

function Add-MissingContainerPropertyFinding {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[object]]$Findings,

        [Parameter(Mandatory = $true)]
        [object]$Container,

        [Parameter(Mandatory = $true)]
        [string]$PropertyName,

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

    if ((Get-YamlListItemPropertyLineNumber -Block $Container -PropertyName $PropertyName) -gt 0) {
        return
    }

    $containerName = Get-YamlListItemDisplayName -Block $Container
    $findingMessage = if ($containerName) {
        ("Container '{0}' {1}" -f $containerName, $Message)
    }
    else {
        ("A workload container {0}" -f $Message)
    }

    Add-Finding `
        -Findings $Findings `
        -Severity $Severity `
        -Id $Id `
        -File $File `
        -Line ([int]$Container.StartLine) `
        -Message $findingMessage `
        -Remediation $Remediation
}

function Add-WorkloadContainerPostureFindings {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[object]]$Findings,

        [Parameter(Mandatory = $true)]
        [object]$Document,

        [Parameter(Mandatory = $true)]
        [string]$File
    )

    foreach ($container in @(Get-YamlListItemBlocks -Lines @($Document.Lines) -StartLine ([int]$Document.StartLine) -SectionName "containers")) {
        Add-MissingContainerPropertyFinding `
            -Findings $Findings `
            -Container $container `
            -PropertyName "resources" `
            -Severity "medium" `
            -Id "missing-container-resources" `
            -File $File `
            -Message "does not declare resource requests and limits." `
            -Remediation "Add conservative container resources for predictable scheduling and blast-radius control."

        Add-MissingContainerPropertyFinding `
            -Findings $Findings `
            -Container $container `
            -PropertyName "readinessProbe" `
            -Severity "medium" `
            -Id "missing-readiness-probe" `
            -File $File `
            -Message "does not declare a readinessProbe." `
            -Remediation "Add a readinessProbe that matches the service protocol before enabling rollout automation."

        Add-MissingContainerPropertyFinding `
            -Findings $Findings `
            -Container $container `
            -PropertyName "livenessProbe" `
            -Severity "medium" `
            -Id "missing-liveness-probe" `
            -File $File `
            -Message "does not declare a livenessProbe." `
            -Remediation "Add a livenessProbe only after confirming it will not restart slow-starting components prematurely."
    }
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
        -Pattern '(?m)^\s{6,}automountServiceAccountToken:\s*true\s*$' `
        -Severity "medium" `
        -Id "service-account-token-automount" `
        -File $relativePath `
        -Message "A workload explicitly automounts a service account token." `
        -Remediation "Set automountServiceAccountToken to false unless the workload has a reviewed Kubernetes API access requirement."

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

    Add-RbacWildcardFindings `
        -Findings $findings `
        -Content $content `
        -File $relativePath

    Add-SecretCommandArgumentFindings `
        -Findings $findings `
        -Content $content `
        -File $relativePath

    foreach ($document in @(Get-YamlDocuments -Content $content)) {
        $documentContent = [string]$document.Content
        if ($documentContent -notmatch '(?m)^kind:\s*(Deployment|StatefulSet|DaemonSet)\s*$') {
            continue
        }

        Add-WorkloadContainerPostureFindings `
            -Findings $findings `
            -Document $document `
            -File $relativePath

        if ($documentContent -notmatch '(?m)^\s{6,}securityContext:\s*$') {
            Add-Finding `
                -Findings $findings `
                -Severity "medium" `
                -Id "missing-security-context" `
                -File $relativePath `
                -Line ([int]$document.StartLine) `
                -Message "A workload does not declare a pod or container securityContext." `
                -Remediation "Add a securityContext after confirming the public image supports the intended user, filesystem, and capability settings."
        }

        if ($documentContent -notmatch '(?m)^\s{6,}automountServiceAccountToken:\s*true\s*$' -and
            $documentContent -notmatch '(?m)^\s{6,}serviceAccountName:\s*\S+\s*$' -and
            $documentContent -notmatch '(?m)^\s{6,}automountServiceAccountToken:\s*false\s*$') {
            Add-Finding `
                -Findings $findings `
                -Severity "medium" `
                -Id "missing-service-account-token-disable" `
                -File $relativePath `
                -Line ([int]$document.StartLine) `
                -Message "A workload that uses the default service account does not disable service account token automounting." `
                -Remediation "Set automountServiceAccountToken to false for workloads that do not need Kubernetes API access."
        }
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
