# Kubernetes — Domestic Stack

Manifests para rodar a stack completa na rede local com Ingress + MetalLB.

> **Arquitetura de ambientes**
>
> ```
> MacBook (dev)                     ASUS Ubuntu (servidor)
> ─────────────────────             ──────────────────────────────
> VS Code / editor                  k3s (Kubernetes)
> kubectl → LAN → Ubuntu            Docker + registry local
> skaffold dev                      Todos os serviços da stack
> domestic-backend-api/  ─build──►  registry:5000/domestic-api
> kubernetes/            ─apply──►  kubectl (via kubeconfig remoto)
> ```
>
> **Estrutura de repositórios**
>
> ```
> ~/Documents/personal/domestic/
> ├── kubernetes/              ← manifestos K8s (este repo)
> └── domestic-backend-api/   ← código-fonte da API
> ```

---

## Topologia de acesso

```
Rede local (LAN)
      │
      ▼
MetalLB IP (ex: 192.168.1.200)  ← atribuído automaticamente ao Ingress Controller
      │
      ▼
nginx Ingress Controller
      │
      ├── gateway.domestic.local  ──►  Kong (8000)  ──►  api:3000   [TODAS as chamadas de API]
      ├── keycloak.domestic.local ──►  Keycloak (8080)              [auth / login / OIDC]
      ├── api.domestic.local      ──►  API direta (3000)            [dev/debug, bypassa Kong]
      ├── bff.domestic.local      ──►  BFF (3001)                   [dev/debug, bypassa Kong]
      ├── worker.domestic.local   ──►  Worker /health + /admin/queues (3002)
      ├── cron.domestic.local     ──►  Cron /health + /jobs (3003)
      ├── storage.domestic.local  ──►  MinIO console (9001)
      ├── s3.domestic.local       ──►  MinIO API / S3 (9000)
      ├── queue.domestic.local    ──►  RabbitMQ management (15672)
      ├── grafana.domestic.local  ──►  Grafana (3000)
      ├── metrics.domestic.local  ──►  Prometheus (9090)
      ├── tracing.domestic.local  ──►  Jaeger UI (16686)
      └── argocd.domestic.local   ──►  ArgoCD UI (80)              [GitOps — sync automático]
```

---

## Dicionário de Credenciais e Conexões

Utilize estes hostnames para acesso administrativo e conexão entre serviços. No macOS, certifique-se de que o `minikube tunnel` esteja ativo.

### 1. Painéis Administrativos (Web)

| Serviço        | URL                                                                    | Usuário      | Senha            |
| :------------- | :--------------------------------------------------------------------- | :----------- | :--------------- |
| **Keycloak**   | [keycloak.domestic.local](http://keycloak.domestic.local)              | `domestic`   | `admin`          |
| **RabbitMQ**   | [queue.domestic.local](http://queue.domestic.local)                    | `domestic`   | `backendapi123`  |
| **MinIO**      | [storage.domestic.local](http://storage.domestic.local)                | `domestic`   | `minioadmin`     |
| **ArgoCD**     | [argocd.domestic.local](http://argocd.domestic.local)                  | `admin`      | _(ver seção 14)_ |
| **Kong Manager** | [kong-manager.domestic.local](http://kong-manager.domestic.local)    | via Keycloak | _(login no Keycloak → Kong Manager)_ |
| **Grafana**    | [grafana.domestic.local](http://grafana.domestic.local)                | `admin`      | _(ver grafana secret)_ |

### 2. Bancos de Dados e S3 (Conexão Direta)

Os bancos estão expostos via `LoadBalancer`, permitindo conexão direta pelos hostnames abaixo:

| Serviço        | Hostname / String de Conexão                                                                | Porta |
| :------------- | :------------------------------------------------------------------------------------------ | :---- |
| **PostgreSQL** | `postgresql://domestic:postgres1234@postgres.domestic.local:5432/backend_database_postgres` | 5432  |
| **MongoDB**    | `mongodb://mongo.domestic.local:27017/domestic_mongo`                                       | 27017 |
| **Redis**      | `redis://redis.domestic.local:6379/0`                                                       | 6379  |
| **MinIO (S3)** | `http://s3.domestic.local`                                                                  | 9000  |

### 3. Endpoints de API (Gateway)

- **Kong Proxy (HTTP):** `http://gateway.domestic.local/api/v1`
- **Keycloak Auth:** `http://keycloak.domestic.local/realms/domestic-backend`

---

## Pré-requisitos

### macOS (workstation de desenvolvimento)

```bash
brew install kubectl    # CLI do Kubernetes
brew install helm       # package manager (operators, charts)
brew install kubectx    # troca de namespace: kubens domestic
brew install k9s        # terminal UI — abre com: k9s -n domestic
brew install skaffold   # hot-reload de imagens (inner loop dev)
# minikube só se quiser rodar localmente no Mac também
brew install minikube
```

### Ubuntu (servidor — ASUS Vivobook i7-1255U / 16 GB)

Ver seção **"Setup Ubuntu Server (k3s)"** abaixo.

---

## Setup Ubuntu Server (k3s) ← ambiente de produção local

> **Por que k3s e não minikube no Ubuntu?**
> minikube é projetado para laptops de desenvolvimento (um usuário, uma máquina).
> k3s é um Kubernetes leve e production-grade: acesso remoto nativo, menos overhead (~512 MB vs ~1.5 GB),
> MetalLB e Ingress funcionam com IPs reais da LAN, e os dados persistem sem truques de VM.

### Especificações do servidor

| Item    | Valor                                    |
| ------- | ---------------------------------------- |
| Máquina | ASUS Vivobook X1605ZA                    |
| CPU     | i7-1255U (12 cores, boost 4.7 GHz)       |
| RAM     | 16 GB                                    |
| SO      | Ubuntu 22.04 LTS / 24.04 LTS             |
| Papel   | Kubernetes server (k3s) + registry local |

### 1. Ubuntu — preparar o sistema

```bash
# Atualizar pacotes
sudo apt update && sudo apt upgrade -y

# Dependências básicas
sudo apt install -y curl wget git vim net-tools nmap ufw

# Docker (necessário para buildar imagens e rodar o registry local)
curl -fsSL https://get.docker.com | sudo bash
sudo usermod -aG docker $USER
newgrp docker

# Verificar instalação
docker --version
```

### 2. Ubuntu — definir IP estático (fundamental para DNS da LAN)

O servidor precisa de IP fixo para que o DNS da rede aponte corretamente para ele.

```bash
# Descobrir o nome da interface de rede
ip link show
# Ex: enp3s0, eth0, wlan0

# Editar configuração Netplan
sudo vim /etc/netplan/01-netcfg.yaml
```

```yaml
# /etc/netplan/01-netcfg.yaml
network:
  version: 2
  ethernets:
    enp3s0: # substitua pelo nome da sua interface
      dhcp4: false
      addresses:
        - 192.168.1.100/24 # IP fixo desejado na sua sub-rede
      routes:
        - to: default
          via: 192.168.1.1 # IP do seu roteador/gateway
      nameservers:
        addresses:
          - 8.8.8.8
          - 1.1.1.1
```

```bash
sudo netplan apply

# Confirmar IP
ip addr show enp3s0
```

### 3. Ubuntu — instalar k3s

```bash
# Instalação com MetalLB e Traefik desabilitados
# (usaremos nginx ingress + MetalLB separados, igual aos manifestos já criados)
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="\
  --disable=traefik \
  --disable=servicelb \
  --write-kubeconfig-mode=644" sh -

# Verificar que k3s está rodando
sudo systemctl status k3s
kubectl get nodes
```

### 4. Ubuntu — criar alias `standard` para o StorageClass do k3s

Os manifestos usam `storageClassName: standard` (padrão do minikube).
No k3s, o provisioner se chama `local-path`. Este alias evita editar todos os YAMLs:

```bash
kubectl apply -f - <<'EOF'
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: standard
  annotations:
    storageclass.kubernetes.io/is-default-class: "false"
provisioner: rancher.io/local-path
reclaimPolicy: Delete
volumeBindingMode: WaitForFirstConsumer
EOF

# Onde os dados serão armazenados no disco
# /var/lib/rancher/k3s/storage/<namespace>/<pvc-name>/
```

### 5. Ubuntu — instalar MetalLB

```bash
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.5/config/manifests/metallb-native.yaml

kubectl wait --namespace metallb-system \
  --for=condition=ready pod \
  --selector=app=metallb \
  --timeout=90s

# Configurar o pool de IPs (edite o range para sua rede)
# Dica: use IPs ACIMA do IP estático do servidor para não conflitar
# Ex: servidor = 192.168.1.100 → pool = 192.168.1.200-192.168.1.210
kubectl apply -f metallb/metallb-config.yaml
```

### 6. Ubuntu — instalar nginx Ingress Controller

```bash
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  --set controller.service.type=LoadBalancer

# Aguardar o controller ficar pronto e receber IP do MetalLB
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=120s

# Ver o IP externo atribuído (ex: 192.168.1.200)
kubectl get svc -n ingress-nginx ingress-nginx-controller
```

### 8. Ubuntu — configurar firewall (UFW)

```bash
sudo ufw allow OpenSSH
sudo ufw allow 6443/tcp      # kubectl remoto (API server do k3s)
sudo ufw allow 80/tcp        # Ingress HTTP
sudo ufw allow 443/tcp       # Ingress HTTPS (futuro)
sudo ufw allow 5000/tcp      # registry Docker local
sudo ufw enable

sudo ufw status
```

### 9. macOS — configurar kubectl para apontar para o Ubuntu

```bash
# No Ubuntu: copiar o kubeconfig e trocar o IP
sudo cat /etc/rancher/k3s/k3s.yaml | \
  sed 's/127.0.0.1/192.168.1.100/g' > ~/k3s-domestic.yaml

# Transferir para o macOS (execute no macOS)
scp ubuntu-user@192.168.1.100:~/k3s-domestic.yaml ~/.kube/domestic-config

# Adicionar ao PATH do kubectl
export KUBECONFIG=~/.kube/config:~/.kube/domestic-config

# Mesclar os contexts permanentemente
kubectl config view --flatten > ~/.kube/config_merged
mv ~/.kube/config_merged ~/.kube/config

# Verificar contexts disponíveis
kubectl config get-contexts

# Alternar para o servidor Ubuntu
kubectl config use-context default   # ou o nome que aparecer para o k3s

# Testar acesso remoto
kubectl get nodes
```

### 10. macOS — construir e enviar imagem para o registry Ubuntu

```bash
# No macOS, na pasta domestic-backend-api/
cd ../domestic-backend-api

# Build da imagem apontando para o registry no Ubuntu
docker build -f Dockerfile.dev \
  -t 192.168.1.100:5000/domestic-api:latest \
  .

# Configurar Docker no macOS para aceitar registry inseguro
# Adicione em Docker Desktop → Settings → Docker Engine:
# {
#   "insecure-registries": ["192.168.1.100:5000"]
# }

# Push para o registry no Ubuntu
docker push 192.168.1.100:5000/domestic-api:latest

# Verificar que chegou
curl http://192.168.1.100:5000/v2/domestic-api/tags/list
```

> **Atenção:** Os manifestos `api/api.deployment.yaml` e `migrator/migrator.job.yaml`
> precisam ser atualizados para usar o registry local:
>
> ```yaml
> # Antes (daemon minikube)
> image: domestic-api:local
> imagePullPolicy: Never
>
> # Depois (registry local Ubuntu)
> image: 192.168.1.100:5000/domestic-api:latest
> imagePullPolicy: Always
> ```

### 11. Ubuntu — onde ficam os dados persistentes

```
/var/lib/rancher/k3s/storage/
└── pvc-<uid>_domestic_postgres-data-postgres-0/      ← PostgreSQL app
└── pvc-<uid>_domestic_postgres-keycloak-data-.../   ← PostgreSQL Keycloak
└── pvc-<uid>_domestic_mongo-data-mongo-0/           ← MongoDB
└── pvc-<uid>_domestic_redis-data-redis-0/           ← Redis
└── pvc-<uid>_domestic_rabbitmq-data-rabbitmq-0/     ← RabbitMQ
└── pvc-<uid>_domestic_minio-data-minio-0/           ← MinIO
```

```bash
# Ver todos os PVCs e onde estão montados
kubectl get pvc -n domestic
kubectl get pv -o wide

# Backup manual de emergência (copia direto do disco)
sudo cp -r /var/lib/rancher/k3s/storage/ /backup/k3s-$(date +%Y%m%d)/
```

### 12. Ubuntu — DNS para toda a LAN

```bash
# Instalar dnsmasq
sudo apt install -y dnsmasq

sudo tee /etc/dnsmasq.d/domestic.conf <<EOF
# Qualquer subdomínio de .domestic.local resolve para o IP do Ingress Controller
# Substitua pelo IP que o MetalLB atribuiu (kubectl get svc -n ingress-nginx)
address=/.domestic.local/192.168.1.200
EOF

sudo systemctl restart dnsmasq
sudo systemctl enable dnsmasq

# Nos outros dispositivos da rede: aponte o DNS primário para 192.168.1.100
# Windows: Configurações de rede → DNS manual → 192.168.1.100
# macOS:   Preferências → Rede → DNS → 192.168.1.100
# Android: Wi-Fi avançado → DNS-1 → 192.168.1.100
```

### 13. Ubuntu — Deploy da stack completa

Com o kubectl configurado no macOS apontando para o Ubuntu, os mesmos comandos do Quick Start funcionam:

```bash
# No macOS, na pasta kubernetes/
kubectl apply -f namespace.yaml
kubectl apply -f postgres/
# ... (mesmo fluxo do Quick Start abaixo)
```

Ou use o Skaffold com o registry remoto (ver seção Skaffold abaixo).

---

## Pré-requisitos (macOS)

| Ferramenta     | Versão mínima | Instalação              |
| -------------- | ------------- | ----------------------- |
| minikube       | v1.32+        | `brew install minikube` |
| kubectl        | v1.29+        | `brew install kubectl`  |
| helm           | v3.14+        | `brew install helm`     |
| k9s            | latest        | `brew install k9s`      |
| kubectx        | latest        | `brew install kubectx`  |
| skaffold       | latest        | `brew install skaffold` |
| Docker Desktop | v4+           | docker.com              |

```bash
# Instalar tudo de uma vez
brew install minikube kubectl helm k9s kubectx skaffold
```

---

## Setup macOS (minikube) — validar manifests localmente

> **Objetivo:** confirmar que todos os manifests K8s sobem sem erro **antes** de ir para o Ubuntu.
> Acesso via NodePort — sem MetalLB, sem DNS, sem `minikube tunnel`.
> BFF, Worker e Cron são pulados (sem código ainda).

### 1. Preencher os secrets

Substitua todos os `CHANGE_ME` usando como referência `../domestic-backend-api/.env.example`:

```bash
# Edite cada arquivo (os valores devem bater com o .env da API)
code postgres/postgres.secret.yaml
code postgres-keycloak/postgres-keycloak.secret.yaml
code rabbitmq/rabbitmq.secret.yaml
code minio/minio.secret.yaml
code keycloak/keycloak.secret.yaml
code api/api.secret.yaml
```

### 2. Subir a stack (script automático)

```bash
# Na pasta kubernetes/
./scripts/start-macos.sh

# Com observabilidade (Grafana, Prometheus, Loki, Jaeger)
./scripts/start-macos.sh --with-observability
```

O script faz tudo em ordem:

- inicia minikube (6 CPU, 8 GB RAM, driver Docker)
- habilita o addon `ingress`
- aponta Docker CLI para o daemon interno (`eval $(minikube docker-env)`)
- builda `domestic-api:local` no daemon do minikube
- aplica: namespace → secrets → configmaps → infra → keycloak → migrations → api → kong → ingress
- exibe URLs de acesso via NodePort ao final

### 3. Acessar os serviços (NodePort)

O script mostra o IP do minikube ao final. Acesse diretamente:

```bash
minikube ip   # ex: 192.168.49.2
```

| Serviço        | NodePort | URL                          |
| -------------- | -------- | ---------------------------- |
| Kong (gateway) | 30800    | `http://<minikube-ip>:30800` |
| API (direto)   | 30300    | `http://<minikube-ip>:30300` |
| Keycloak       | 30808    | `http://<minikube-ip>:30808` |
| MinIO console  | 30901    | `http://<minikube-ip>:30901` |
| RabbitMQ mgmt  | 30672    | `http://<minikube-ip>:30672` |

```bash
# Ou abrir direto no browser
minikube service kong                -n domestic
minikube service api                 -n domestic
minikube service keycloak-external   -n domestic
minikube service minio-console       -n domestic
minikube service rabbitmq-management -n domestic
```

### 4. Verificar se tudo está saudável

```bash
# Status geral de todos os pods
kubectl get pods -n domestic

# Acompanhar em tempo real
kubectl get pods -n domestic -w

# Interface interativa (recomendada)
k9s -n domestic
```

Todos os pods devem chegar em `Running` ou `Completed` (migrator). Se algum ficar em `CrashLoopBackOff` ou `Error`:

```bash
kubectl describe pod <nome-do-pod> -n domestic
kubectl logs <nome-do-pod> -n domestic
```

### 5. Rebuild da API durante testes

```bash
eval $(minikube docker-env)
docker build -f ../domestic-backend-api/Dockerfile.dev \
             -t domestic-api:local \
             ../domestic-backend-api
kubectl rollout restart deployment/api -n domestic
kubectl rollout status  deployment/api -n domestic
```

### 6. Limpar / reiniciar

```bash
minikube stop     # pausa — dados nos PVCs preservados
minikube start    # retoma do ponto anterior

minikube delete   # reset total — use para testar do zero
```

> **Preciso rodar `./scripts/start-macos.sh` de novo — preciso de clean?**
>
> **Não.** O script usa `kubectl apply` que é idempotente: recursos existentes ficam `unchanged`, alterados são atualizados automaticamente.
>
> **Exceções — quando é necessário deletar antes de reaplicar:**
>
> | Situação                                                    | Comando de limpeza                              |
> | ----------------------------------------------------------- | ----------------------------------------------- |
> | Mudou `storageClassName` num PVC já criado (campo imutável) | `kubectl delete pvc <nome> -n domestic`         |
> | Mudou `volumeClaimTemplates` num StatefulSet (imutável)     | `kubectl delete statefulset <nome> -n domestic` |
> | Quer banco de dados limpo (zero dados)                      | `minikube delete`                               |
> | Pod preso em `CrashLoopBackOff` após mudança de config      | `kubectl delete pod <nome> -n domestic`         |
>
> O Job do migrator é tratado automaticamente pelo script (`delete` + `apply` a cada execução).

### Validado no macOS → próximo passo: Ubuntu

Quando todos os pods estiverem `Running` e os endpoints responderem via NodePort, os manifests estão corretos. Siga a seção **"Setup Ubuntu Server (k3s)"** para o ambiente real.

---

## Estratégia de imagens — local vs registry

A API (`domestic-api`) é uma imagem customizada que precisa ser acessível pelo minikube.
As demais imagens (postgres, mongo, redis, etc.) são públicas e puxadas automaticamente do Docker Hub.

### Opção 1 — Daemon do minikube (uso individual, sem rede) ✅ recomendado para dev solo

O minikube tem seu próprio daemon Docker interno. Se você buildar a imagem **dentro** desse daemon,
ela fica disponível diretamente para os pods — sem precisar de nenhum registry.

```bash
# Aponta o Docker CLI para o daemon interno do minikube
eval $(minikube docker-env)

# Agora este build vai para DENTRO do minikube
cd ../domestic-backend-api
docker build -f Dockerfile.dev -t domestic-api:local .

# Voltar ao daemon local quando precisar (outro terminal ou ao sair da sessão)
eval $(minikube docker-env -u)
```

Nos manifestos, `imagePullPolicy: Never` garante que o Kubernetes nunca tente buscar a imagem
em nenhum registry — só usa o que já está no daemon local.

> **Atenção:** esse método não compartilha a imagem com outros notebooks na rede.
> Cada desenvolvedor precisa buildar na própria máquina.

---

### Opção 2 — `minikube image load` (alternativa sem `eval`)

Se você não quiser usar `eval`, pode fazer o build normalmente e depois carregar:

```bash
# Build no daemon local (sem eval)
cd ../domestic-backend-api
docker build -f Dockerfile.dev -t domestic-api:local .

# Envia a imagem para dentro do minikube
minikube image load domestic-api:local

# Verificar que chegou
minikube image ls | grep domestic-api
```

Funciona igual à Opção 1 — `imagePullPolicy: Never` nos manifestos.

---

### Opção 3 — Registry local na LAN ✅ recomendado para time / compartilhar na rede

Um container `registry:2` rodando em uma máquina da rede serve como registry privado para todos.
Ideal quando mais de um desenvolvedor precisa puxar a imagem `domestic-api`.

**Na máquina que vai servir o registry (uma vez só):**

```bash
docker run -d \
  --name domestic-registry \
  --restart always \
  -p 5000:5000 \
  registry:2

# Descubra o IP dessa máquina na rede local
ip route get 1 | awk '{print $7; exit}'   # Linux
ipconfig getifaddr en0                    # macOS
# Exemplo: 192.168.1.100
```

**Configurar o minikube para aceitar registry inseguro (sem TLS):**

```bash
# Passe o flag ao criar o minikube (só na primeira vez)
minikube start \
  --cpus=6 \
  --memory=8192 \
  --disk-size=40g \
  --insecure-registry="192.168.1.100:5000"
```

**Build e push para o registry local:**

```bash
cd ../domestic-backend-api
docker build -f Dockerfile.dev -t 192.168.1.100:5000/domestic-api:latest .
docker push 192.168.1.100:5000/domestic-api:latest
```

**Atualizar os manifestos para usar o registry local:**

Em `api/api.deployment.yaml` e `migrator/migrator.job.yaml`, substitua:

```yaml
# Antes (opção 1/2 — daemon local)
image: domestic-api:local
imagePullPolicy: Never

# Depois (opção 3 — registry local)
image: 192.168.1.100:5000/domestic-api:latest
imagePullPolicy: Always
```

**Qualquer outro notebook na rede** pode rodar o kubectl sem precisar buildar:

```bash
# Apenas aponte o minikube para o mesmo registry
minikube start --insecure-registry="192.168.1.100:5000"
# Os pods vão puxar a imagem automaticamente
```

---

### Opção 4 — Registry remoto (GitHub Container Registry / Docker Hub)

Para ambientes de CI/CD ou acesso fora da LAN:

```bash
# GitHub Container Registry (ghcr.io) — gratuito para repositórios públicos
docker build -f Dockerfile.dev -t ghcr.io/<org>/domestic-api:latest .
echo $GITHUB_TOKEN | docker login ghcr.io -u <user> --password-stdin
docker push ghcr.io/<org>/domestic-api:latest
```

Nos manifestos:

```yaml
image: ghcr.io/<org>/domestic-api:latest
imagePullPolicy: Always
```

Se o repositório for privado, crie um `imagePullSecret`:

```bash
kubectl create secret docker-registry ghcr-secret \
  --docker-server=ghcr.io \
  --docker-username=<user> \
  --docker-password=$GITHUB_TOKEN \
  -n domestic
```

E adicione ao deployment:

```yaml
spec:
  imagePullSecrets:
    - name: ghcr-secret
```

---

## Ferramentas recomendadas (instalar uma vez)

```bash
brew install kubectl    # CLI do Kubernetes
brew install minikube   # cluster local
brew install helm       # package manager (operators, charts)
brew install kubectx    # troca de namespace/contexto: kubens domestic
brew install k9s        # terminal UI — abre com: k9s -n domestic
brew install skaffold   # hot-reload de imagens (inner loop dev)
```

**k9s** substitui o kubectl no dia a dia — pods, logs, exec, restart, tudo interativo.

---

## Atualizar imagens da API em desenvolvimento (inner loop)

No `docker-compose`, o código é montado via volume e o NestJS watch mode recompila.
No Kubernetes isso precisa ser configurado explicitamente. Três opções:

### Opção A — Skaffold (recomendado) — rebuild + redeploy automático ao salvar arquivo

```bash
# Da pasta kubernetes/ — watch contínuo
eval $(minikube docker-env)
skaffold dev

# Ao salvar qualquer .ts em domestic-backend-api/src/ →
# Skaffold sincroniza o arquivo no pod → NestJS recompila automaticamente
# Sem rebuild completo da imagem a cada mudança
```

Com observabilidade:

```bash
skaffold dev --profile=observability
```

Deploy único (sem watch):

```bash
skaffold run
```

### Opção B — `minikube mount` + hostPath (replica exatamente o docker-compose)

**Terminal 1 — mantém o mount ativo (não feche durante o desenvolvimento):**

```bash
minikube mount \
  /Users/anderson.filho/Documents/personal/domestic/domestic-backend-api/src:/mnt/api-src
```

O deployment da API já está configurado para usar este volume quando o mount está ativo.
O NestJS watch mode detecta as mudanças e recompila dentro do pod — sem rebuild de imagem.

### Opção C — Rebuild manual (simples, sem ferramentas extras)

```bash
eval $(minikube docker-env)
docker build -f ../domestic-backend-api/Dockerfile.dev -t domestic-api:local ../domestic-backend-api
kubectl rollout restart deployment/api -n domestic
kubectl rollout status  deployment/api -n domestic
```

Demora ~30s a cada mudança (rebuild completo). Use apenas para mudanças pontuais.

---

## Quick Start (passo a passo completo)

> Todos os comandos `kubectl apply -f` devem ser executados **deste diretório**:
> `~/Documents/personal/domestic/kubernetes/`
>
> Os comandos que referenciam arquivos do projeto (`kong/kong.yml`, `keycloak-config/`, etc.)
> devem ser executados **do diretório da API**:
> `~/Documents/personal/domestic/domestic-backend-api/`

### 1. Iniciar o minikube

```bash
# Para o seu notebook (i7-1255U, 16 GB RAM)
minikube start --cpus=6 --memory=8192 --disk-size=40g

# Com registry local na LAN (Opção 3), adicione:
# --insecure-registry="192.168.1.100:5000"
```

### 2. Habilitar addons necessários

```bash
minikube addons enable ingress
minikube addons enable metallb

# Aguardar Ingress Controller estar pronto
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=120s
```

### 3. Buildar a imagem da API (Opção 1 — daemon minikube)

```bash
eval $(minikube docker-env)

cd ../domestic-backend-api
docker build -f Dockerfile.dev -t domestic-api:local .
cd ../kubernetes
```

### 4. Configurar MetalLB (IP range da sua rede local)

Edite `metallb/metallb-config.yaml` e ajuste o range de IPs livres na sua rede:

```bash
# Descubra IPs livres na sua rede
nmap -sn 192.168.1.0/24 | grep "report for"

# Edite o range (ex: 192.168.1.200-192.168.1.210)
# vim metallb/metallb-config.yaml

kubectl apply -f metallb/metallb-config.yaml
```

### 5. Criar namespace

```bash
kubectl apply -f namespace.yaml
```

### 6. Preencher os Secrets

Edite cada `*.secret.yaml` substituindo todos os `CHANGE_ME` pelos valores reais,
**usando os mesmos valores do `.env` da API**. Depois aplique:

```bash
kubectl apply -f postgres/postgres.secret.yaml
kubectl apply -f postgres-keycloak/postgres-keycloak.secret.yaml
kubectl apply -f rabbitmq/rabbitmq.secret.yaml
kubectl apply -f minio/minio.secret.yaml
kubectl apply -f keycloak/keycloak.secret.yaml
kubectl apply -f api/api.secret.yaml
kubectl apply -f observability/grafana/grafana.secret.yaml   # se for subir observabilidade
```

> Nunca commite secrets com valores reais. Adicione `*secret.yaml` ao `.gitignore`
> ou use [Sealed Secrets](https://github.com/bitnami-labs/sealed-secrets).

### 7. Criar ConfigMaps a partir dos arquivos do projeto

Execute **a partir do diretório da API** (`domestic-backend-api/`):

```bash
cd ../domestic-backend-api

# Configuração declarativa do Kong (roteamento, plugins)
kubectl create configmap kong-declarative-config \
  --from-file=kong.yml=./kong/kong.yml \
  -n domestic

# Realm do Keycloak (usuários, clientes, roles)
kubectl create configmap keycloak-realm-config \
  --from-file=domestic-backend-realm.json=./keycloak-config/domestic-backend-realm.json \
  -n domestic

# Prometheus scrape config
kubectl create configmap prometheus-scrape-config \
  --from-file=prometheus.yml=./monitoring/prometheus.yml \
  -n domestic

# Loki config
kubectl create configmap loki-config \
  --from-file=local-config.yaml=./monitoring/loki-config.yml \
  -n domestic

cd ../kubernetes
```

### 8. Deploy — infraestrutura (ordem importa)

```bash
# 1. Bancos de dados (StatefulSets com PVC)
kubectl apply -f postgres/
kubectl apply -f postgres-keycloak/
kubectl apply -f mongo/
kubectl apply -f redis/
kubectl apply -f rabbitmq/
kubectl apply -f minio/

# Aguardar todos os StatefulSets ficarem prontos
kubectl rollout status statefulset/postgres           -n domestic
kubectl rollout status statefulset/postgres-keycloak  -n domestic
kubectl rollout status statefulset/mongo              -n domestic
kubectl rollout status statefulset/redis              -n domestic
kubectl rollout status statefulset/rabbitmq           -n domestic
kubectl rollout status statefulset/minio              -n domestic

# 2. Keycloak (depende do postgres-keycloak)
kubectl apply -f keycloak/
kubectl rollout status deployment/keycloak -n domestic

# 3. Migração do banco (Job one-shot — aguarda postgres internamente)
kubectl apply -f migrator/migrator.job.yaml
kubectl wait --for=condition=complete job/migrator -n domestic --timeout=120s

# 4. API
kubectl apply -f api/
kubectl rollout status deployment/api -n domestic

# 5. Kong (depende de api + keycloak)
kubectl apply -f kong/
kubectl rollout status deployment/kong -n domestic
```

### 9. Deploy — Ingress (expor na rede local)

```bash
kubectl apply -f ingress/ingress-core.yaml           # Kong (gateway) + Keycloak
kubectl apply -f ingress/ingress-services.yaml       # API direta + placeholders bff/worker/cron
kubectl apply -f ingress/ingress-infra.yaml          # MinIO + RabbitMQ
```

### 10. Configurar DNS na rede local

```bash
# Descobrir o IP atribuído pelo MetalLB ao Ingress Controller
kubectl get svc -n ingress-nginx ingress-nginx-controller
# EXTERNAL-IP = ex: 192.168.1.200

# Adicionar ao /etc/hosts (esta máquina)
sudo tee -a /etc/hosts <<EOF
192.168.1.200  gateway.domestic.local
192.168.1.200  keycloak.domestic.local
192.168.1.200  api.domestic.local
192.168.1.200  storage.domestic.local
192.168.1.200  queue.domestic.local
192.168.1.200  bff.domestic.local
192.168.1.200  worker.domestic.local
192.168.1.200  cron.domestic.local
EOF

# Para compartilhar com toda a rede (dnsmasq / Pi-hole):
# address=/.domestic.local/192.168.1.200
```

### 11. Deploy — Observabilidade (opcional)

```bash
kubectl apply -f observability/prometheus/
kubectl apply -f observability/loki/
kubectl apply -f observability/grafana/
kubectl apply -f observability/jaeger/

# Ingress de observabilidade
kubectl apply -f ingress/ingress-observability.yaml

# DNS adicional
sudo tee -a /etc/hosts <<EOF
192.168.1.200  grafana.domestic.local
192.168.1.200  metrics.domestic.local
192.168.1.200  tracing.domestic.local
EOF
```

### 12. Deploy — Backups automáticos

```bash
kubectl apply -f backup/backup-postgres.cronjob.yaml
kubectl apply -f backup/backup-mongo.cronjob.yaml

# Verificar agendamento
kubectl get cronjob -n domestic

# Testar backup agora (sem esperar o horário agendado)
kubectl create job --from=cronjob/backup-postgres backup-pg-test -n domestic
kubectl logs job/backup-pg-test -n domestic -f
```

---

## Acessar os serviços

### Via Ingress (rede local — recomendado)

| URL                                                                                           | Serviço    | Descrição                         |
| --------------------------------------------------------------------------------------------- | ---------- | --------------------------------- |
| [gateway.domestic.local](http://gateway.domestic.local)                                       | Kong       | **Entry point de API — use este** |
| [keycloak.domestic.local](http://keycloak.domestic.local)                                     | Keycloak   | Admin console e login             |
| [api.domestic.local](http://api.domestic.local)                                               | API        | Acesso direto (bypassa Kong)      |
| [bff.domestic.local](http://bff.domestic.local)                                               | BFF        | Acesso direto (bypassa Kong)      |
| [worker.domestic.local/health](http://worker.domestic.local/health)                           | Worker     | Health check                      |
| [worker.domestic.local/admin/queues](http://worker.domestic.local/admin/queues)               | Worker     | Bull Board — filas                |
| [cron.domestic.local/health](http://cron.domestic.local/health)                               | Cron       | Health check                      |
| [cron.domestic.local/jobs](http://cron.domestic.local/jobs)                                   | Cron       | Trigger manual de jobs            |
| [storage.domestic.local](http://storage.domestic.local)                                       | MinIO      | Console de objetos                |
| [queue.domestic.local](http://queue.domestic.local)                                           | RabbitMQ   | Management UI                     |
| [grafana.domestic.local](http://grafana.domestic.local)                                       | Grafana    | Dashboards                        |
| [metrics.domestic.local](http://metrics.domestic.local)                                       | Prometheus | Métricas                          |
| [tracing.domestic.local](http://tracing.domestic.local)                                       | Jaeger     | Traces                            |
| [argocd.domestic.local](http://argocd.domestic.local)                                         | ArgoCD     | GitOps UI                         |
| [kong-manager.domestic.local](http://kong-manager.domestic.local)                             | Kong Manager | Dashboard built-in Kong 3.x (login via Keycloak) |

### Via NodePort (fallback / debug sem Ingress)

```bash
minikube service api                -n domestic --url
minikube service kong               -n domestic --url
minikube service keycloak-external  -n domestic --url
minikube service minio-console      -n domestic --url
minikube service rabbitmq-management -n domestic --url
minikube service grafana            -n domestic --url
```

| Serviço       | NodePort | URL direta                    |
| ------------- | -------- | ----------------------------- |
| api           | 30300    | `http://$(minikube ip):30300` |
| kong proxy    | 30800    | `http://$(minikube ip):30800` |
| kong admin    | 30801    | `http://$(minikube ip):30801` |
| keycloak      | 30808    | `http://$(minikube ip):30808` |
| minio console | 30901    | `http://$(minikube ip):30901` |
| rabbitmq mgmt | 30672    | `http://$(minikube ip):30672` |
| prometheus    | 30909    | `http://$(minikube ip):30909` |
| grafana       | 30030    | `http://$(minikube ip):30030` |
| jaeger UI     | 30686    | `http://$(minikube ip):30686` |

---

## Guia de Logs (Monitoramento)

Para acompanhar o que está acontecendo em cada serviço:

### 1. Serviços de Backend (Aplicação)

| Serviço    | Comando de Log                                      | Notas                               |
| :--------- | :-------------------------------------------------- | :---------------------------------- |
| **API**    | `kubectl logs -f deployment/api -n domestic -c api` | Container principal (pós-migration) |
| **BFF**    | `kubectl logs -f deployment/bff -n domestic`        | Agregador mobile/web                |
| **Worker** | `kubectl logs -f deployment/worker -n domestic`     | Processamento de filas              |
| **Cron**   | `kubectl logs -f deployment/cron -n domestic`       | Agendamento de jobs                 |

### 2. Infraestrutura (Bancos e Filas)

```bash
# PostgreSQL (Principal)
kubectl logs -f statefulset/postgres -n domestic

# PostgreSQL (Keycloak)
kubectl logs -f statefulset/postgres-keycloak -n domestic

# MongoDB
kubectl logs -f statefulset/mongo -n domestic

# RabbitMQ
kubectl logs -f statefulset/rabbitmq -n domestic

# Redis
kubectl logs -f statefulset/redis -n domestic
```

### 3. Gateway e Autenticação

```bash
# Kong (Gateway de API)
kubectl logs -f deployment/kong -n domestic

# Keycloak (Identity Provider)
kubectl logs -f deployment/keycloak -n domestic
```

### Dicas Úteis de Debug

- **Logs de Migrations (API):**
  ```bash
  kubectl logs deployment/api -n domestic -c migrate
  ```
- **Logs de múltiplos pods (por label):**
  ```bash
  kubectl logs -f -n domestic -l 'app in (api, bff, worker)' --tail=50
  ```
- **Verificar erros de subida (Eventos):**
  ```bash
  kubectl get events -n domestic --sort-by='.lastTimestamp'
  ```
- **K9s (Visual e Interativo):**
  A forma mais fácil de ver logs é usando o **k9s**. Digite `k9s -n domestic`, selecione o pod e aperte `l`.

---

## Operações do dia a dia

### Rebuild e redeploy da API

```bash
# Opção 1 — daemon minikube
eval $(minikube docker-env)
cd ../domestic-backend-api
docker build -f Dockerfile.dev -t domestic-api:local .
cd ../kubernetes
kubectl rollout restart deployment/api -n domestic

# Opção 3 — registry local
docker build -f Dockerfile.dev -t 192.168.1.100:5000/domestic-api:latest ../domestic-backend-api
docker push 192.168.1.100:5000/domestic-api:latest
kubectl rollout restart deployment/api -n domestic
```

### Re-executar migrations

```bash
kubectl delete job migrator -n domestic
kubectl apply -f migrator/migrator.job.yaml
kubectl wait --for=condition=complete job/migrator -n domestic --timeout=120s
```

### Ver logs

```bash
kubectl logs -f deployment/api       -n domestic
kubectl logs -f deployment/kong      -n domestic
kubectl logs -f statefulset/postgres -n domestic
```

### Migrations (initContainer)

As migrations rodam como **initContainer** no pod da API — antes do container principal subir, com log separado.

```bash
# Ver só o log das migrations
kubectl logs deployment/api -n domestic -c migrate

# Ver só o log da API (após migrations concluídas)
kubectl logs -f deployment/api -n domestic -c api

# Ver todos os containers do pod juntos
kubectl logs -f deployment/api -n domestic --all-containers
```

Acompanhar a progressão dos initContainers em tempo real:

```bash
kubectl describe pod -n domestic -l app=api
```

```
Init Containers:
  wait-for-postgres   ✓ Terminated (0)
  wait-for-mongo      ✓ Terminated (0)
  wait-for-redis      ✓ Terminated (0)
  wait-for-rabbitmq   ✓ Terminated (0)
  wait-for-minio      ✓ Terminated (0)
  wait-for-keycloak   ✓ Terminated (0)
  migrate             ✓ Terminated (0)  ← migrations aqui
Containers:
  api                 ✓ Running         ← app só sobe depois
```

Se a migration falhar, o pod não sobe e o Kubernetes reinicia automaticamente — sem afetar os logs da aplicação.

### Status geral

```bash
kubectl get all     -n domestic
kubectl get pvc     -n domestic
kubectl get ingress -n domestic
```

---

## Onde ficam os dados dos bancos

### No minikube (desenvolvimento local)

Os dados vivem dentro do VM do minikube em volumes `hostPath`:

```
Minikube VM: /tmp/hostpath-provisioner/domestic/<pvc-name>/
```

```bash
kubectl get pvc -n domestic           # lista as claims e seus status
kubectl get pv                        # lista os volumes físicos
kubectl describe pvc postgres-data-postgres-0 -n domestic
```

> `minikube stop` → suspende, **dados preservados**
> `minikube delete` → destrói tudo, **dados perdidos**

---

## Estratégia de Backup

### CronJobs implementados (este projeto)

| Job               | Horário (UTC) | Destino                   |
| ----------------- | ------------- | ------------------------- |
| `backup-postgres` | 02:00 diário  | `minio/backups/postgres/` |
| `backup-mongo`    | 02:30 diário  | `minio/backups/mongo/`    |

Retenção automática: arquivos com mais de 30 dias são removidos.

### Restaurar PostgreSQL

```bash
# 1. Configure o mc (MinIO client)
mc alias set local http://$(minikube ip):30901 <user> <pass>

# 2. Baixe o backup
mc cp local/backups/postgres/postgres_YYYY-MM-DD_02-00-00.sql.gz /tmp/

# 3. Restaure
gunzip -c /tmp/postgres_*.sql.gz | \
  kubectl exec -i statefulset/postgres -n domestic -- \
  psql -U <user> -d backend_database_postgres
```

### Restaurar MongoDB

```bash
mc cp local/backups/mongo/mongo_YYYY-MM-DD_02-30-00.archive.gz /tmp/

kubectl exec -i statefulset/mongo -n domestic -- \
  mongorestore --archive --gzip < /tmp/mongo_*.archive.gz
```

---

## Recomendações de banco para produção (escalabilidade)

### PostgreSQL — CloudNativePG Operator

```bash
helm repo add cnpg https://cloudnative-pg.github.io/charts
helm upgrade --install cnpg cnpg/cloudnative-pg -n cnpg-system --create-namespace
```

- `postgres-cluster-rw` → primary (escritas)
- `postgres-cluster-ro` → réplicas round-robin (leituras)
- WAL streaming contínuo para MinIO/S3 (PITR)

### MongoDB — ReplicaSet 3 nós

```bash
helm repo add mongodb https://mongodb.github.io/helm-charts
helm install community-operator mongodb/community-operator -n domestic
```

- 1 primary + 2 secondaries
- `readPreference=secondaryPreferred` para escalar leitura

### Redis — Sentinel

```bash
helm install redis bitnami/redis \
  --set architecture=replication \
  --set sentinel.enabled=true \
  --set replica.replicaCount=2 \
  -n domestic
```

### RabbitMQ — Cluster Operator (3 nós, quorum queues)

```bash
helm install rabbitmq bitnami/rabbitmq-cluster-operator -n domestic
```

---

## ArgoCD — GitOps visual (Ubuntu / k3s)

O ArgoCD monitora o repositório git e sincroniza automaticamente os manifests para o k3s.
Toda alteração no git é aplicada ao cluster sem precisar rodar `kubectl apply` manualmente.

```
Git push → ArgoCD detecta → aplica ao k3s → stack atualizada
```

### Topologia de acesso

```
http://argocd.domestic.local
      │
      ▼
nginx Ingress → argocd-server:80  (HTTP, sem TLS)
```

### 1. Atualizar a URL do repositório nos Application CRs

Antes de instalar, edite os arquivos com a URL real do seu repositório git.
Ou passe a URL direto para o script de instalação (ele substitui automaticamente).

```bash
# Substituição manual (se preferir)
GIT_URL="https://github.com/seu-org/kubernetes.git"
sed -i "s|CHANGE_ME_GIT_REPO_URL|$GIT_URL|g" argocd/applications/*.yaml
```

### 2. Instalar e configurar (script automático)

```bash
# Repositório público (HTTPS)
./scripts/install-argocd-ubuntu.sh https://github.com/seu-org/kubernetes.git

# Repositório privado (SSH)
./scripts/install-argocd-ubuntu.sh git@github.com:seu-org/kubernetes.git \
  --private-key ~/.ssh/id_rsa

# Sem registrar repo agora (registra manualmente depois)
./scripts/install-argocd-ubuntu.sh
```

O script faz tudo em ordem:

1. Instala ArgoCD no namespace `argocd`
2. Configura modo HTTP (`argocd-params.configmap.yaml`)
3. Aplica o Ingress (`argocd.domestic.local`)
4. Recupera e exibe a senha inicial do admin
5. Instala o `argocd` CLI (se não estiver instalado)
6. Registra o repositório git
7. Substitui `CHANGE_ME_GIT_REPO_URL` nos Application CRs
8. Aplica o AppProject + 4 Applications (waves 1-4)

### 3. Acessar a UI

Após o script:

```
URL:      http://argocd.domestic.local
Usuário:  admin
Senha:    (exibida ao final do script)
```

```bash
# Recuperar a senha a qualquer momento
kubectl get secret argocd-initial-admin-secret \
  -n argocd -o jsonpath="{.data.password}" | base64 -d && echo

# Trocar a senha após o primeiro login
argocd login argocd.domestic.local --username admin --insecure --grpc-web
argocd account update-password
```

### 4. DNS — adicionar ao dnsmasq

O wildcard `*.domestic.local` já cobre `argocd.domestic.local` automaticamente.
Nenhuma configuração adicional de DNS é necessária se o dnsmasq já estiver rodando.

```bash
# Confirmar que o endereço resolve
nslookup argocd.domestic.local 192.168.1.100
```

### 5. Estrutura dos Applications (sync-waves)

| Application              | Wave | Gerencia                                        |
| ------------------------ | ---- | ----------------------------------------------- |
| `domestic-infra`         | 1    | postgres, mongo, redis, rabbitmq, minio         |
| `domestic-auth`          | 2    | postgres-keycloak, keycloak                     |
| `domestic-services`      | 3    | migrator, api, kong, bff, worker, cron, ingress |
| `domestic-observability` | 4    | prometheus, grafana, loki, jaeger               |

O ArgoCD respeita a ordem: wave 1 fica `Healthy` antes de wave 2 iniciar, e assim por diante.

### 6. Comandos úteis do dia a dia

```bash
# Listar todos os Applications e seu status
argocd app list
kubectl get applications -n argocd

# Forçar sync imediato (sem esperar o poll de 3 min)
argocd app sync domestic-infra
argocd app sync domestic-auth
argocd app sync domestic-services

# Ver diff entre git e cluster (o que vai mudar)
argocd app diff domestic-services

# Ver logs de sync
argocd app logs domestic-services

# Ver detalhes de um Application
argocd app get domestic-infra
```

### 7. Fluxo GitOps (depois de instalado)

```bash
# 1. Edite um manifest localmente (ex: aumentar réplicas da API)
vim api/api.deployment.yaml

# 2. Commit e push
git add api/api.deployment.yaml
git commit -m "chore: scale api to 3 replicas"
git push

# 3. ArgoCD detecta a mudança em até 3 min e aplica automaticamente
# — acompanhe em http://argocd.domestic.local
# — ou force sync imediato: argocd app sync domestic-services
```

### 8. Instalação manual (sem script)

Se preferir instalar passo a passo:

```bash
# Instalar ArgoCD
kubectl create namespace argocd
kubectl apply -n argocd \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Aguardar
kubectl wait --namespace argocd \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/name=argocd-server \
  --timeout=180s

# Modo HTTP
kubectl apply -f argocd/argocd-params.configmap.yaml
kubectl rollout restart deployment/argocd-server -n argocd

# Ingress
kubectl apply -f argocd/argocd-ingress.yaml

# Senha inicial
kubectl get secret argocd-initial-admin-secret \
  -n argocd -o jsonpath="{.data.password}" | base64 -d && echo

# AppProject + Applications
kubectl apply -f argocd/applications/app-project.yaml
kubectl apply -f argocd/applications/app-infra.yaml
kubectl apply -f argocd/applications/app-auth.yaml
kubectl apply -f argocd/applications/app-services.yaml
kubectl apply -f argocd/applications/app-observability.yaml
```

---

## Troubleshooting

```bash
# Pod não sobe
kubectl describe pod <nome> -n domestic

# PVC preso em Pending
kubectl describe pvc <nome> -n domestic
kubectl get storageclass

# Ingress não roteando
kubectl describe ingress -n domestic
kubectl logs -n ingress-nginx deployment/ingress-nginx-controller

# Imagem não encontrada (ErrImageNeverPull)
# → você está usando Opção 1 mas não buildou com eval $(minikube docker-env)
minikube image ls | grep domestic-api
eval $(minikube docker-env) && docker build -f Dockerfile.dev -t domestic-api:local ../domestic-backend-api

# Resetar o cluster do zero
minikube delete
minikube start --cpus=6 --memory=8192 --disk-size=40g
```

---

## Suspender / Parar

```bash
minikube stop     # suspende — dados nos PVCs preservados
minikube start    # retoma exatamente do ponto anterior

minikube delete   # destrói tudo — use só para reset completo
```
