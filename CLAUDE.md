# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Repo Is

Kubernetes manifests for a self-hosted home-lab stack running on either **macOS (minikube)** or **Ubuntu (k3s)**. Everything deploys into the `domestic` namespace. GitOps is handled by ArgoCD on the Ubuntu path.

## Common Commands

### Local dev (macOS + minikube)
```bash
./scripts/start-macos.sh                  # validate & apply full stack
./scripts/start-macos.sh --with-observability  # include Grafana/Prometheus/Loki/Jaeger
skaffold dev                              # hot-reload API (syncs .ts files without rebuild)
skaffold dev --profile=observability      # include observability stack in hot-reload
k9s -n domestic                           # terminal UI for pods/logs/exec
```

### Remote dev (Ubuntu + k3s)
```bash
./scripts/install-argocd-ubuntu.sh <git-url>   # one-time: install ArgoCD + apply all apps
argocd app sync domestic-infra domestic-auth domestic-services
```

### Day-to-day operations
```bash
kubectl get all -n domestic
kubectl logs -f deployment/api -n domestic -c api
kubectl rollout restart deployment/api -n domestic

# Run migrations manually (delete old job first)
kubectl delete job migrator -n domestic --ignore-not-found
kubectl apply -f migrator/migrator.job.yaml

# Port-forward databases for local access
kubectl port-forward svc/postgres 5432:5432 -n domestic
kubectl port-forward svc/mongo 27017:27017 -n domestic
kubectl port-forward svc/redis 6379:6379 -n domestic

# Rebuild API image (macOS, uses minikube daemon)
eval $(minikube docker-env)
docker build -f ../domestic-backend-api/Dockerfile.dev -t domestic-api:local ../domestic-backend-api
```

## Architecture

### Service Tiers

**Ingress layer** — nginx Ingress Controller gets a MetalLB IP (192.168.1.200 on Ubuntu). DNS wildcard `*.domestic.local` points there via dnsmasq.

**Gateway tier**
- `kong.domestic.local` → Kong API Gateway (handles auth via Keycloak token introspection)
- `keycloak.domestic.local` → Keycloak (OAuth2/OIDC identity provider)
- `api.domestic.local` → NestJS API (direct, bypasses Kong — for dev/debug)

**Application tier** — API (3000), BFF (3001), Worker (3002), Cron (3003). Worker consumes RabbitMQ queues; Cron runs scheduled jobs.

**Infrastructure tier** (all StatefulSets with PVCs)
- PostgreSQL (5432) — primary app database
- PostgreSQL-Keycloak — dedicated Keycloak DB (separate StatefulSet)
- MongoDB (27017)
- Redis (6379)
- RabbitMQ (5672 / 15672)
- MinIO (9000 / 9001)

**Observability tier** (optional) — Prometheus, Grafana, Loki, Jaeger.

### Auth Flow
Browser → Kong → Keycloak (login) → Kong introspects token → forwards to API or returns 401.

### Deployment Order (Critical)

ArgoCD enforces this via sync-waves; manual scripts enforce it via `kubectl wait`:

1. Namespace
2. Secrets + ConfigMaps
3. Wave 1 — Infrastructure (Postgres, Mongo, Redis, RabbitMQ, MinIO)
4. Wave 2 — Auth (Postgres-Keycloak, Keycloak)
5. Migration Job (one-time schema setup)
6. Wave 3 — Services (API, BFF, Worker, Cron, Kong)
7. Ingress
8. Wave 4 — Observability (optional)

Deployment dependencies are wired as initContainers using `nc` (busybox) health checks before the main container starts.

### Image Strategy: GitOps com GitHub Container Registry (ghcr.io)

No Ubuntu/k3s **não há registry local**. As imagens ficam hospedadas no ghcr.io e o k3s faz pull direto de lá:

```
código fonte → git push → GitHub Actions builda
                                  ↓
                    push → ghcr.io/andersonfrfilho/domestic-api:latest
                                  ↓
                    ArgoCD detecta mudança no manifesto
                                  ↓
                    k3s faz pull do ghcr.io → atualiza pod
```

Para usar imagens privadas no ghcr.io, crie um `imagePullSecret`:
```bash
kubectl create secret docker-registry ghcr-secret \
  --docker-server=ghcr.io \
  --docker-username=andersonfrfilho \
  --docker-password=<github-token> \
  -n domestic
```

E referencie nos deployments:
```yaml
spec:
  imagePullSecrets:
    - name: ghcr-secret
```

Imagens públicas no ghcr.io não precisam de secret.

### Skaffold Profiles (macOS apenas)

| Profile | Use case |
|---|---|
| *(default / minikube)* | macOS local build, no registry push |
| `observability` | Adds observability manifests to sync |
| `full` | All of the above |

Skaffold syncs `.ts` files directly into running pods for NestJS watch-mode — no image rebuild on source changes.

## Key Files

| File/Dir | What it controls |
|---|---|
| `*/secret.yaml` | Credentials for every service — fill in before first deploy |
| `argocd/applications/` | GitOps Application CRs (one per wave) |
| `ingress/` | All HTTP routing rules split by tier |
| `skaffold.yaml` | Image build config and file-sync paths |
| `backup/` | CronJobs for nightly PostgreSQL (02:00 UTC) and MongoDB (02:30 UTC) backups to MinIO |
| `scripts/start-macos.sh` | Validates secrets, builds images in minikube daemon, applies all manifests |
| `scripts/install-argocd-ubuntu.sh` | Installs + configures ArgoCD on k3s |

## Acessando de outros dispositivos na rede

A máquina host usa o IP `192.168.3.60` (Ethernet). O Ingress Controller recebe o IP `192.168.1.200` via MetalLB.

Configure o DNS do dispositivo para apontar para a máquina host:
- **DNS primário:** `192.168.3.60`
- **DNS secundário:** `8.8.8.8`

O dnsmasq na máquina resolve `*.domestic.local → 192.168.1.200` automaticamente. Sem configuração de DNS, acesse direto pelo IP com o header `Host`:
```bash
curl -H "Host: kong.domestic.local" http://192.168.1.200/sua-rota
```

## Web Panels

| Service | URL | User | Password |
|---|---|---|---|
| Keycloak | `http://keycloak.domestic.local` | `domestic` | `admin` |
| RabbitMQ | `http://queue.domestic.local` | `domestic` | `backendapi123` |
| MinIO | `http://storage.domestic.local` | `domestic` | `minioadmin` |
| ArgoCD | `http://argocd.domestic.local` | `admin` | *(auto-generated, shown by install script)* |
| Grafana | `http://grafana.domestic.local` | `admin` | *(see grafana secret)* |
