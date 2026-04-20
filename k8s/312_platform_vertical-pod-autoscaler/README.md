# Vertical Pod Autoscaler Template

Use this directory when you want automated CPU and memory request tuning for workloads that are not already governed by an HPA on the same resource metrics.

## Install Notes

The VPA project is an add-on and must be installed separately from core Kubernetes. It also requires a metrics source such as metrics-server.

This directory includes:

- `values.yaml`: a Helm values scaffold aligned to the supported VPA chart in the upstream autoscaler repository
- `example-nginx-web-vpa.yaml`: a conservative example VPA object for the `nginx-web` deployment

## Important Cautions

- Do not combine VPA and HPA on the same workload if both are trying to control CPU or memory-based scaling.
- Prefer `Initial` or carefully scoped policies first when introducing VPA on stateful or latency-sensitive services.
- Install VPA only after `metrics-server` is healthy.
