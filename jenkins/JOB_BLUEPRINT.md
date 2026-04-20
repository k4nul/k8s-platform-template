# Jenkins Job Blueprint

Recommended generic folder layout:

```text
platform/
  dev/
    repository-validation
    bundle-delivery
    bundle-promotion
  staging/
    repository-validation
    bundle-delivery
    bundle-promotion
  prod/
    repository-validation
    bundle-delivery
    bundle-promotion
```

## Why This Layout

- repository-level jobs stay stable even if application examples change
- delivery and promotion stay clearly separated
- environment presets map cleanly to job folders
- The folder names above are only examples. If your teams use names such as `sandbox`, `qa`, or `production`, the same layout still applies.

## Seeding Defaults

- Leaving `SEED_ENVIRONMENT_PRESETS` blank in `job-seed.Jenkinsfile` will generate jobs for every preset currently present in `config/environments`.
- `SEED_REPO_URL` defaults to `https://github.com/k4nul/k8s-platform-template.git`.
- If you fork or mirror this template, replace `SEED_REPO_URL` before applying the generated DSL so the SCM-backed jobs point at your own repository.

## Optional Service Jobs

The current public-image sample services do not require dedicated Jenkins build jobs.

If you later add your own custom services with Jenkinsfiles, regenerate the plan and seed DSL so those service jobs appear automatically.
