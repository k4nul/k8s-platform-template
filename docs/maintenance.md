# Template Maintenance

This guide is for maintainers keeping the public Kubernetes platform template in
the `template-maintenance` phase. Use it when a dashboard, scheduled automation,
or reviewer reports that Kubernetes validation is failing and you need to
separate a template regression from local workstation readiness.

## Maintenance Validation Order

Run the maintenance gate from the repository root:

```bash
env PATH="$HOME/.local/bin:$PATH" pwsh -NoProfile -File scripts/validate-template.ps1
```

This is the validation command recorded in
`docs/instructions/phase-gates.json`. It uses public defaults and temporary
render output, then removes the temporary render directory before exiting.

When the gate passes, it proves the current maintenance baseline:

- required repository docs, catalogs, scripts, and tests exist
- service catalogs, service builds, service config artifacts, service runtime,
  platform selection, and platform values validate against public defaults
- the `web-platform` public smoke bundle renders with `nginx-web`, `httpbin`,
  `whoami`, and `redis`
- rendered assets validate through `validate-platform-assets.ps1`
- rendered manifest schema validation is wired through `kubeconform` first,
  then `kubectl apply --dry-run=client --validate=true`
- Kubernetes security baseline checks cover workload hardening, RBAC,
  NetworkPolicy review items, and concrete sensitive Secret values
- every bundled environment preset and every public profile shape is covered by
  the render matrix

Use the broader repository workflow after the maintenance gate when you are
preparing a delivery or checking one environment preset end to end:

```powershell
.\scripts\invoke-repository-validation.ps1 -EnvironmentPreset dev
```

That command adds strict workstation validation. A failure there can mean local
tools such as `kubectl` or `helm` are missing even when the template maintenance
gate is healthy.

## Progress Dashboard Evidence

If a progress dashboard still reports `kubernetes validation failed`, collect
these checks in order:

| Evidence | Command | Interpret it as |
| --- | --- | --- |
| Template maintenance gate | `env PATH="$HOME/.local/bin:$PATH" pwsh -NoProfile -File scripts/validate-template.ps1` | Passing means the public-default template, render matrix, schema-validator wiring, and security baseline are healthy for `template-maintenance`. |
| Readiness report | `.\scripts\show-validation-readiness.ps1 -Profile web-platform -Applications nginx-web,httpbin,whoami -DataServices redis -Format markdown` | Shows whether the current machine has the tools needed for the selected validation workflow. |
| Strict workstation check | `.\scripts\validate-workstation.ps1 -Strict` | Identifies missing required tools for the broader repository workflow. |
| Broader repository workflow | `.\scripts\invoke-repository-validation.ps1 -EnvironmentPreset dev` | Validates the `dev` preset through template, workstation, and rendered bundle checks. |

Record the exact failing command before changing manifests. Template regressions
should be fixed in source files or catalogs; workstation readiness failures
should be fixed by installing the missing local tool and rerunning the same
command.

## Public Defaults And Values Files

Maintenance validation intentionally uses
`config/platform-values.env.example`. The bundled environment presets set
`ValidationValuesFile` to that public values file so validation does not depend
on local hostnames, storage paths, or secret placeholders.

After creating a site-specific values file, validate it explicitly:

```powershell
.\scripts\invoke-repository-validation.ps1 `
  -EnvironmentPreset dev `
  -ValuesFile config\platform-values.dev.env
```

Do not treat local values-file failures as public template regressions until the
public maintenance gate also fails.

## Maintenance Guardrails

- Keep public image defaults unless a profile explicitly documents another
  image source.
- Keep rendered `out/` bundles, kubeconfigs, generated secret manifests with
  real values, and local environment files out of commits.
- Keep CRD-backed resources skipped in generic public validation unless the
  selected validator has the required CRD schemas available.
- Use `-FailOnHighSecurityBaselineFinding` only when high-severity baseline
  findings should block the selected validation command.
- Do not add live cluster access as a requirement for the public maintenance
  gate.
