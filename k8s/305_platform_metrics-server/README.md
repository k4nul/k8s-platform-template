# 305_platform_metrics-server

Metrics Server add-on required for `kubectl top`, many autoscaling flows, and VPA.

Use this only when your managed cluster does not already provide the metrics API.

The APIService template keeps TLS verification enabled. If your bootstrap path
uses a metrics-server serving certificate that is not trusted by the aggregation
layer yet, patch the rendered bundle with an environment-specific CA bundle or a
reviewed temporary exception outside the repository template.
