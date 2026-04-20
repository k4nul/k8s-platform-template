# whoami

Uses the public `traefik/whoami:v1.10.4` image for request-header and routing inspection.

Files:

- `whoami.yaml`: deployment for a tiny HTTP responder
- `service.yaml`: internal ClusterIP service on port `80`

This is a good lightweight workload for validating ingress, gateway routing, and service networking.
