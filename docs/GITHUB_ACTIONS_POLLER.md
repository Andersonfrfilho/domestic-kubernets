# GitHub Actions Poller - Auto-Deploy via Polling

## Visão Geral

Sistema que faz **polling** do GitHub Actions a cada 5 minutos para detectar novos builds bem-sucedidos e automaticamente dispara refresh no ArgoCD.

**Por que polling e não webhooks?**
- ✅ Seu K8s local tem acesso à internet (outbound)
- ❌ GitHub não consegue acessar K8s (não está exposto)
- ✅ Polling funciona perfeitamente nesse cenário

## Arquitetura

```
GitHub Actions (4 repos)
        ↓ (build & push GHCR)
GitHub Container Registry (GHCR)
        ↓ (poll a cada 5 min)
CronJob no Kubernetes
        ↓ (detecta novo build)
ArgoCD API (refresh)
        ↓
ArgoCD sincroniza manifests
        ↓
K8s restart pods com nova imagem
```

## Como Funciona

### 1. CronJob Scheduler
- Roda a cada **5 minutos** (`*/5 * * * *`)
- Namespace: `argocd-poller`
- Image: `alpine:latest` (leve e rápido)

### 2. Script de Polling (`poller.sh`)
Para cada aplicação configurada (API, BFF, Worker, Cron):

1. **Query GitHub Actions API**
   ```bash
   GET https://api.github.com/repos/Andersonfrfilho/{repo}/actions/runs?status=success
   ```
   Extrai o SHA do commit do último build bem-sucedido

2. **Compara com a revision atual**
   - Consulta ArgoCD: qual SHA está atualmente deployado?
   - Se GitHub SHA == ArgoCD revision: ✗ PULA (já está deployado)
   - Se diferentes: ✓ CONTINUA (nova imagem disponível)

3. **Dispara refresh no ArgoCD (apenas se SHA diferente)**
   ```bash
   POST http://argocd-server.argocd:80/api/v1/applications/{app}/refresh
   ```
   **Nota:** Usa porta 80 (HTTP) ao invés de 443 para evitar problemas de TLS

### 3. Secrets
- `github-argocd-tokens` contém:
  - `github-token`: `$GIT_HUB_KUBERNETS_TOKEN`
  - `argocd-token`: Service account token (10 anos)

## Seviços Monitorados

| App | GitHub Repo | ArgoCD App | Checado |
|-----|-------------|-----------|---------|
| API | domestic-backend-api | domestic-api | ✓ |
| BFF | domestic-backend-bff | domestic-bff | ✓ |
| Worker | domestic-backend-worker | domestic-worker | ✓ |
| Cron | domestic-backend-cron | domestic-cron | ✓ |

## Monitoramento

### Logs do Poller
```bash
# Ver último run
kubectl logs -n argocd-poller -l app=github-actions-poller --tail=50

# Ver todos os runs
kubectl logs -n argocd-poller -l app=github-actions-poller --all-containers
```

### Próximo run
```bash
kubectl get cronjob -n argocd-poller github-actions-poller
```

### Testar manualmente
```bash
kubectl create job --from=cronjob/github-actions-poller test-run -n argocd-poller
kubectl logs -n argocd-poller -l job-name=test-run --follow
```

## Fluxo Completo

1. **Você faz push** para qualquer repo (api, bff, worker, cron)
   ```bash
   git push origin main
   ```

2. **GitHub Actions compila** (seu workflow atual)
   ```
   ✓ Build
   ✓ Tests
   ✓ Docker build
   ✓ Push to GHCR
   ```

3. **Poller detecta** (a cada 5 minutos)
   ```
   ✓ Checa GitHub Actions
   ✓ Encontra novo run bem-sucedido
   ```

4. **ArgoCD sincroniza** (imediato)
   ```
   ✓ Refresh applications
   ✓ Detecta mudança no GHCR
   ✓ Puxa nova imagem
   ```

5. **K8s restart** (automático)
   ```
   ✓ Pod termina
   ✓ Nova imagem pulled
   ✓ Pod inicia com novo código
   ```

**Tempo total: ~5 min (máximo)**

## Troubleshooting

### "No successful runs found"

**Problema**: Nenhum build bem-sucedido encontrado

**Causas possíveis**:
- ✗ Último workflow falhou
- ✗ Nenhum commit para a branch `main` recentemente
- ✗ Workflow ainda em execução

**Solução**:
1. Verificar GitHub Actions: `https://github.com/Andersonfrfilho/{repo}/actions`
2. Fazer novo push para `main` para disparar workflow
3. Aguardar workflow completar com sucesso

### "SKIPPED (already deployed)" para todos os apps

**Problema**: O poller roda mas não faz refresh em nenhuma aplicação

**Causas possíveis**:
- ✓ Comportamento normal se não há novos commits (SHAs são iguais)
- ✗ ArgoCD não está retornando a revision correta
- ✗ Token de ArgoCD inválido ou expirado

**Solução**:
```bash
# 1. Verificar último run do poller
kubectl logs -n argocd-poller -l app=github-actions-poller --tail=50

# 2. Se todos estão com "No successful runs" - verificar GitHub
# Se todos estão com "already deployed" mas há commits novos - verificar token
kubectl get secret -n argocd-poller github-argocd-tokens -o jsonpath='{.data.argocd-token}' | base64 -d | head -c 50

# 3. Testar manualmente com novo push
git push origin main
# Esperar ~5 min para o próximo poll ciclo
```

### "Permission denied" no curl

**Problema**: Não consegue fazer refresh no ArgoCD

**Causas**:
- ✗ Token inválido ou expirado
- ✗ Service account sem permissões
- ✗ ArgoCD server não acessível

**Solução**:
```bash
# Regenerar token ArgoCD
kubectl -n argocd create token github-poller --duration=87600h

# Update secret
kubectl create secret generic github-argocd-tokens \
  --from-literal=github-token=$GIT_HUB_KUBERNETS_TOKEN \
  --from-literal=argocd-token=<novo-token> \
  -n argocd-poller --dry-run=client -o yaml | kubectl apply -f -

# Reiniciar CronJob (próximo ciclo em 5 min)
```

### Poller rodando mas não faz refresh

**Problema**: Script executa mas ArgoCD não sincroniza

**Debug**:
```bash
# Verificar RBAC
kubectl auth can-i get applications \
  --as=system:serviceaccount:argocd-poller:github-poller

# Testar manualmente
kubectl -n argocd-poller run -it debug --image=alpine -- sh
# apk add jq curl
# curl -H "Authorization: Bearer $ARGOCD_TOKEN" https://argocd-server.argocd:443/api/v1/applications/domestic-api -k
```

## Performance

| Métrica | Valor |
|---------|-------|
| Frequência polling | A cada 5 minutos |
| Tempo de detecção | Até 5 min após build |
| Tempo de sync | 30-60 seg |
| CPU por run | 50m (request) / 200m (limit) |
| Memory | 64Mi (request) / 256Mi (limit) |

## Segurança

- ✅ Tokens guardados em Secrets do K8s (encriptados em etcd)
- ✅ RBAC restringido ao mínimo necessário
- ✅ HTTPS com `-k` (ignora cert self-signed local)
- ✅ Tokens com expiração (10 anos, renegociável)
- ✅ Sem hardcoding de credenciais no script

## Prevenção de Deployments Duplicados

O script automaticamente **compara commits SHAs** entre GitHub e ArgoCD:

```
GitHub Actions: SHA abc123def456...
ArgoCD Deployed: SHA abc123def456...
                 ↓
            SHAs são iguais?
            ✓ SIM → Pula (economiza API calls e evita redeploy)
            ✗ NÃO → Trigger refresh (nova imagem detectada)
```

Isso evita que o poller despache a mesma imagem múltiplas vezes, mesmo que o cron rode a cada 5 minutos sem novos commits.

## Customização

### Mudar frequência de polling

```bash
kubectl patch cronjob github-actions-poller \
  -n argocd-poller \
  -p '{"spec":{"schedule":"*/10 * * * *"}}'  # Cada 10 minutos
```

### Adicionar nova aplicação

Edite o ConfigMap:
```bash
kubectl edit configmap -n argocd-poller github-poller-script
```

Na função `check_app`, adicione uma nova chamada:
```sh
# No final do script, antes do "echo ==="
check_app "myapp" "domestic-backend-myapp" "domestic-myapp"
```

Depois reinicie o CronJob:
```bash
kubectl delete cronjob -n argocd-poller github-actions-poller
# O ArgoCD Application Controller vai recriá-lo automaticamente
```

### Remover uma aplicação

Simplesmente remova a linha `check_app` correspondente no ConfigMap.

## Recursos Kubernetes

```bash
# Ver todos os recursos
kubectl get all -n argocd-poller

# Ver CronJob
kubectl get cronjob -n argocd-poller

# Ver histórico de runs
kubectl get jobs -n argocd-poller

# Ver secrets
kubectl get secret -n argocd-poller
```

## Próximos Passos (Opcional)

Se quiser ainda mais otimização:

1. **Usar SHA/Digest ao invés de tags**
   - Detectar mudanças por SHA da imagem
   - Mais preciso que tags `main`

2. **Slack/Discord notifications**
   - Notificar quando deploy acontecer

3. **Métricas Prometheus**
   - Contar refreshes/falhas
   - Tempo de delay

4. **GitHub Webhook (quando tiver accesso)**
   - Deploy imediato (não esperar 5 min)
