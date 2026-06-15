# 100_namespace

Creates the shared namespaces used by the template.

Current namespaces:

- `platform`
- `mysql`

The `platform-public-ingress-baseline` NetworkPolicy is intentionally permissive.
It makes the template's public-default network posture explicit without changing
first-run connectivity for demo workloads, Gateway API examples, or ingress
controllers that may run outside the `platform` namespace. Tighten or replace it
with environment-specific allow lists before production promotion.

Adjust these only if your organization has a different namespace layout standard.
