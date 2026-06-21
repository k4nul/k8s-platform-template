# Template Maintenance

This guide is for maintainers working through the phase currently recorded in
`docs/instructions/phase-gates.json`. In the current manifest, that is
`template-maintenance` with no pending `next_phase` after the public-default
security review returned the Kubernetes platform template to maintenance. Use it
when a dashboard, scheduled automation, or reviewer reports that Kubernetes
validation is failing and you need to separate a template regression from local
workstation readiness.

## Active Maintenance Scope

The completed review scope was `public-default-security-review`. Routine
maintenance should preserve the intentionally permissive public-default posture
unless a maintainer selects a new explicit phase:

- review `platform-public-ingress-baseline` and keep its demo-friendly ingress
  behavior explicit
- keep Kubernetes Dashboard sample admin and viewer manifests as manual
  follow-up resources outside generated bundles
- preserve public image defaults, public validation values, and rendered output
  cleanup while the review is active
- keep proving the scope with `scripts/validate-template.ps1`, which checks the
  phase manifest, render matrix, schema-validator wiring, and Kubernetes
  security baseline
- keep `template-maintenance` without a pending `next_phase` until a new
  reviewed template scope is selected

Do not add live cluster access, private registry assumptions, or committed
rendered bundles as part of this scope.

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
  NetworkPolicy review items, service account token automount posture, and concrete sensitive Secret values, with
  high-severity source and rendered findings failing the template gate
- every bundled environment preset and every public profile shape is covered by
  the render matrix

Use the broader repository workflow after the maintenance gate when you are
preparing a delivery or checking one environment preset end to end:

```powershell
.\scripts\invoke-repository-validation.ps1 -EnvironmentPreset dev
```

That command adds strict workstation validation and uses the preset's public
`ValidationValuesFile` when no values file is passed. After editing a generated
environment file, pass it explicitly:

```powershell
.\scripts\invoke-repository-validation.ps1 `
  -EnvironmentPreset dev `
  -ValuesFile config\platform-values.dev.env
```

A failure there can mean local tools such as `kubectl` or `helm` are missing
even when the template maintenance gate is healthy.

## Progress Dashboard Evidence

If a progress dashboard still reports `kubernetes validation failed`, collect
these checks in order:

| Evidence | Command | Interpret it as |
| --- | --- | --- |
| Template maintenance gate | `env PATH="$HOME/.local/bin:$PATH" pwsh -NoProfile -File scripts/validate-template.ps1` | Passing means the public-default template, render matrix, schema-validator wiring, and security baseline are healthy for maintenance. |
| Matrix coverage report | `.\scripts\show-render-matrix.ps1 -Format markdown` | Lists the environment and profile entries, values-file resolution, and representative public selections without rendering bundles. |
| Matrix validation | `.\scripts\validate-render-matrix.ps1` | Renders and validates every public environment and profile matrix entry using temporary output. |
| Readiness report | `.\scripts\show-validation-readiness.ps1 -Profile web-platform -Applications nginx-web,httpbin,whoami -DataServices redis -Format markdown` | Shows whether the current machine has the tools needed for the selected validation workflow. |
| Strict workstation check | `.\scripts\validate-workstation.ps1 -Strict` | Identifies missing required tools for the broader repository workflow. |
| Broader repository workflow | `.\scripts\invoke-repository-validation.ps1 -EnvironmentPreset dev` | Validates the `dev` preset through template, workstation, and rendered bundle checks. |

Record the exact failing command before changing manifests. Template regressions
should be fixed in source files or catalogs; workstation readiness failures
should be fixed by installing the missing local tool and rerunning the same
command.

Use this decision path when triaging the dashboard status:

| Result | Meaning | Next action |
| --- | --- | --- |
| Template maintenance gate passes | The public-default template render, render matrix, schema-validator wiring, and security baseline are healthy for the current phase. | Save the command output as maintenance evidence, then inspect workstation readiness before editing manifests. |
| Template maintenance gate fails before rendering | A required repository path, catalog, script, test, or public values file is missing or inconsistent. | Fix the reported repository file and rerun the same gate. |
| Template maintenance gate fails during smoke render or matrix render | A public profile, environment preset, values file, or source manifest no longer renders with public defaults. | Use the failing profile or preset from the error output, then run `.\scripts\validate-render-matrix.ps1` after the fix. |
| Template maintenance gate warns that no schema validator is installed | Non-strict public validation reached the optional schema-validation layer, but this machine cannot prove schemas offline. | Install `kubeconform` or `kubectl` when schema proof is required; do not treat the warning alone as a template regression. |
| Broader repository workflow fails after a passing template gate | The selected environment workflow or workstation is not ready, usually because strict validation requires tools such as `kubectl` or `helm`. | Run the readiness report and strict workstation check before changing template files. |

For automation reports, record the first failing command, whether the template
gate passed, and whether the readiness report lists a missing grouped
requirement such as `kubeconform or kubectl`.

When the template maintenance gate passes and the manifest has no pending
`next_phase`, the remaining dashboard work is not another manifest or
documentation repair. Treat that state as maintenance evidence:

- keep the validation output from the passing `scripts/validate-template.ps1`
  run as the evidence package
- confirm `docs/instructions/phase-gates.json` lists `template-maintenance`, an
  empty `next_phase`, and an empty `transition_validation_command`
- select a new explicit phase before routing another phase-transition task
- keep future phase-transition patches limited to the files listed in
  `transition.phase_update_files`

For this phase, a passing validation command means the public-default
NetworkPolicy posture, Dashboard manual RBAC posture, rendered schema-validator
wiring, and source/rendered security baseline remain healthy for maintenance.

## Render Matrix Evidence Package

When the progress dashboard or a reviewer needs evidence for the profile and
environment render-validation gate, collect these commands as one package:

```powershell
.\scripts\show-render-matrix.ps1 -Format markdown
.\scripts\validate-render-matrix.ps1
.\scripts\validate-template.ps1
```

Use the first command to show the intended matrix entries, values-file
resolution, and representative application and data-service selections. Use the
second command to prove those entries render and validate in temporary output.
Use the template gate as the final maintenance signal because it also runs the
smoke render, schema-validator wiring checks, Kubernetes security baseline, and
the lightweight PowerShell tests.

For a generated values file, keep the public-default package above and add an
explicit override check:

```powershell
.\scripts\show-render-matrix.ps1 -ValuesFile config\platform-values.dev.env -Format markdown
.\scripts\validate-render-matrix.ps1 -ValuesFile config\platform-values.dev.env
```

That override intentionally applies the edited values file to every matrix
entry. Treat failures in this override as site-specific values work unless the
public-default package also fails.

## Phase Transition Readiness

`docs/instructions/phase-gates.json` records `template-maintenance` as the
current phase with no selected next phase after the public-default review. Its
maintenance validation command is the template maintenance gate:

```bash
env PATH="$HOME/.local/bin:$PATH" pwsh -NoProfile -File scripts/validate-template.ps1
```

When that command passes and `transition_validation_command` is empty, routine
maintenance should continue without routing a phase-transition. A future
phase-transition should first select a concrete `next_phase` and validation
command, then update only the phase manifest files listed in
`transition.phase_update_files`. It should not add new platform scope, require
live cluster access, introduce private image defaults, or commit rendered
bundles.

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
.\scripts\show-render-matrix.ps1 -Format markdown
.\scripts\validate-render-matrix.ps1
.\scripts\validate-template.ps1
```

When adding or changing an environment preset, keep `ValidationValuesFile`
separate from site-specific `ValuesFile` defaults so repository validation does
not depend on private hostnames, storage paths, or secret placeholders. Then run
the matrix directly before the full maintenance gate:

```powershell
.\scripts\show-render-matrix.ps1 -Format markdown
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
