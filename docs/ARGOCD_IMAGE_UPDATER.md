# ArgoCD Image Updater - Sincronização Automática de Imagens

## Visão Geral

Sistema de sincronização automática que mantém as imagens Docker dos microserviços atualizadas no Kubernetes sem intervenção manual.

**Fluxo:**
```
GitHub Actions (cloud)
  ↓ compila e faz push
GHCR (github registry)
  ↓ ArgoCD Image Updater detecta nova imagem
GitHub repo (domestic-kubernets)
  ↓ atualiza manifests automaticamente
ArgoCD
  ↓ sincroniza mudanças
Kubernetes local
  ↓ puxa nova imagem e restart pods
```

## Serviços Sincronizados

| Serviço | Repository | Registry | Application |
|---------|-----------|----------|-------------|
| API | domestic-backend-api | ghcr.io/andersonfrfilho/domestic-backend-api | app-api |
| BFF | domestic-backend-bff | ghcr.io/andersonfrfilho/domestic-backend-bff | app-bff |
| Worker | domestic-backend-worker | ghcr.io/andersonfrfilho/domestic-backend-worker | app-worker |
| Cron | domestic-backend-cron | ghcr.io/andersonfrfilho/domestic-backend-cron | app-cron |

## Instalação

### 1. Namespace e Deployment

```bash
kubectl create namespace argocd-image-updater
kubectl apply -n argocd-image-updater -f \
  https://raw.githubusercontent.com/argoproj-labs/argocd-image-updater/stable/manifests/install.yaml
```

Verificar se está rodando:
```bash
kubectl get pods -n argocd-image-updater
```

### 2. Secret para Autenticação GitHub

Criar token em: https://github.com/settings/tokens
- Permissões necessárias: `repo`, `read:packages`

```bash
kubectl create secret generic git-creds \
  --from-literal=username=seu-usuario-github \
  --from-literal=password=seu-token-github \
  -n argocd-image-updater
```

### 3. ConfigMap com Configuração

```bash
kubectl apply -n argocd-image-updater -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-image-updater-config
data:
  log.level: info
  git.commit.message: "chore: update container images"
  git.commit.author.name: "ArgoCD Image Updater"
  git.commit.author.email: "argocd-image-updater@domestic.local"
EOF
```

## Configuração por Aplicação

Cada Application no ArgoCD precisa de anotações para que o Image Updater saiba quais imagens monitorar:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: domestic-api
  namespace: argocd
  annotations:
    # Lista de imagens a monitorar (nome=registry/imagem)
    argocd-image-updater.argoproj.io/image-list: api=ghcr.io/andersonfrfilho/domestic-backend-api
    
    # Estratégia de atualização (latest, semver, digest, etc)
    argocd-image-updater.argoproj.io/api.update-strategy: latest
    
    # Quais tags permitir (regex)
    argocd-image-updater.argoproj.io/api.allow-tags: regexp:^main$
    
    # Branch Git para atualizar
    argocd-image-updater.argoproj.io/git-branch: main
```

## Monitoramento

### Logs do Image Updater

```bash
kubectl logs -n argocd-image-updater -f deployment/argocd-image-updater
```

Procurar por:
- `scanning image` - está monitorando
- `no new image found` - nenhuma atualização
- `Writing config in git` - atualizou manifests
- `ERROR` - erro na sincronização

### Status das Applications

```bash
# Ver todas applications
kubectl get applications -n argocd

# Ver detalhes de uma
kubectl describe application domestic-api -n argocd

# Ver logs do ArgoCD
kubectl logs -n argocd -f deployment/argocd-application-controller
```

## Troubleshooting

### Erro: "no permission to update git repository"

**Problema:** Token GitHub sem permissões suficientes
**Solução:** 
- Regenerar token com permissões `repo` (full control of private repositories)
- Atualizar secret: `kubectl delete secret git-creds -n argocd-image-updater` + recrear

### Erro: "image not found in registry"

**Problema:** GitHub Actions ainda não fez push da imagem
**Solução:**
- Verificar GitHub Actions: https://github.com/Andersonfrfilho/{repo}/actions
- Esperar build completar
- Image Updater tenta a cada 2 minutos

### Logs não estão aparecendo

**Problema:** Pod não está rodando
**Solução:**
```bash
kubectl describe pod -n argocd-image-updater $(kubectl get pods -n argocd-image-updater -o name)
kubectl logs -n argocd-image-updater -p $(kubectl get pods -n argocd-image-updater -o name)
```

## Desabilitar Atualização Manual

Se precisa desabilitar temporariamente as atualizações automáticas, remover as anotações da Application:

```bash
kubectl annotate application domestic-api \
  argocd-image-updater.argoproj.io/image-list- \
  argocd-image-updater.argoproj.io/api.update-strategy- \
  -n argocd --overwrite
```

Para reabilitar, adicionar as anotações novamente.

## Fluxo Manual (Se Preciso)

Se o Image Updater não funcionar, trigger manualmente:

```bash
# Forçar refresh da application
argocd app diff domestic-api

# Forçar sincronização
argocd app sync domestic-api

# Ou via kubectl
kubectl patch application domestic-api -n argocd -p \
  '{"spec":{"source":{"helm":{"parameters":[{"name":"image.tag","value":"newTag"}]}}}}' \
  --type merge
```

## Referências

- [ArgoCD Image Updater Docs](https://argocd-image-updater.readthedocs.io/)
- [GitHub Token Creation](https://github.com/settings/tokens)
- [GHCR Documentation](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry)
