param(
    [string]$Path,
    [switch]$FailOnHighFinding,
    [switch]$FailOnMediumFinding
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

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

if (-not $PSBoundParameters.ContainsKey("Path") -or -not $Path) {
    $Path = Join-Path $PSScriptRoot ".."
}

$root = (Resolve-Path -Path $Path).Path
$k8sRootCandidate = Join-Path $root "k8s"
$scanRoot = if (Test-Path -Path $k8sRootCandidate -PathType Container) {
    $k8sRootCandidate
}
else {
    $root
}

$yamlFiles = @(
    Get-ChildItem -Path $scanRoot -Recurse -File |
        Where-Object {
            $_.Extension.ToLowerInvariant() -in @(".yaml", ".yml") -and
            $_.Name -ne "values.yaml"
        } |
        Sort-Object FullName
)

if ($yamlFiles.Count -eq 0) {
    throw "No Kubernetes YAML files were found under $scanRoot."
}

$findings = New-Object System.Collections.Generic.List[object]
$hasNetworkPolicy = $false

foreach ($file in $yamlFiles) {
    $content = Get-Content -Path $file.FullName -Raw
    $relativePath = Get-RelativePathFromRoot -Root $root -Path $file.FullName

    if ($content -match '(?m)^kind:\s*NetworkPolicy\s*$') {
        $hasNetworkPolicy = $true
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
        -File (Get-RelativePathFromRoot -Root $root -Path $scanRoot) `
        -Message "No NetworkPolicy manifests were found in the scanned bundle." `
        -Remediation "Add environment-specific NetworkPolicy defaults or document why the selected cluster enforces network isolation elsewhere."
}

$highFindings = @($findings | Where-Object { $_.Severity -eq "high" })
$mediumFindings = @($findings | Where-Object { $_.Severity -eq "medium" })
$lowFindings = @($findings | Where-Object { $_.Severity -eq "low" })

Write-Host ("Kubernetes security baseline scanned files: {0}" -f $yamlFiles.Count)
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
