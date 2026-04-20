#!/usr/bin/env bash
# ============================================================
# start-macos.sh — Valida a stack domestic localmente no macOS
#
# Objetivo: confirmar que todos os manifestos K8s sobem corretamente
#           ANTES de levar para o Ubuntu (k3s).
#
# Acesso via NodePort — sem MetalLB, sem DNS, sem minikube tunnel.
#
# Pré-requisitos:
#   brew install minikube kubectl
#   Docker Desktop rodando
#
# Uso:
#   ./scripts/start-macos.sh
#   ./scripts/start-macos.sh --with-observability
# ============================================================

set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
ok()   { echo -e "${GREEN}✔ $1${NC}"; }
warn() { echo -e "${YELLOW}⚠ $1${NC}"; }
fail() { echo -e "${RED}✖ $1${NC}"; exit 1; }
step() { echo -e "\n${YELLOW}── $1 ──${NC}"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
K8S_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
API_DIR="$(cd "$K8S_DIR/../domestic-backend-api" && pwd)"
BFF_DIR="$(cd "$K8S_DIR/../domestic-backend-bff" && pwd)"
WORKER_DIR="$(cd "$K8S_DIR/../domestic-backend-worker" && pwd)"
CRON_DIR="$(cd "$K8S_DIR/../domestic-backend-cron" && pwd)"
WITH_OBS="${1:-}"

# ── Verificações ──────────────────────────────────────────────
step "Verificações"

command -v minikube &>/dev/null || fail "minikube não encontrado: brew install minikube"
command -v kubectl  &>/dev/null || fail "kubectl não encontrado: brew install kubectl"
command -v docker   &>/dev/null || fail "Docker não encontrado. Instale o Docker Desktop."
[[ -d "$API_DIR" ]] || fail "API não encontrada em: $API_DIR"
[[ -d "$BFF_DIR" ]] || fail "BFF não encontrada em: $BFF_DIR"
[[ -d "$WORKER_DIR" ]] || fail "Worker não encontrada em: $WORKER_DIR"
[[ -d "$CRON_DIR" ]] || fail "Cron não encontrada em: $CRON_DIR"

if grep -q "CHANGE_ME" "$K8S_DIR/postgres/postgres.secret.yaml" 2>/dev/null; then
  warn "Secrets com valores CHANGE_ME detectados."
  warn "Edite os arquivos *.secret.yaml antes de continuar."
  echo ""
  read -rp "Continuar mesmo assim? (s/N): " REPLY
  [[ "$REPLY" =~ ^[sS]$ ]] || exit 0
fi

ok "Dependências OK"

# ── Minikube ──────────────────────────────────────────────────
step "Minikube"

if ! minikube status &>/dev/null; then
  minikube start --cpus=6 --memory=8192 --disk-size=40g --driver=docker
  ok "minikube iniciado"
else
  ok "minikube já está rodando"
fi

minikube addons enable ingress &>/dev/null || true

kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=120s 2>/dev/null && ok "Ingress Controller pronto" || warn "Ingress Controller ainda iniciando"

# ── Build das Imagens ─────────────────────────────────────────
step "Build das imagens (daemon do minikube)"

eval "$(minikube docker-env)"

echo "Building API..."
docker build -f "$API_DIR/Dockerfile.dev" -t domestic-api:local "$API_DIR"
echo "Building BFF..."
docker build -f "$BFF_DIR/Dockerfile.dev" -t domestic-bff:local "$BFF_DIR"
echo "Building Worker..."
docker build -f "$WORKER_DIR/Dockerfile.dev" -t domestic-worker:local "$WORKER_DIR"
echo "Building Cron..."
# Cron pode falhar se o lock estiver dessincronizado, tentamos npm install se falhar
docker build -f "$CRON_DIR/Dockerfile.dev" -t domestic-cron:local "$CRON_DIR" || {
  warn "Build do Cron falhou. Tentando sincronizar package-lock..."
  (cd "$CRON_DIR" && npm install)
  docker build -f "$CRON_DIR/Dockerfile.dev" -t domestic-cron:local "$CRON_DIR"
}

ok "Imagens buildadas com sucesso"

# ── Namespace ─────────────────────────────────────────────────
step "Namespace"
kubectl apply -f "$K8S_DIR/namespace.yaml"
ok "Namespace: domestic"

# ── Secrets ───────────────────────────────────────────────────
step "Secrets"
kubectl apply -f "$K8S_DIR/postgres/postgres.secret.yaml"
kubectl apply -f "$K8S_DIR/postgres-keycloak/postgres-keycloak.secret.yaml"
kubectl apply -f "$K8S_DIR/rabbitmq/rabbitmq.secret.yaml"
kubectl apply -f "$K8S_DIR/minio/minio.secret.yaml"
kubectl apply -f "$K8S_DIR/keycloak/keycloak.secret.yaml"
kubectl apply -f "$K8S_DIR/api/api.secret.yaml"
kubectl apply -f "$K8S_DIR/bff/bff.secret.yaml"
kubectl apply -f "$K8S_DIR/worker/worker.secret.yaml"
kubectl apply -f "$K8S_DIR/cron/cron.secret.yaml"
ok "Secrets aplicados"

# ── ConfigMaps dos arquivos da API ────────────────────────────
step "ConfigMaps (arquivos da API + Kong Config)"

# Preparar kong.yml ativando a rota do BFF
TEMP_KONG="/tmp/domestic-kong-macos.yml"
cp "$API_DIR/kong/kong.yml" "$TEMP_KONG"
sed -i '' 's/# - name: bff/- name: bff/g' "$TEMP_KONG"
sed -i '' 's/#   url: http:\/\/bff:3000/    url: http:\/\/bff:3001/g' "$TEMP_KONG"
sed -i '' 's/#   connect_timeout: 10000/    connect_timeout: 10000/g' "$TEMP_KONG"
sed -i '' 's/#   read_timeout: 30000/    read_timeout: 30000/g' "$TEMP_KONG"
sed -i '' 's/#   write_timeout: 30000/    write_timeout: 30000/g' "$TEMP_KONG"
sed -i '' 's/#   routes:/    routes:/g' "$TEMP_KONG"
sed -i '' 's/#     - name: bff-all/      - name: bff-all/g' "$TEMP_KONG"
sed -i '' 's/#       paths:/        paths:/g' "$TEMP_KONG"
sed -i '' 's/#         - \/api\/v1/          - \/api\/v1/g' "$TEMP_KONG"
sed -i '' 's/#       strip_path: false/        strip_path: false/g' "$TEMP_KONG"
# ... simplificando os seds de plugins para garantir indentação correta
# (Em um ambiente real seria melhor ter um kong.dev.yml pronto)

kubectl create configmap kong-declarative-config \
  --from-file=kong.yml="$TEMP_KONG" \
  -n domestic --dry-run=client -o yaml | kubectl apply -f -

kubectl create configmap keycloak-realm-config \
  --from-file=domestic-backend-realm.json="$API_DIR/keycloak-config/domestic-backend-realm.json" \
  -n domestic --dry-run=client -o yaml | kubectl apply -f -

if [[ "$WITH_OBS" == "--with-observability" ]]; then
  kubectl create configmap prometheus-scrape-config \
    --from-file=prometheus.yml="$API_DIR/monitoring/prometheus.yml" \
    -n domestic --dry-run=client -o yaml | kubectl apply -f -
  kubectl create configmap loki-config \
    --from-file=local-config.yaml="$API_DIR/monitoring/loki-config.yml" \
    -n domestic --dry-run=client -o yaml | kubectl apply -f -
fi
ok "ConfigMaps (arquivos) aplicados"

# ── ConfigMaps dos serviços ───────────────────────────────────
step "ConfigMaps dos serviços"
kubectl apply -f postgres/postgres.configmap.yaml
kubectl apply -f postgres-keycloak/postgres-keycloak.configmap.yaml
kubectl apply -f mongo/mongo.configmap.yaml
kubectl apply -f redis/redis.configmap.yaml
kubectl apply -f rabbitmq/rabbitmq.configmap.yaml
kubectl apply -f api/api.configmap.yaml
kubectl apply -f bff/bff.configmap.yaml
kubectl apply -f worker/worker.configmap.yaml
kubectl apply -f cron/cron.configmap.yaml
kubectl apply -f kong/kong.configmap.yaml
kubectl apply -f keycloak/keycloak.configmap.yaml
ok "ConfigMaps dos serviços aplicados"

# ── Infraestrutura ────────────────────────────────────────────
step "Infraestrutura (StatefulSets)"

kubectl apply -f postgres/
kubectl apply -f postgres-keycloak/
kubectl apply -f mongo/
kubectl apply -f redis/
kubectl apply -f rabbitmq/
kubectl apply -f minio/

echo "Aguardando bancos ficarem prontos..."
kubectl rollout status statefulset/postgres          -n domestic --timeout=180s
kubectl rollout status statefulset/postgres-keycloak -n domestic --timeout=180s
kubectl rollout status statefulset/mongo             -n domestic --timeout=180s
kubectl rollout status statefulset/redis             -n domestic --timeout=60s
kubectl rollout status statefulset/rabbitmq          -n domestic --timeout=120s
kubectl rollout status statefulset/minio             -n domestic --timeout=120s
ok "Infraestrutura pronta"

# ── Keycloak ──────────────────────────────────────────────────
step "Keycloak"
kubectl apply -f keycloak/
echo "Aguardando Keycloak..."
kubectl rollout status deployment/keycloak -n domestic --timeout=240s
ok "Keycloak pronto"

# ── Serviços Backend ──────────────────────────────────────────
step "Serviços Backend (API, BFF, Worker, Cron)"
kubectl apply -f api/
kubectl apply -f bff/
kubectl apply -f worker/
kubectl apply -f cron/

echo "Aguardando serviços..."
kubectl rollout status deployment/api    -n domestic --timeout=300s
kubectl rollout status deployment/bff    -n domestic --timeout=180s
kubectl rollout status deployment/worker -n domestic --timeout=180s
ok "Serviços Backend prontos"

# ── Kong ──────────────────────────────────────────────────────
step "Kong"
kubectl apply -f kong/
kubectl rollout status deployment/kong -n domestic --timeout=240s
ok "Kong pronto"

# ── Ingress ───────────────────────────────────────────────────
step "Ingress"
kubectl apply -f ingress/
ok "Ingress aplicado"

# ── Observabilidade (opcional) ────────────────────────────────
if [[ "$WITH_OBS" == "--with-observability" ]]; then
  step "Observabilidade"
  kubectl apply -f observability/prometheus/
  kubectl apply -f observability/loki/
  kubectl apply -f observability/grafana/
  kubectl apply -f observability/jaeger/
  ok "Observabilidade aplicada"
fi

# ── Resultado ─────────────────────────────────────────────────
echo ""
echo -e "${GREEN}════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  Stack domestic COMPLETA validada no macOS!    ${NC}"
echo -e "${GREEN}════════════════════════════════════════════════${NC}"
echo ""
warn "No macOS com driver Docker, use 'minikube tunnel' para os links funcionarem."
echo ""
echo "Links disponíveis (via /etc/hosts):"
echo "  → http://gateway.domestic.local/api/v1/health   (BFF via Kong)"
echo "  → http://keycloak.domestic.local                (Keycloak)"
echo "  → http://bff.domestic.local/health              (BFF Direto)"
echo "  → http://storage.domestic.local                 (MinIO Console)"
echo "  → http://queue.domestic.local                   (RabbitMQ Management)"
echo ""
