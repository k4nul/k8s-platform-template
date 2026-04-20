# 300_jenkins

Contains the generic Jenkins deployment and service resources used when you want Jenkins inside the cluster.

Default behavior:

- common ports only
- internal ClusterIP service
- separate JNLP service

Expose it through your own ingress, gateway, or load balancer strategy if you need external access.
