# GitHub Actions Poller - Auto-Deploy Configuration

Sistema automático de polling do GitHub Actions que dispara refresh no ArgoCD quando detecta novos builds.

## Quick Start

### Mudar Schedule

Edite `configmap-schedule.yaml` e aplique:

```bash
# Alterar para cada 5 minutos
sed -i 's/SCHEDULE: ".*"/SCHEDULE: "\/5 * * * *"/' configmap-schedule.yaml
kubectl apply -f configmap-schedule.yaml

# Ou editar direto
kubectl edit configmap github-poller-config -n argocd-poller
```

### Acompanhar Execuções

```bash
# Logs do último job
kubectl logs -n argocd-poller -l app=github-actions-poller --tail=30

# Status do CronJob
kubectl get cronjob -n argocd-poller github-actions-poller

# Visualizar todas as execuções
kubectl get jobs -n argocd-poller --sort-by=.metadata.creationTimestamp
```

### Testar Manualmente

```bash
# Disparar uma execução agora
kubectl create job --from=cronjob/github-actions-poller test-now -n argocd-poller

# Ver logs em tempo real
kubectl logs -n argocd-poller -l job-name=test-now -f
```

## Valores de SCHEDULE

| Valor | Frequência | Use case |
|---|---|---|
| `* * * * *` | A cada minuto | Testes rápidos |
| `*/5 * * * *` | A cada 5 minutos | Default - bom balanço |
| `*/10 * * * *` | A cada 10 minutos | Economizar API calls |
| `0 * * * *` | A cada hora | Produção conservadora |
| `0 */6 * * *` | A cada 6 horas | Apenas para fallback |

## Como Funciona

```
[GitHub Actions]
       ↓ (build & push)
[GHCR - GitHub Container Registry]
       ↓ (poll a cada N minutos)
[CronJob - kubernetes]
       ├─ Query GitHub Actions API
       ├─ Extrai SHA do último build bem-sucedido
       ├─ Compara com SHA deployado no ArgoCD
       │
       ├─ SHAs iguais? → SKIP (já está deployado)
       └─ SHAs diferentes? → Dispara refresh no ArgoCD
              ↓
       [ArgoCD]
       ├─ Detecta nova imagem no GHCR
       └─ Atualiza pods automaticamente
```

## Arquivos

| File | Propósito |
|---|---|
| `configmap-schedule.yaml` | ConfigMap com schedule e settings |
| `../docs/GITHUB_ACTIONS_POLLER.md` | Documentação completa |

## Troubleshooting

### "Poll cycle completed: 0 refresh(es) triggered"

Significa que o poller rodou mas:
- ✓ Não há novos commits (comportamento esperado)
- ✓ As imagens já estão deployadas (SHA comparison funciona)

### "No successful runs found"

O GitHub Actions não tem builds bem-sucedidos. Verificar:
```bash
# Ver últimos builds da API
curl -s -H "Authorization: token $GITHUB_TOKEN" \
  "https://api.github.com/repos/Andersonfrfilho/domestic-backend-api/actions/runs?per_page=3" | \
  jq '.workflow_runs[] | {status: .status, conclusion: .conclusion}'
```

### "Refresh triggered" mas nada aconteceu

ArgoCD pode estar com problema. Verificar:
```bash
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-server
```

## Próximas Melhorias

- [ ] Suporte a múltiplas branches (não apenas `main`)
- [ ] Notificações (Slack/Discord) ao fazer deploy
- [ ] Métricas Prometheus (total refreshes, latency)
- [ ] Webhook do GitHub (quando tiver acesso inbound)
