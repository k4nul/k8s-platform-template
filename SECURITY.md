# Security Policy

## Supported Versions

Security fixes target the current `main` branch until versioned releases are
published.

## Reporting a Vulnerability

Use GitHub private vulnerability reporting if it is enabled for the repository.
If it is not available, open a public issue with a short summary only and ask
for a private disclosure channel. Do not include kubeconfigs, cluster hostnames,
tokens, secret manifests, rendered production bundles, or exploit details in
public.

## Kubernetes Safety

Do not commit:

- kubeconfigs or cluster credentials
- generated secret manifests containing real values
- private registry credentials
- production ingress hosts unless they are intentionally public
- rendered bundles from `out/`
