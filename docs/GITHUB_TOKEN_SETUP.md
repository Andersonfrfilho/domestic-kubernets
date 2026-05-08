# Setup do Token GitHub para ArgoCD Image Updater

## Por que precisa de um token?

O ArgoCD Image Updater precisa fazer push de commits no repo `domestic-kubernets` quando detecta novas imagens. Para isso, precisa autenticar no GitHub.

## Gerar o Token

1. Acesse: https://github.com/settings/tokens/new
2. Nome: `ArgoCD Image Updater`
3. **Permissões necessárias:**
   - ✅ `repo` (full control of private repositories)
   - ✅ `read:packages` (read packages from container registry)
4. Clique em "Generate token"
5. **Copie o token** (só aparece uma vez!)

## Criar o Secret no Kubernetes

```bash
kubectl create secret generic git-creds \
  --from-literal=username=seu-usuario-github \
  --from-literal=password=seu-token-aqui \
  -n argocd-image-updater
```

Exemplo:
```bash
kubectl create secret generic git-creds \
  --from-literal=username=Andersonfrfilho \
  --from-literal=password=ghp_xxxxxxxxxxxxxxxxxxxxxxxxxxxxx \
  -n argocd-image-updater
```

## Verificar se funcionou

```bash
# Logs do Image Updater
kubectl logs -n argocd-image-updater -f deployment/argocd-image-updater

# Procure por:
# - "scanning image" = está ok
# - "Writing config in git" = funcionou!
# - "authentication failed" = token errado ou sem permissões
```

## Se Precisar Atualizar o Token

```bash
kubectl delete secret git-creds -n argocd-image-updater
kubectl create secret generic git-creds \
  --from-literal=username=seu-usuario-github \
  --from-literal=password=novo-token \
  -n argocd-image-updater
```

## Segurança

⚠️ **Importante:**
- O token fica em um Secret do Kubernetes (encriptado em etcd)
- Pode ser revogado a qualquer momento em: https://github.com/settings/tokens
- Se vazar, revogue imediatamente
- Token morre em 30 dias se não o usar na geração (ajuste na UI do GitHub)
