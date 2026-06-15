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

The maintenance gate explicitly uses `config/platform-values.env.example` for
its smoke render and full render matrix. The bundled environment presets also
set `ValidationValuesFile` to that public values file so preset-based repository
validation stays public by default when no explicit values file is passed.

After creating a site-specific values file, validate it explicitly:

```powershell
.\scripts\invoke-repository-validation.ps1 `
  -EnvironmentPreset dev `
  -ValuesFile config\platform-values.dev.env
```

Do not treat local values-file failures as public template regressions until the
public maintenance gate also fails.

## Profile And Environment Matrix Maintenance

Every profile or environment preset change should preserve the public render
matrix contract:

- Environment preset entries are discovered from every
  `config/environments/*.psd1` file and run before profile entries.
- Environment entries normally use `ValidationValuesFile` for public validation.
  Keep bundled presets pointed at `config/platform-values.env.example` unless a
  new public defaults file is intentionally introduced.
- Direct `validate-render-matrix.ps1 -ValuesFile <path>` runs override every
  environment and profile entry with that values file, which is the right check
  for a generated site-specific values file.
- Profile entries are discovered from every `config/profiles/*.psd1` file.
  Each profile must declare `ValidationApplications` and
  `ValidationDataServices`, even when the intended validation list is empty.
- `ValidationIncludeJenkins` should stay disabled for public profiles unless the
  profile intentionally needs Jenkins assets in its render-validation coverage.
- Optional manual follow-up manifests should remain outside generated bundles
  unless the profile or platform catalog explicitly promotes them into the
  public render path.

When adding or changing a profile, update the profile `.psd1` owner metadata and
public validation selections in the same change. Then run:

```powershell
.\scripts\validate-render-matrix.ps1
.\scripts\validate-template.ps1
```

When adding or changing an environment preset, keep `ValidationValuesFile`
separate from site-specific `ValuesFile` defaults so repository validation does
not depend on private hostnames, storage paths, or secret placeholders. Then run
the matrix directly before the full maintenance gate:

```powershell
.\scripts\validate-render-matrix.ps1
.\scripts\validate-template.ps1
```

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
