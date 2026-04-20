# adminer

Uses the public `adminer:5.3.0-standalone` image as a generic database administration UI.

Files:

- `adminer.yaml`: deployment with `ADMINER_DEFAULT_SERVER` rendered from the values file
- `service.yaml`: internal ClusterIP service on port `8080`

Keep this service internal by default and expose it only behind authentication or temporary port-forwarding.
