# GitHub Actions Poller - Componentes

Visão geral de todos os componentes Kubernetes necessários.

## Arquivo x Componente

### Namespace
**File:** `manifests/01-namespace.yaml`
```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: argocd-poller
```
**Propósito:** Isolamento de recursos. Todos os componentes do poller ficam aqui.

---

### ServiceAccount
**File:** `manifests/02-serviceaccount.yaml`

**No namespace argocd-poller:**
- ServiceAccount `github-poller`
- Usado pelo CronJob

**No namespace argocd:**
- ServiceAccount `github-poller`
- Usado para gerar tokens e acessar API do ArgoCD

---

### RBAC (Role + RoleBinding)
**File:** `manifests/03-rbac.yaml`

**Role `github-poller-appmanager` (no argocd):**
- `applications` - GET, LIST
- `applications/refresh` - CREATE
- `secrets` - GET (se necessário)

**RoleBinding `github-poller-appmanager`:**
- Vincula ServiceAccount `argocd/github-poller` ao Role

**Propósito:** Permitir que o poller leia applications e dispare refresh.

---

### Secret
**File:** `manifests/04-secret.yaml`

**Campos:**
- `github-token` - Token GitHub para acessar Actions API
- `argocd-token` - Token ArgoCD para disparar refresh

**Propósito:** Armazenar credenciais de forma segura (encriptado em etcd).

---

### ConfigMap - Configuração
**File:** `manifests/05-configmap.yaml`

**Campos:**
- `SCHEDULE` - Schedule do CronJob (formato cron)
- `CURL_TIMEOUT` - Timeout para curl calls
- `MAX_RETRIES` - Tentativas (futuro)
- `POLL_INTERVAL` - Intervalo (futuro)

**Propósito:** Separar configuração do código.

---

### ConfigMap - Script
**File:** `manifests/06-configmap-script.yaml`

**Contém:** Script `poller.sh`

**Propósito:** Armazenar o script de polling como volume montável.

**Lógica:**
1. Query GitHub Actions API por cada repo
2. Extrai SHA do último build bem-sucedido
3. Consulta ArgoCD para SHA deployado
4. Compara SHAs
5. Se diferentes: dispara refresh

---

### CronJob
**File:** `manifests/07-cronjob.yaml`

**Recursos:**
- Schedule: Controlado pelo ConfigMap
- Image: `alpine:latest`
- Command: `apk add curl jq && sh /scripts/poller.sh`

**Volumes:**
- `/scripts` - Monta ConfigMap com script

**Environment:**
- `GITHUB_TOKEN` - Do Secret
- `ARGOCD_TOKEN` - Do Secret
- `ARGOCD_SERVER` - hardcoded ou ConfigMap
- `CURL_TIMEOUT` - Do ConfigMap

**Propósito:** Agendar e executar o polling automaticamente.

---

### ArgoCD Application
**File:** `manifests/08-application.yaml`

**Configuração:**
- Repository: `domestic-kubernets`
- Path: `argocd-poller/manifests`
- Sync Policy: Automated (prune + selfHeal)

**Propósito:** Gerenciar todos os componentes do poller via GitOps.

---

## Fluxo de Dependências

```
Namespace (01)
    ↓
ServiceAccount (02)
    ↓
RBAC (03) + Secret (04) + ConfigMaps (05, 06)
    ↓
CronJob (07)
    ↓
Application (08) - opcional, para GitOps
```

## Deploy Order

1. **Namespace** - Precisa existir para outros recursos
2. **ServiceAccount** - Antes do RBAC
3. **RBAC** - Antes do CronJob poder acessar ArgoCD
4. **Secret** - Antes do CronJob poder usar tokens
5. **ConfigMaps** - Antes do CronJob ser criado
6. **CronJob** - Tudo pronto, pode rodar
7. **Application** - Opcional, para gerenciar tudo

## Checklist de Instalação

```bash
# 1. Namespace
[ ] kubectl apply -f manifests/01-namespace.yaml
[ ] kubectl get namespace argocd-poller

# 2. ServiceAccount
[ ] kubectl apply -f manifests/02-serviceaccount.yaml
[ ] kubectl get serviceaccount -n argocd-poller

# 3. RBAC
[ ] kubectl apply -f manifests/03-rbac.yaml
[ ] kubectl get role,rolebinding -n argocd -l app=github-poller

# 4. Secret (PREENCHER ANTES!)
[ ] kubectl apply -f manifests/04-secret.yaml
[ ] kubectl get secret -n argocd-poller github-argocd-tokens

# 5. ConfigMaps
[ ] kubectl apply -f manifests/05-configmap.yaml
[ ] kubectl apply -f manifests/06-configmap-script.yaml
[ ] kubectl get configmap -n argocd-poller

# 6. CronJob
[ ] kubectl apply -f manifests/07-cronjob.yaml
[ ] kubectl get cronjob -n argocd-poller

# 7. Application (opcional)
[ ] kubectl apply -f manifests/08-application.yaml
[ ] kubectl get application -n argocd argocd-poller
```

## Atualizar Componentes

### Schedule
```bash
kubectl patch configmap github-poller-config -n argocd-poller \
  -p '{"data":{"SCHEDULE":"*/5 * * * *"}}'
```

### Script
```bash
# Editar 06-configmap-script.yaml e aplicar
kubectl apply -f manifests/06-configmap-script.yaml
```

### Tokens (Secret)
```bash
kubectl delete secret github-argocd-tokens -n argocd-poller
# Recriar com novos tokens
```

### RBAC
```bash
kubectl apply -f manifests/03-rbac.yaml
```

## Recursos Totais

| Tipo | Nome | Namespace |
|------|------|-----------|
| Namespace | `argocd-poller` | - |
| ServiceAccount | `github-poller` | `argocd-poller` |
| ServiceAccount | `github-poller` | `argocd` |
| Role | `github-poller-appmanager` | `argocd` |
| RoleBinding | `github-poller-appmanager` | `argocd` |
| Secret | `github-argocd-tokens` | `argocd-poller` |
| ConfigMap | `github-poller-config` | `argocd-poller` |
| ConfigMap | `github-poller-script` | `argocd-poller` |
| CronJob | `github-actions-poller` | `argocd-poller` |
| Application | `argocd-poller` | `argocd` |

**Total: 10 recursos**
