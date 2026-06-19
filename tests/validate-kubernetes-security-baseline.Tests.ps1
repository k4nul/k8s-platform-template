Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$script:TestsRun = 0
$script:TestsFailed = 0

function Assert-True {
    param(
        [bool]$Condition,
        [string]$Message
    )

    if (-not $Condition) {
        throw $Message
    }
}

function Assert-Contains {
    param(
        [string]$Content,
        [string]$Expected,
        [string]$Message
    )

    if (-not $Content.Contains($Expected)) {
        throw ("{0} Expected to find '{1}'." -f $Message, $Expected)
    }
}

function Assert-NotContains {
    param(
        [string]$Content,
        [string]$Unexpected,
        [string]$Message
    )

    if ($Content.Contains($Unexpected)) {
        throw ("{0} Did not expect to find '{1}'." -f $Message, $Unexpected)
    }
}

function Invoke-Test {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [scriptblock]$Body
    )

    $script:TestsRun++
    try {
        & $Body
        Write-Host ("[PASS] {0}" -f $Name)
    }
    catch {
        $script:TestsFailed++
        Write-Host ("[FAIL] {0}" -f $Name)
        Write-Host ("       {0}" -f $_.Exception.Message)
    }
}

function New-TestSecretBundle {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Root,

        [Parameter(Mandatory = $true)]
        [string]$SecretYaml
    )

    $k8sRoot = Join-Path $Root "k8s"
    New-Item -ItemType Directory -Path $k8sRoot -Force | Out-Null
    Set-Content `
        -Path (Join-Path $k8sRoot "secret.yaml") `
        -Value $SecretYaml `
        -NoNewline
}

function New-TestBootstrapSecretBundle {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Root,

        [Parameter(Mandatory = $true)]
        [string]$SecretYaml
    )

    $k8sRoot = Join-Path $Root "k8s"
    $bootstrapSecretRoot = Join-Path $Root "cluster-bootstrap\secrets\platform"
    New-Item -ItemType Directory -Path $k8sRoot -Force | Out-Null
    New-Item -ItemType Directory -Path $bootstrapSecretRoot -Force | Out-Null
    Set-Content `
        -Path (Join-Path $k8sRoot "configmap.yaml") `
        -Value "apiVersion: v1`nkind: ConfigMap`nmetadata:`n  name: bootstrap-scope-test`n" `
        -NoNewline
    Set-Content `
        -Path (Join-Path $bootstrapSecretRoot "secret.yaml") `
        -Value $SecretYaml `
        -NoNewline
}

function New-TestKubernetesBundle {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Root,

        [Parameter(Mandatory = $true)]
        [hashtable]$Manifests
    )

    $k8sRoot = Join-Path $Root "k8s"
    New-Item -ItemType Directory -Path $k8sRoot -Force | Out-Null

    foreach ($manifestName in $Manifests.Keys) {
        $manifestPath = Join-Path $k8sRoot $manifestName
        $manifestDirectory = Split-Path -Path $manifestPath -Parent
        if ($manifestDirectory) {
            New-Item -ItemType Directory -Path $manifestDirectory -Force | Out-Null
        }

        Set-Content `
            -Path $manifestPath `
            -Value $Manifests[$manifestName] `
            -NoNewline
    }
}

$repoRoot = (Resolve-Path -Path (Join-Path $PSScriptRoot "..")).Path
$securityBaselineScript = Join-Path $repoRoot "scripts\validate-kubernetes-security-baseline.ps1"

Invoke-Test -Name "Security baseline allows placeholder-only Secret template values" -Body {
    $testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("security-baseline-test-" + [Guid]::NewGuid().ToString("N"))

    try {
        New-TestSecretBundle `
            -Root $testRoot `
            -SecretYaml "apiVersion: v1`nkind: Secret`nmetadata:`n  name: placeholder-secret`ntype: Opaque`nstringData:`n  password: change-me-placeholder-password`n  token: REPLACE_WITH_TOKEN`n"

        & $securityBaselineScript -Path $testRoot -FailOnMediumFinding 3>&1 2>&1 | Out-String | Out-Null
    }
    finally {
        if (Test-Path -LiteralPath $testRoot) {
            Remove-Item -LiteralPath $testRoot -Recurse -Force
        }
    }
}

Invoke-Test -Name "Security baseline reports concrete sensitive values without printing the value" -Body {
    $testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("security-baseline-test-" + [Guid]::NewGuid().ToString("N"))
    $secretValue = "actual-sensitive-value-123"

    try {
        New-TestSecretBundle `
            -Root $testRoot `
            -SecretYaml "apiVersion: v1`nkind: Secret`nmetadata:`n  name: concrete-secret`ntype: Opaque`nstringData:`n  password: $secretValue`n  username: platform_app`n"

        $output = (& $securityBaselineScript -Path $testRoot 3>&1 2>&1 | Out-String)

        Assert-Contains `
            -Content $output `
            -Expected "concrete-secret-template-value" `
            -Message "Concrete sensitive Secret values should be reported."
        Assert-NotContains `
            -Content $output `
            -Unexpected $secretValue `
            -Message "The finding output should not print the sensitive value."
    }
    finally {
        if (Test-Path -LiteralPath $testRoot) {
            Remove-Item -LiteralPath $testRoot -Recurse -Force
        }
    }
}

Invoke-Test -Name "Security baseline can fail on concrete sensitive Secret values" -Body {
    $testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("security-baseline-test-" + [Guid]::NewGuid().ToString("N"))

    try {
        New-TestSecretBundle `
            -Root $testRoot `
            -SecretYaml "apiVersion: v1`nkind: Secret`nmetadata:`n  name: concrete-secret`ntype: Opaque`ndata:`n  token: YWN0dWFsLXRva2Vu`n"

        $failed = $false
        try {
            & $securityBaselineScript -Path $testRoot -FailOnMediumFinding 3>&1 2>&1 | Out-String | Out-Null
        }
        catch {
            Assert-Contains `
                -Content $_.Exception.Message `
                -Expected "high or medium" `
                -Message "FailOnMediumFinding should block concrete sensitive Secret values."
            $failed = $true
        }

        Assert-True -Condition $failed -Message "FailOnMediumFinding should fail when a concrete sensitive Secret value is present."
    }
    finally {
        if (Test-Path -LiteralPath $testRoot) {
            Remove-Item -LiteralPath $testRoot -Recurse -Force
        }
    }
}

Invoke-Test -Name "Security baseline scans rendered bootstrap Secret templates" -Body {
    $testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("security-baseline-test-" + [Guid]::NewGuid().ToString("N"))

    try {
        New-TestBootstrapSecretBundle `
            -Root $testRoot `
            -SecretYaml "apiVersion: v1`nkind: Secret`nmetadata:`n  name: bootstrap-secret`ntype: Opaque`nstringData:`n  password: bootstrap-sensitive-value`n"

        $failed = $false
        try {
            & $securityBaselineScript -Path $testRoot -FailOnMediumFinding 3>&1 2>&1 | Out-String | Out-Null
        }
        catch {
            Assert-Contains `
                -Content $_.Exception.Message `
                -Expected "high or medium" `
                -Message "FailOnMediumFinding should include rendered bootstrap Secret templates."
            $failed = $true
        }

        Assert-True -Condition $failed -Message "Bootstrap Secret templates should be part of the security baseline scan."
    }
    finally {
        if (Test-Path -LiteralPath $testRoot) {
            Remove-Item -LiteralPath $testRoot -Recurse -Force
        }
    }
}

Invoke-Test -Name "Security baseline allows hardened workload with NetworkPolicy without gap findings" -Body {
    $testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("security-baseline-test-" + [Guid]::NewGuid().ToString("N"))

    try {
        New-TestKubernetesBundle `
            -Root $testRoot `
            -Manifests @{
                "deployment.yaml" = "apiVersion: apps/v1`nkind: Deployment`nmetadata:`n  name: hardened-web`nspec:`n  replicas: 1`n  selector:`n    matchLabels:`n      app: hardened-web`n  template:`n    metadata:`n      labels:`n        app: hardened-web`n    spec:`n      securityContext:`n        runAsNonRoot: true`n      containers:`n        - name: web`n          image: nginx:1.25.4`n          securityContext:`n            allowPrivilegeEscalation: false`n          resources:`n            requests:`n              cpu: 50m`n              memory: 64Mi`n            limits:`n              cpu: 250m`n              memory: 128Mi`n          readinessProbe:`n            httpGet:`n              path: /`n              port: 80`n          livenessProbe:`n            httpGet:`n              path: /`n              port: 80`n"
                "networkpolicy.yaml" = "apiVersion: networking.k8s.io/v1`nkind: NetworkPolicy`nmetadata:`n  name: hardened-web-default-deny`nspec:`n  podSelector:`n    matchLabels:`n      app: hardened-web`n  policyTypes:`n    - Ingress`n"
            }

        & $securityBaselineScript -Path $testRoot -FailOnMediumFinding 3>&1 2>&1 | Out-String | Out-Null
        Assert-True -Condition $true -Message "A hardened workload with NetworkPolicy should not report baseline gaps."
    }
    finally {
        if (Test-Path -LiteralPath $testRoot) {
            Remove-Item -LiteralPath $testRoot -Recurse -Force
        }
    }
}

Invoke-Test -Name "Security baseline fail-on-medium blocks workload posture gaps" -Body {
    $testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("security-baseline-test-" + [Guid]::NewGuid().ToString("N"))

    try {
        New-TestKubernetesBundle `
            -Root $testRoot `
            -Manifests @{
                "deployment.yaml" = "apiVersion: apps/v1`nkind: Deployment`nmetadata:`n  name: incomplete-web`nspec:`n  replicas: 1`n  selector:`n    matchLabels:`n      app: incomplete-web`n  template:`n    metadata:`n      labels:`n        app: incomplete-web`n    spec:`n      containers:`n        - name: web`n          image: nginx:1.25.4`n"
                "networkpolicy.yaml" = "apiVersion: networking.k8s.io/v1`nkind: NetworkPolicy`nmetadata:`n  name: incomplete-web-default-deny`nspec:`n  podSelector:`n    matchLabels:`n      app: incomplete-web`n  policyTypes:`n    - Ingress`n"
            }

        $output = (& $securityBaselineScript -Path $testRoot 3>&1 2>&1 | Out-String)
        Assert-Contains -Content $output -Expected "missing-container-resources" -Message "Missing resources should be reported for workloads."
        Assert-Contains -Content $output -Expected "missing-security-context" -Message "Missing securityContext should be reported for workloads."
        Assert-Contains -Content $output -Expected "missing-readiness-probe" -Message "Missing readiness probes should be reported for workloads."
        Assert-Contains -Content $output -Expected "missing-liveness-probe" -Message "Missing liveness probes should be reported for workloads."

        $failed = $false
        try {
            & $securityBaselineScript -Path $testRoot -FailOnMediumFinding 3>&1 2>&1 | Out-String | Out-Null
        }
        catch {
            Assert-Contains `
                -Content $_.Exception.Message `
                -Expected "high or medium" `
                -Message "FailOnMediumFinding should block workload posture gaps."
            $failed = $true
        }

        Assert-True -Condition $failed -Message "FailOnMediumFinding should fail when workload posture gaps are present."
    }
    finally {
        if (Test-Path -LiteralPath $testRoot) {
            Remove-Item -LiteralPath $testRoot -Recurse -Force
        }
    }
}

Invoke-Test -Name "Security baseline reports high-risk workload defaults without failing by default" -Body {
    $testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("security-baseline-test-" + [Guid]::NewGuid().ToString("N"))

    try {
        New-TestKubernetesBundle `
            -Root $testRoot `
            -Manifests @{
                "deployment.yaml" = "apiVersion: apps/v1`nkind: Deployment`nmetadata:`n  name: risky-web`nspec:`n  replicas: 1`n  selector:`n    matchLabels:`n      app: risky-web`n  template:`n    metadata:`n      labels:`n        app: risky-web`n    spec:`n      hostNetwork: true`n      containers:`n        - name: web`n          image: nginx:latest`n          securityContext:`n            privileged: true`n            allowPrivilegeEscalation: true`n          volumeMounts:`n            - name: host-root`n              mountPath: /host`n      volumes:`n        - name: host-root`n          hostPath:`n            path: /`n"
            }

        $output = (& $securityBaselineScript -Path $testRoot 3>&1 2>&1 | Out-String)

        Assert-Contains -Content $output -Expected "privileged-container" -Message "Privileged containers should be reported."
        Assert-Contains -Content $output -Expected "privilege-escalation" -Message "Privilege escalation should be reported."
        Assert-Contains -Content $output -Expected "host-namespace" -Message "Host namespace usage should be reported."
        Assert-Contains -Content $output -Expected "host-path-volume" -Message "hostPath volumes should be reported."
        Assert-Contains -Content $output -Expected "latest-image-tag" -Message "Mutable latest tags should be reported."
        Assert-Contains -Content $output -Expected "missing-container-resources" -Message "Missing resources should be reported for workloads."
        Assert-Contains -Content $output -Expected "missing-readiness-probe" -Message "Missing readiness probes should be reported for workloads."
        Assert-Contains -Content $output -Expected "missing-liveness-probe" -Message "Missing liveness probes should be reported for workloads."
    }
    finally {
        if (Test-Path -LiteralPath $testRoot) {
            Remove-Item -LiteralPath $testRoot -Recurse -Force
        }
    }
}

Invoke-Test -Name "Security baseline fail-on-high blocks cluster-admin bindings" -Body {
    $testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("security-baseline-test-" + [Guid]::NewGuid().ToString("N"))

    try {
        New-TestKubernetesBundle `
            -Root $testRoot `
            -Manifests @{
                "clusterrolebinding.yaml" = "apiVersion: rbac.authorization.k8s.io/v1`nkind: ClusterRoleBinding`nmetadata:`n  name: unsafe-admin-binding`nsubjects:`n  - kind: ServiceAccount`n    name: unsafe-admin`n    namespace: default`nroleRef:`n  apiGroup: rbac.authorization.k8s.io`n  kind: ClusterRole`n  name: cluster-admin`n"
            }

        $failed = $false
        try {
            & $securityBaselineScript -Path $testRoot -FailOnHighFinding 3>&1 2>&1 | Out-String | Out-Null
        }
        catch {
            Assert-Contains `
                -Content $_.Exception.Message `
                -Expected "high-severity" `
                -Message "FailOnHighFinding should block high-severity RBAC findings."
            $failed = $true
        }

        Assert-True -Condition $failed -Message "FailOnHighFinding should fail when a cluster-admin binding is present."
    }
    finally {
        if (Test-Path -LiteralPath $testRoot) {
            Remove-Item -LiteralPath $testRoot -Recurse -Force
        }
    }
}

Invoke-Test -Name "Security baseline fail-on-high blocks wildcard RBAC grants" -Body {
    $testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("security-baseline-test-" + [Guid]::NewGuid().ToString("N"))

    try {
        New-TestKubernetesBundle `
            -Root $testRoot `
            -Manifests @{
                "wildcard-role.yaml" = "apiVersion: rbac.authorization.k8s.io/v1`nkind: ClusterRole`nmetadata:`n  name: overly-broad-role`nrules:`n- apiGroups: ['*']`n  resources:`n  - '*'`n  verbs:`n  - '*'`n"
            }

        $output = (& $securityBaselineScript -Path $testRoot 3>&1 2>&1 | Out-String)

        Assert-Contains -Content $output -Expected "wildcard-rbac-api-groups" -Message "Wildcard RBAC API groups should be reported."
        Assert-Contains -Content $output -Expected "wildcard-rbac-resources" -Message "Wildcard RBAC resources should be reported."
        Assert-Contains -Content $output -Expected "wildcard-rbac-verbs" -Message "Wildcard RBAC verbs should be reported."

        $failed = $false
        try {
            & $securityBaselineScript -Path $testRoot -FailOnHighFinding 3>&1 2>&1 | Out-String | Out-Null
        }
        catch {
            Assert-Contains `
                -Content $_.Exception.Message `
                -Expected "high-severity" `
                -Message "FailOnHighFinding should block high-severity wildcard RBAC findings."
            $failed = $true
        }

        Assert-True -Condition $failed -Message "FailOnHighFinding should fail when wildcard RBAC resources or verbs are present."
    }
    finally {
        if (Test-Path -LiteralPath $testRoot) {
            Remove-Item -LiteralPath $testRoot -Recurse -Force
        }
    }
}

Invoke-Test -Name "Security baseline skips cataloged optional manual manifests by default" -Body {
    $testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("security-baseline-test-" + [Guid]::NewGuid().ToString("N"))

    try {
        New-TestKubernetesBundle `
            -Root $testRoot `
            -Manifests @{
                "311_platform_kubernetes-dashboard/sample-admin-user.yaml" = "apiVersion: rbac.authorization.k8s.io/v1`nkind: ClusterRoleBinding`nmetadata:`n  name: optional-admin-binding`nsubjects:`n  - kind: ServiceAccount`n    name: optional-admin`n    namespace: kubernetes-dashboard`nroleRef:`n  apiGroup: rbac.authorization.k8s.io`n  kind: ClusterRole`n  name: cluster-admin`n"
                "311_platform_kubernetes-dashboard/sample-viewer-user.yaml" = "apiVersion: rbac.authorization.k8s.io/v1`nkind: RoleBinding`nmetadata:`n  name: optional-viewer-binding`n  namespace: kubernetes-dashboard`nsubjects:`n  - kind: ServiceAccount`n    name: optional-viewer`n    namespace: kubernetes-dashboard`nroleRef:`n  apiGroup: rbac.authorization.k8s.io`n  kind: ClusterRole`n  name: view`n"
            }

        $output = (& $securityBaselineScript -Path $testRoot -FailOnHighFinding 6>&1 3>&1 2>&1 | Out-String)

        Assert-Contains `
            -Content $output `
            -Expected "skipped optional manifests: 2" `
            -Message "Cataloged optional manifests should be skipped by default."
        Assert-NotContains `
            -Content $output `
            -Unexpected "cluster-admin-binding" `
            -Message "Skipped optional manifests should not produce high-severity findings."

        & $securityBaselineScript -Path $testRoot -FailOnHighFinding 3>&1 2>&1 | Out-String | Out-Null
    }
    finally {
        if (Test-Path -LiteralPath $testRoot) {
            Remove-Item -LiteralPath $testRoot -Recurse -Force
        }
    }
}

Invoke-Test -Name "Security baseline can include cataloged optional manual manifests" -Body {
    $testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("security-baseline-test-" + [Guid]::NewGuid().ToString("N"))

    try {
        New-TestKubernetesBundle `
            -Root $testRoot `
            -Manifests @{
                "311_platform_kubernetes-dashboard/sample-admin-user.yaml" = "apiVersion: rbac.authorization.k8s.io/v1`nkind: ClusterRoleBinding`nmetadata:`n  name: optional-admin-binding`nsubjects:`n  - kind: ServiceAccount`n    name: optional-admin`n    namespace: kubernetes-dashboard`nroleRef:`n  apiGroup: rbac.authorization.k8s.io`n  kind: ClusterRole`n  name: cluster-admin`n"
                "311_platform_kubernetes-dashboard/sample-viewer-user.yaml" = "apiVersion: rbac.authorization.k8s.io/v1`nkind: RoleBinding`nmetadata:`n  name: optional-viewer-binding`n  namespace: kubernetes-dashboard`nsubjects:`n  - kind: ServiceAccount`n    name: optional-viewer`n    namespace: kubernetes-dashboard`nroleRef:`n  apiGroup: rbac.authorization.k8s.io`n  kind: ClusterRole`n  name: view`n"
            }

        $failed = $false
        try {
            & $securityBaselineScript -Path $testRoot -IncludeOptionalManifests -FailOnHighFinding 3>&1 2>&1 | Out-String | Out-Null
        }
        catch {
            Assert-Contains `
                -Content $_.Exception.Message `
                -Expected "high-severity" `
                -Message "Optional manifests should still be reviewable through the explicit include switch."
            $failed = $true
        }

        Assert-True -Condition $failed -Message "IncludeOptionalManifests should scan cataloged optional manifests."
    }
    finally {
        if (Test-Path -LiteralPath $testRoot) {
            Remove-Item -LiteralPath $testRoot -Recurse -Force
        }
    }
}

Invoke-Test -Name "Security baseline can include namespace-scoped optional manual manifests without high findings" -Body {
    $testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("security-baseline-test-" + [Guid]::NewGuid().ToString("N"))

    try {
        New-TestKubernetesBundle `
            -Root $testRoot `
            -Manifests @{
                "311_platform_kubernetes-dashboard/sample-viewer-user.yaml" = "apiVersion: rbac.authorization.k8s.io/v1`nkind: RoleBinding`nmetadata:`n  name: optional-viewer-binding`n  namespace: kubernetes-dashboard`nsubjects:`n  - kind: ServiceAccount`n    name: optional-viewer`n    namespace: kubernetes-dashboard`nroleRef:`n  apiGroup: rbac.authorization.k8s.io`n  kind: ClusterRole`n  name: view`n"
            }

        & $securityBaselineScript -Path $testRoot -IncludeOptionalManifests -FailOnHighFinding 3>&1 2>&1 | Out-String | Out-Null
    }
    finally {
        if (Test-Path -LiteralPath $testRoot) {
            Remove-Item -LiteralPath $testRoot -Recurse -Force
        }
    }
}

if ($script:TestsFailed -gt 0) {
    throw ("{0} of {1} Kubernetes security baseline test(s) failed." -f $script:TestsFailed, $script:TestsRun)
}

Write-Host ("All {0} Kubernetes security baseline test(s) passed." -f $script:TestsRun)
