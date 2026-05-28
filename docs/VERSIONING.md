# Versioning Strategy

This document outlines the versioning and tagging strategy for the Domestic stack.

## Application Versioning (Semantic Versioning)

Applications follow [Semantic Versioning](https://semver.org/) format: `MAJOR.MINOR.PATCH`

### Repositories
- `domestic-backend-api`
- `domestic-backend-bff`
- `domestic-backend-cron`
- `domestic-backend-worker`

### Release Process

1. **Automatic Tag Creation**: When code is pushed to `main` branch, GitHub Actions automatically builds and pushes images with:
   - `:main` — Latest development build (tracked by ArgoCD Image Updater for continuous deployment)
   - `:sha-{SHORT_SHA}` — Build-specific tag for traceability

2. **Manual Release Tags**: Create semantic version tags for releases:
   ```bash
   git tag v0.1.0 -m "Release v0.1.0: Description"
   git push origin v0.1.0
   ```
   
   This triggers GitHub Actions to build and push additional tags:
   - `:0.1.0` — Exact semantic version
   - `:0.1` — Minor version (latest 0.1.x)
   - `:0` — Major version (latest 0.x)

### Current Status
- API: v0.1.0 (last updated: OTLP span export with full-hash ID format, May 27 2026)
- BFF: v0.1.0 (last updated: OTLP span export with full-hash ID format, May 27 2026)
- Cron: v0.1.0 (last updated: nestjs-logger 0.2.4, May 27 2026)
- Worker: v0.1.0 (last updated: nestjs-logger 0.2.4, May 27 2026)

### ArgoCD Automation

**Image Updater Rules**: Applications are configured to accept:
- `main` — Continuous deployment on every push to main
- `v*.*.*` — Can be manually pinned to semantic versions for stability

To pin a deployment to a specific version:
```bash
# Update deployment image
kubectl set image deployment/api api=ghcr.io/andersonfrfilho/domestic-backend-api:0.1.0 -n domestic

# Or update the manifest and let ArgoCD sync
```

## Infrastructure Versioning

All infrastructure components use pinned versions to ensure reproducibility and stability.

### Current Pinned Versions (May 27, 2026)

| Component | Version | Registry |
|-----------|---------|----------|
| Kong | 3.9.1 | docker.io |
| Grafana | 11.0.0 | docker.io |
| Tempo | 2.4.0 | docker.io |
| Prometheus | 2.53.0 | docker.io |
| Loki | 2.9.4 | docker.io |
| Jaeger | 1.51.0 | docker.io |
| Promtail | 2.9.4 | docker.io |
| PostgreSQL | 18 | docker.io |
| MongoDB | 7 | docker.io |
| Redis | 7 | docker.io |
| RabbitMQ | 3.12-management | docker.io |
| Keycloak | 25.0 | quay.io |

### Updating Infrastructure

To upgrade an infrastructure component:

1. Update the image tag in the relevant manifest:
   ```yaml
   image: grafana/grafana:11.1.0  # Change version here
   ```

2. Test in development environment (minikube)

3. Commit and push to main (GitOps will deploy via ArgoCD)

4. Monitor ArgoCD sync status and pod startup

## Image Registry

All images are stored in:
- **GitHub Container Registry (GHCR)**: `ghcr.io/andersonfrfilho/domestic-backend-*`
- **Docker Hub**: Infrastructure components (Kong, Grafana, Prometheus, etc.)
- **Quay.io**: Keycloak

## Related Documents

- [CLAUDE.md](../CLAUDE.md) - Development guidelines
- [Architecture](./ARCHITECTURE.md) - System architecture
