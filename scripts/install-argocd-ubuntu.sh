#!/usr/bin/env bash
# install-argocd-ubuntu.sh
# Instala e configura o ArgoCD no k3s (Ubuntu) + registra o repositório git
# e aplica o AppProject + todos os Applications da stack domestic.
#
# Pré-requisitos:
#   - k3s instalado e rodando (kubectl funcional)
#   - nginx Ingress Controller + MetalLB já configurados
#   - dnsmasq com *.domestic.local → IP do MetalLB
#
# Uso:
#   ./scripts/install-argocd-ubuntu.sh [GIT_REPO_URL] [--private-key /path/to/id_rsa]
#
# Exemplos:
#   ./scripts/install-argocd-ubuntu.sh https://github.com/org/kubernetes.git
#   ./scripts/install-argocd-ubuntu.sh git@github.com:org/kubernetes.git --private-key ~/.ssh/id_rsa

set -euo pipefail

# ─────────────────────────────────────────
# Argumentos
# ─────────────────────────────────────────
GIT_REPO_URL="${1:-}"
PRIVATE_KEY_PATH=""

for arg in "$@"; do
  shift
  if [[ "$arg" == "--private-key" ]]; then
    PRIVATE_KEY_PATH="${1:-}"
  fi
done

# ─────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────
info()    { echo -e "\033[0;34m[INFO]\033[0m  $*"; }
success() { echo -e "\033[0;32m[OK]\033[0m    $*"; }
warn()    { echo -e "\033[0;33m[WARN]\033[0m  $*"; }
error()   { echo -e "\033[0;31m[ERROR]\033[0m $*" >&2; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
K8S_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# ─────────────────────────────────────────
# 1. Instalar ArgoCD
# ─────────────────────────────────────────
info "Criando namespace argocd..."
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -

info "Instalando ArgoCD (stable)..."
kubectl apply --server-side --force-conflicts -n argocd \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

info "Aguardando pods do ArgoCD ficarem prontos (pode demorar 2-3 min)..."
kubectl wait --namespace argocd \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/name=argocd-server \
  --timeout=180s

success "ArgoCD instalado."

# ─────────────────────────────────────────
# 2. Configurar modo HTTP (sem TLS) — mais simples para rede local
# ─────────────────────────────────────────
info "Configurando ArgoCD para modo HTTP (insecure)..."
kubectl apply -f "$K8S_DIR/argocd/argocd-params.configmap.yaml"

info "Reiniciando argocd-server para aplicar configuração..."
kubectl rollout restart deployment/argocd-server -n argocd
kubectl rollout status deployment/argocd-server  -n argocd --timeout=120s

success "ArgoCD em modo HTTP."

# ─────────────────────────────────────────
# 3. Expor via Ingress (argocd.domestic.local)
# ─────────────────────────────────────────
info "Aplicando Ingress do ArgoCD..."
kubectl apply -f "$K8S_DIR/argocd/argocd-ingress.yaml"
success "Ingress aplicado — será acessível em http://argocd.domestic.local"

# ─────────────────────────────────────────
# 4. Recuperar senha inicial do admin
# ─────────────────────────────────────────
info "Aguardando secret argocd-initial-admin-secret..."
until kubectl get secret argocd-initial-admin-secret -n argocd &>/dev/null; do
  sleep 2
done

ARGOCD_PASSWORD=$(kubectl get secret argocd-initial-admin-secret \
  -n argocd -o jsonpath="{.data.password}" | base64 -d)

success "Senha inicial do admin: $ARGOCD_PASSWORD"
echo ""
warn "Anote esta senha. Após o primeiro login, troque em:"
warn "  argocd account update-password  (ou via UI → User Info → Update Password)"
echo ""

# ─────────────────────────────────────────
# 5. Instalar argocd CLI (opcional — se não estiver instalado)
# ─────────────────────────────────────────
if ! command -v argocd &>/dev/null; then
  info "Instalando argocd CLI..."
  ARGOCD_VERSION=$(curl -s https://api.github.com/repos/argoproj/argo-cd/releases/latest \
    | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/')
  curl -sSL -o /usr/local/bin/argocd \
    "https://github.com/argoproj/argo-cd/releases/download/${ARGOCD_VERSION}/argocd-linux-amd64"
  chmod +x /usr/local/bin/argocd
  success "argocd CLI instalado: $(argocd version --client --short)"
else
  info "argocd CLI já instalado: $(argocd version --client --short)"
fi

# ─────────────────────────────────────────
# 6. Login no ArgoCD via CLI
# ─────────────────────────────────────────
info "Fazendo login no ArgoCD..."

# Aguardar o ArgoCD responder (Ingress pode demorar alguns segundos)
ARGOCD_URL="argocd.domestic.local"
for i in $(seq 1 20); do
  if curl -sf "http://$ARGOCD_URL/healthz" &>/dev/null; then
    break
  fi
  if [[ "$i" == "20" ]]; then
    warn "ArgoCD não respondeu via Ingress após 40s."
    warn "Tente manualmente após o script:"
    warn "  argocd login argocd.domestic.local --username admin --password '$ARGOCD_PASSWORD' --insecure --http"
    ARGOCD_URL=""
  fi
  sleep 2
done

if [[ -n "$ARGOCD_URL" ]]; then
  argocd login "$ARGOCD_URL" \
    --username admin \
    --password "$ARGOCD_PASSWORD" \
    --insecure \
    --grpc-web \
    2>/dev/null || warn "Login via CLI falhou — continue pela UI."
  success "Login realizado."
fi

# ─────────────────────────────────────────
# 7. Registrar repositório git
# ─────────────────────────────────────────
if [[ -z "$GIT_REPO_URL" ]]; then
  warn "Nenhum repositório git informado. Pule para o passo 8 manualmente."
  warn "Para registrar depois:"
  warn "  argocd repo add <URL> [--ssh-private-key-path ~/.ssh/id_rsa]"
else
  info "Registrando repositório: $GIT_REPO_URL"

  if [[ -n "$PRIVATE_KEY_PATH" ]]; then
    argocd repo add "$GIT_REPO_URL" \
      --ssh-private-key-path "$PRIVATE_KEY_PATH" \
      --insecure-ignore-host-key 2>/dev/null \
      || warn "Falha ao registrar repo com chave SSH. Verifique a chave e tente manualmente."
  else
    argocd repo add "$GIT_REPO_URL" --insecure 2>/dev/null \
      || warn "Falha ao registrar repo público. Tente manualmente se o repo for privado."
  fi

  success "Repositório registrado."

  # ─────────────────────────────────────────
  # 8. Atualizar CHANGE_ME_GIT_REPO_URL nos Application CRs
  # ─────────────────────────────────────────
  info "Substituindo CHANGE_ME_GIT_REPO_URL nos Applications..."
  ESCAPED_URL=$(printf '%s\n' "$GIT_REPO_URL" | sed -e 's/[\/&]/\\&/g')

  for file in "$K8S_DIR"/argocd/applications/*.yaml; do
    if grep -q "CHANGE_ME_GIT_REPO_URL" "$file"; then
      sed -i "s/CHANGE_ME_GIT_REPO_URL/$ESCAPED_URL/g" "$file"
      info "  Atualizado: $(basename "$file")"
    fi
  done

  # app-project.yaml também
  PROJECT_FILE="$K8S_DIR/argocd/applications/app-project.yaml"
  if grep -q "CHANGE_ME_GIT_REPO_URL" "$PROJECT_FILE"; then
    sed -i "s/CHANGE_ME_GIT_REPO_URL/$ESCAPED_URL/g" "$PROJECT_FILE"
    info "  Atualizado: app-project.yaml"
  fi

  success "URLs atualizadas."
fi

# ─────────────────────────────────────────
# 9. Aplicar AppProject + Application CRs
# ─────────────────────────────────────────
info "Aplicando AppProject (domestic)..."
kubectl apply -f "$K8S_DIR/argocd/applications/app-project.yaml"

info "Aplicando Applications (waves 1-4)..."
kubectl apply -f "$K8S_DIR/argocd/applications/app-infra.yaml"
kubectl apply -f "$K8S_DIR/argocd/applications/app-auth.yaml"
kubectl apply -f "$K8S_DIR/argocd/applications/app-services.yaml"
kubectl apply -f "$K8S_DIR/argocd/applications/app-observability.yaml"

success "Applications aplicados."

# ─────────────────────────────────────────
# Resumo final
# ─────────────────────────────────────────
echo ""
echo "════════════════════════════════════════════════════════════"
success "ArgoCD instalado e configurado com sucesso!"
echo "════════════════════════════════════════════════════════════"
echo ""
echo "  URL:      http://argocd.domestic.local"
echo "  Usuário:  admin"
echo "  Senha:    $ARGOCD_PASSWORD"
echo ""
echo "  kubectl get applications -n argocd"
echo "  argocd app list"
echo ""
echo "  Para forçar sync imediato:"
echo "    argocd app sync domestic-infra"
echo "    argocd app sync domestic-auth"
echo "    argocd app sync domestic-services"
echo ""
if [[ -z "$GIT_REPO_URL" ]]; then
  echo "  PRÓXIMO PASSO: Registre o repositório git e atualize os Application CRs:"
  echo "    ./scripts/install-argocd-ubuntu.sh <GIT_REPO_URL>"
  echo "  ou manualmente:"
  echo "    argocd repo add <URL>"
  echo "    sed -i 's/CHANGE_ME_GIT_REPO_URL/<URL>/g' argocd/applications/*.yaml"
  echo "    kubectl apply -f argocd/applications/"
  echo ""
fi
echo "════════════════════════════════════════════════════════════"
