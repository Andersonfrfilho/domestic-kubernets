# Acesso remoto ao kubectl (dev → servidor)

Guia para configurar o `kubectl` no notebook de desenvolvimento para controlar
o cluster k3s que roda no notebook servidor (`192.168.3.60`).

---

## Pré-requisitos

- Notebooks na mesma rede local
- Servidor Ubuntu com k3s em execução
- `kubectl` instalado no notebook de desenvolvimento

---

## Passo 1 — Habilitar SSH no servidor

Acesse o servidor Ubuntu fisicamente (ou via monitor) e execute:

```bash
sudo systemctl enable ssh
sudo systemctl start ssh
sudo systemctl status ssh   # deve mostrar "active (running)"
```

> Se o pacote não estiver instalado:
> ```bash
> sudo apt update && sudo apt install -y openssh-server
> sudo systemctl enable ssh && sudo systemctl start ssh
> ```

---

## Passo 2 — Copiar o kubeconfig para o notebook de desenvolvimento

No **notebook de desenvolvimento** (macOS), execute:

```bash
# Copia o kubeconfig do servidor e substitui 127.0.0.1 pelo IP real
ssh miyazaki@192.168.3.60 "sudo cat /etc/rancher/k3s/k3s.yaml" \
  | sed 's/127\.0\.0\.1/192.168.3.60/g' \
  > ~/.kube/k3s-domestic.yaml
```

---

## Passo 3 — Configurar o contexto local

```bash
# Adiciona o contexto k3s ao kubeconfig ativo
export KUBECONFIG=~/.kube/config:~/.kube/k3s-domestic.yaml
kubectl config view --flatten > ~/.kube/config-merged
mv ~/.kube/config-merged ~/.kube/config

# Ativa o contexto do cluster doméstico
kubectl config use-context default   # ou o nome que aparecer no kubeconfig

# Torna a variável permanente (adicione ao ~/.zshrc se quiser persistir)
echo 'export KUBECONFIG=~/.kube/config' >> ~/.zshrc
```

---

## Passo 4 — Verificar o acesso

```bash
kubectl get nodes -n domestic
kubectl get pods -n domestic
```

Resultado esperado:

```
NAME       STATUS   ROLES                  AGE
miyazaki   Ready    control-plane,master   Xd
```

---

## Operações do dia a dia

```bash
# Ver todos os recursos no namespace domestic
kubectl get all -n domestic

# Logs de um deployment
kubectl logs -f deployment/worker -n domestic
kubectl logs -f deployment/api -n domestic

# Reiniciar um deployment
kubectl rollout restart deployment/worker -n domestic

# Executar SQL direto no PostgreSQL
kubectl exec -it -n domestic statefulset/postgres -- psql -U domestic -d domestic_postgres

# Port-forward para acesso local aos bancos
kubectl port-forward svc/postgres 5432:5432 -n domestic
kubectl port-forward svc/mongo 27017:27017 -n domestic
kubectl port-forward svc/redis 6379:6379 -n domestic
```

---

## Referência rápida — IPs e portas

| Serviço        | Host/IP          | Porta |
|----------------|------------------|-------|
| Servidor k3s   | `192.168.3.60`   | —     |
| k3s API        | `192.168.3.60`   | 6443  |
| SSH servidor   | `192.168.3.60`   | 22    |
| Ingress (MetalLB) | `192.168.1.200` | 80/443 |

---

## Solução de problemas

**`Unable to connect to the server`**
→ Verifique se a porta 6443 está acessível: `nc -zv 192.168.3.60 6443`

**`certificate signed by unknown authority`**
→ O kubeconfig copiado já inclui o CA do k3s — certifique-se de que o campo
`certificate-authority-data` não foi corrompido durante a cópia.

**SSH timeout**
→ Verifique se o serviço SSH está ativo no servidor:
`sudo systemctl status ssh`
