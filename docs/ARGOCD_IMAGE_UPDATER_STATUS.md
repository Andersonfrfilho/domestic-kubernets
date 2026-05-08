# Status da Instalação - ArgoCD Image Updater

## ✅ Concluído

- [x] ArgoCD Image Updater instalado no cluster
- [x] Namespace `argocd-image-updater` criado
- [x] RBAC configurado (ClusterRole + RoleBinding)
- [x] ConfigMap atualizado com endereço correto do ArgoCD
- [x] Todas as applications anotadas (API, BFF, Worker, Cron)
- [x] Documentação criada

## ⚠️ Próximas Ações

### 1. Gerar GitHub Token (OBRIGATÓRIO)

Sem o token GitHub, o Image Updater não consegue fazer push das atualizações no repo.

**Siga:** `docs/GITHUB_TOKEN_SETUP.md`

Resumido:
```bash
# Gere em: https://github.com/settings/tokens/new
# Permissões: repo + read:packages

# Crie o secret:
kubectl create secret generic git-creds \
  --from-literal=username=seu-usuario \
  --from-literal=password=seu-token \
  -n argocd-image-updater
```

### 2. Verificar Funcionamento

Após criar o secret:

```bash
# Logs do Image Updater
kubectl logs -n argocd-image-updater -f deployment/argocd-image-updater

# Procure por:
# - "scanning image: ghcr.io/..." = está monitorando ✓
# - "Writing config in git" = atualizou manifests ✓
# - "authentication failed" = erro de token ✗
```

## 🔄 Fluxo de Sincronização

1. **GitHub Actions compila a imagem**
   ```
   Repo: domestic-backend-api/bff/worker/cron
   Action: Compila código → Docker image
   Push: Para GHCR (ghcr.io/andersonfrfilho/...)
   ```

2. **ArgoCD Image Updater detecta**
   ```
   Monitora: GHCR a cada 2 minutos
   Encontra: Nova imagem com tag "main"
   ```

3. **Image Updater atualiza Git**
   ```
   Repo: domestic-kubernets
   Muda: Tag da imagem nos deployments
   Commit: "chore: update container images [skip ci]"
   ```

4. **ArgoCD sincroniza**
   ```
   Detecta: Mudança no repo
   Aplica: Novos manifestos no K8s
   Result: Pod restart com nova imagem
   ```

## 📊 Aplicações Monitoradas

| App | Image | Monitora | Atualiza |
|-----|-------|----------|----------|
| API | ghcr.io/andersonfrfilho/domestic-backend-api | ✓ | `api/api.deployment.yaml` |
| BFF | ghcr.io/andersonfrfilho/domestic-backend-bff | ✓ | `bff/bff.deployment.yaml` |
| Worker | ghcr.io/andersonfrfilho/domestic-backend-worker | ✓ | `worker/worker.deployment.yaml` |
| Cron | ghcr.io/andersonfrfilho/domestic-backend-cron | ✓ | `cron/cron.deployment.yaml` |

## 🐛 Troubleshooting

### "applications=0" nos logs

**Problema:** Image Updater não consegue ler as applications

**Solução:**
```bash
# Verificar RBAC
kubectl auth can-i list applications \
  --as=system:serviceaccount:argocd-image-updater:argocd-image-updater

# Deve retornar: yes
```

### "authentication failed"

**Problema:** Token GitHub inválido ou sem permissões

**Solução:**
- Regenerar token em: https://github.com/settings/tokens
- Verificar permissões: `repo` + `read:packages`
- Atualizar secret

### "connection refused"

**Problema:** Não consegue conectar ao ArgoCD

**Solução:**
```bash
# Verificar conectividade
kubectl exec -it -n argocd-image-updater \
  deployment/argocd-image-updater -- \
  nslookup argocd-server.argocd

# Deve resolver para IP do serviço
```

## 📝 Notas

- Image Updater tenta sincronizar a cada **2 minutos**
- Commitsa mensagem: `chore: update container images [skip ci]`
- Não dispara builds do GitHub Actions (por causa do `[skip ci]`)
- Atualiza apenas a tag, sem trocar a imagem base

## 🔐 Segurança

- Token fica em Secret do K8s (encriptado em etcd)
- Pode ser revogado a qualquer momento
- Image Updater só lê repositórios públicos (GHCR)
- Escreve apenas no branch `main` do `domestic-kubernets`
