# Troubleshooting

This guide focuses on validation and render issues that can appear before a bundle is applied to a cluster.

## Validation Command Fails Immediately

If the shell reports that `pwsh` is not found, install PowerShell 7 or run the scripts from Windows PowerShell on Windows. The phase gate and maintainer validation command use:

```powershell
pwsh -NoProfile -File scripts/validate-template.ps1
```

Automation shells that do not load an interactive profile may need `$HOME/.local/bin`
on `PATH` before invoking `pwsh`. The project phase gate prefixes that user-local
tool directory so a local PowerShell install is still discoverable without
hardcoding a workstation-specific path.

After PowerShell is available, rerun the same command from the repository root.

## Template Validation Warns About Missing Kubernetes Tools

`validate-template.ps1` is the public-default template gate. It can finish without `kubeconform`, `kubectl`, or `helm` when those checks are not running in strict mode.

Expected non-strict warnings include:

- `Neither kubeconform nor kubectl is installed. Skipping rendered manifest validation.`
- `helm is not installed. Skipping Helm values validation.`

These warnings mean the template rendered far enough to reach optional validator paths. Install `kubeconform` for offline Kubernetes schema validation, `kubectl` for client dry-run validation and cluster helper scripts, and `helm` for Helm-managed components.

## Repository Validation Fails At Workstation Validation

`invoke-repository-validation.ps1` runs `validate-workstation.ps1 -Strict` unless `-SkipWorkstationValidation` is passed. The default strict workstation profile requires `kubectl` and `helm`.

Use this command to see the missing tools directly:

```powershell
.\scripts\validate-workstation.ps1 -Strict
```

If you are only checking repository structure and public-default rendering on a workstation that is not prepared for cluster work, run:

```powershell
.\scripts\validate-template.ps1
.\scripts\show-validation-readiness.ps1 -Profile web-platform -Applications nginx-web,httpbin,whoami -DataServices redis -Format markdown
```

Use `-SkipWorkstationValidation` only when the narrower repository-only scope is intentional and recorded in your validation notes.

## Automation Still Reports Kubernetes Validation Failed

The `schema-security-baseline` to `template-maintenance` phase transition uses
the template gate, not the broader repository workflow:

```bash
env PATH="$HOME/.local/bin:$PATH" pwsh -NoProfile -File scripts/validate-template.ps1
```

If automation or a progress dashboard still reports `kubernetes validation
failed`, rerun that exact command from the repository root and compare it with
the broader repository command:

```powershell
.\scripts\invoke-repository-validation.ps1 -EnvironmentPreset dev
```

A passing template gate means public-default render validation, rendered schema
validator wiring, and Kubernetes security baseline checks are ready for
`template-maintenance`. A failing repository workflow may still be a workstation
readiness issue, because strict repository validation checks for tools such as
`kubectl` and `helm`. Use
`.\scripts\show-validation-readiness.ps1 -Profile web-platform -Applications nginx-web,httpbin,whoami -DataServices redis -Format markdown`
to separate missing local tools from template render failures before changing
manifests.

## Edited Values Are Not Reflected

Environment presets use `ValidationValuesFile` for repository validation when it is defined. The bundled presets point to `config/platform-values.env.example` so public validation does not depend on site-specific values.

After generating and editing an environment file, pass it explicitly:

```powershell
.\scripts\invoke-repository-validation.ps1 `
  -EnvironmentPreset dev `
  -ValuesFile config\platform-values.dev.env
```

## Rendered Manifest Schema Validation Is Skipped Or Fails

Rendered manifest schema validation is handled by `validate-rendered-bundle.ps1`, usually through `validate-platform-assets.ps1`.

The validator order is:

1. `kubeconform` when installed.
2. `kubectl apply --dry-run=client --validate=true` when `kubeconform` is unavailable.
3. A non-strict warning when neither tool is installed.
4. A strict failure when neither tool is installed and strict validation is requested.

Install `kubeconform` when you want repository-only schema validation without a live cluster dependency. Use `kubectl` when you also need cluster-side workflows.

## CRD-backed Resources Are Skipped

Public-default validation skips CRD-backed resources unless `-ValidateCrdBackedResources` is passed. Leave this default in generic repository validation so the template does not require cluster-installed CRDs.

Enable CRD-backed validation only in an environment where the required CRDs are available to the selected validator.

## Security Baseline Findings Appear

`validate-platform-assets.ps1` runs `validate-kubernetes-security-baseline.ps1` after rendering. By default, findings are reported for review and do not fail the command.

Use `-FailOnHighSecurityBaselineFinding` when high-severity baseline findings should block validation. Review the rendered file path before changing the source template, because some add-ons need an explicit operational exception instead of a generic default change.

## Generated Bundle Validation Order

After `invoke-bundle-delivery.ps1`, use the generated bundle helpers before applying manifests:

```powershell
.\out\delivery\dev\validate-bundle.ps1
.\out\delivery\dev\cluster-bootstrap\check-secret-templates.ps1
.\out\delivery\dev\cluster-bootstrap\status-secrets.ps1
.\out\delivery\dev\apply-manifests.ps1
.\out\delivery\dev\install-helm-components.ps1 -PrepareRepos
.\out\delivery\dev\status-bundle.ps1
```

Edit generated bootstrap secret templates before applying them. Do not commit rendered `out/` bundles, kubeconfigs, or real secret manifests.

## Bootstrap Secret Readiness On Non-Windows Hosts

`validate-platform-assets.ps1 -RequireBootstrapSecretsReady` expects the generated bootstrap check helper to be runnable. If a non-Windows workstation lacks the `powershell` executable used by that generated check path, run the generated `cluster-bootstrap\check-secret-templates.ps1` directly with the PowerShell host available on the machine, then record that validation separately.
