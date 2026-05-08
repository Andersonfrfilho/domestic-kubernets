# Deploying GitHub Actions Poller

## Estrutura de Componentes

```
01-namespace.yaml           # Namespace argocd-poller
├── 02-serviceaccount.yaml  # ServiceAccounts (argocd-poller + argocd)
├── 03-rbac.yaml            # Role + RoleBinding no namespace argocd
├── 04-secret.yaml          # Tokens (GitHub + ArgoCD)
├── 05-configmap.yaml       # Configuração (SCHEDULE, CURL_TIMEOUT, etc)
├── 06-configmap-script.yaml # Script de polling
└── 07-cronjob.yaml         # CronJob agendador

08-application.yaml        # ArgoCD Application (GitOps)
```

## Deploy Inicial (Manual)

### Opção 1: Aplicar todos os manifestos
```bash
# Substitua os tokens antes!
kubectl apply -f manifests/
```

### Opção 2: Usar kustomize (recomendado)
```bash
kubectl apply -k manifests/
```

### Opção 3: Deixar ArgoCD gerenciar (GitOps)
```bash
# ArgoCD sincronizará automaticamente
kubectl apply -f manifests/08-application.yaml
```

## Passos Pré-Deploy

### 1. Gerar GitHub Token
```bash
# Em: https://github.com/settings/tokens/new
# Permissões: repo + read:packages
GITHUB_TOKEN="ghp_xxxxxxxxxxxxx"
```

### 2. Gerar ArgoCD Token
```bash
# No seu cluster
ARGOCD_TOKEN=$(kubectl -n argocd create token github-poller --duration=87600h)
```

### 3. Atualizar o Secret
```bash
# Editar: 04-secret.yaml
# Ou criar direto:
kubectl create secret generic github-argocd-tokens \
  --from-literal=github-token="$GITHUB_TOKEN" \
  --from-literal=argocd-token="$ARGOCD_TOKEN" \
  -n argocd-poller --dry-run=client -o yaml > 04-secret-filled.yaml
```

## Verificar Instalação

```bash
# Namespace criado
kubectl get namespace argocd-poller

# Recursos no namespace
kubectl get all -n argocd-poller

# ConfigMaps
kubectl get configmap -n argocd-poller

# ServiceAccount
kubectl get serviceaccount -n argocd-poller

# RBAC
kubectl get role,rolebinding -n argocd -l app=github-poller

# CronJob agendado
kubectl get cronjob -n argocd-poller
```

## Monitorar Execuções

```bash
# Logs em tempo real
kubectl logs -n argocd-poller -l app=github-actions-poller -f

# Status dos jobs
kubectl get jobs -n argocd-poller --sort-by=.metadata.creationTimestamp

# Próxima execução
kubectl get cronjob -n argocd-poller github-actions-poller
```

## Alterar Schedule

### Via ConfigMap (recomendado)
```bash
kubectl patch configmap github-poller-config -n argocd-poller \
  -p '{"data":{"SCHEDULE":"*/5 * * * *"}}'
```

### Via manifestos
```bash
# Editar 05-configmap.yaml
kubectl apply -f manifests/05-configmap.yaml
```

## Troubleshooting

### Secret não encontrado
```bash
# Verificar se foi criado
kubectl get secret -n argocd-poller github-argocd-tokens

# Recriar se necessário
kubectl delete secret github-argocd-tokens -n argocd-poller
kubectl create secret generic github-argocd-tokens \
  --from-literal=github-token="$GITHUB_TOKEN" \
  --from-literal=argocd-token="$ARGOCD_TOKEN" \
  -n argocd-poller
```

### CronJob não cria jobs
```bash
# Verificar status
kubectl describe cronjob github-actions-poller -n argocd-poller

# Verificar events
kubectl get events -n argocd-poller --sort-by='.lastTimestamp'

# Testar manualmente
kubectl create job --from=cronjob/github-actions-poller test-manual -n argocd-poller
```

### Poller roda mas não dispara refresh
```bash
# Verificar logs
kubectl logs -n argocd-poller -l job-name=<job-name> --tail=50

# Verificar RBAC
kubectl auth can-i create applications/refresh \
  --as=system:serviceaccount:argocd:github-poller -n argocd
```

## Limpeza

```bash
# Deletar tudo
kubectl delete -f manifests/

# Ou via ArgoCD (se usar Application)
kubectl delete application argocd-poller -n argocd
```
