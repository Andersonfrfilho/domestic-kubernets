# Acesso à Infra de Outros Dispositivos da Rede

## Como funciona

O dnsmasq na máquina host resolve `*.domestic.local → 192.168.3.203` (IP do Ingress Controller via MetalLB).
Outros dispositivos na rede precisam usar a máquina host como DNS primário para acessar os serviços.

**IPs da máquina host:**
- `192.168.3.60` (Ethernet)
- `192.168.3.8` (Wi-Fi)

**IP do Ingress Controller (MetalLB):** `192.168.3.203`

---

## Configuração única (executar uma vez na máquina host)

Por padrão o dnsmasq sobe com `--local-service`, que recusa queries vindas de outros dispositivos.
Execute os comandos abaixo para corrigir:

```bash
# 1. Adicionar upstream DNS ao config do dnsmasq
echo 'server=8.8.8.8
server=1.1.1.1' | sudo tee -a /etc/dnsmasq.d/domestic.conf

# 2. Remover --local-service via override do systemd
sudo mkdir -p /etc/systemd/system/dnsmasq.service.d
sudo tee /etc/systemd/system/dnsmasq.service.d/override.conf << 'EOF'
[Service]
ExecStart=
ExecStart=/usr/sbin/dnsmasq -x /run/dnsmasq/dnsmasq.pid -u dnsmasq -7 /etc/dnsmasq.d,.dpkg-dist,.dpkg-old,.dpkg-new
EOF

# 3. Recarregar e reiniciar
sudo systemctl daemon-reload
sudo systemctl restart dnsmasq

# 4. Verificar que resolve domínios externos normalmente
nslookup google.com 192.168.3.60

# 5. Verificar que resolve domínios internos
nslookup argocd.domestic.local 192.168.3.60
```

---

## Configuração nos dispositivos clientes

### Android / iOS
Configurações → Wi-Fi → segurar na rede → DNS manual:
- **DNS 1:** `192.168.3.60`
- **DNS 2:** `8.8.8.8`

### Windows
Painel de Controle → Central de Rede → Adaptador → Propriedades → IPv4:
- **DNS preferencial:** `192.168.3.60`
- **DNS alternativo:** `8.8.8.8`

### macOS

> **Atenção:** macOS intercepta domínios `.local` via mDNS/Bonjour **antes** de consultar o DNS configurado.
> É necessário criar um resolver específico para contornar esse comportamento.

```bash
# 1. Configurar DNS nas preferências de rede:
networksetup -setdnsservers Wi-Fi 192.168.3.60 8.8.8.8
# ou para Ethernet:
networksetup -setdnsservers Ethernet 192.168.3.60 8.8.8.8

# 2. Criar resolver para bypassar o mDNS no domínio .local
#    (IMPORTANTE: não usar indentação dentro do heredoc)
sudo mkdir -p /etc/resolver
sudo tee /etc/resolver/local << 'EOF'
nameserver 192.168.3.60
port 53
EOF

# 3. Limpar cache DNS:
sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder
```

#### Diagnóstico (rodar no Mac para verificar)

```bash
# Ver qual DNS está configurado
networksetup -getdnsservers Wi-Fi
networksetup -getdnsservers Ethernet

# Ver se o resolver foi criado
cat /etc/resolver/local

# Testar resolução DNS apontando direto para o host Ubuntu
nslookup argocd.domestic.local 192.168.3.60

# Ver o que o Mac está resolvendo (deve retornar 192.168.3.203)
dscacheutil -q host -a name argocd.domestic.local

# Testar HTTP diretamente pelo IP (sem DNS) — confirma que o serviço responde
curl -s -o /dev/null -w "%{http_code}" http://192.168.3.203 -H "Host: argocd.domestic.local"
# Esperado: 200
```

Se `dscacheutil` retornar `192.168.3.203`, o DNS está funcionando e o browser deve abrir normalmente.

### Linux
```bash
# Temporário (sessão atual)
resolvectl dns <interface> 192.168.3.60 8.8.8.8

# Permanente via /etc/resolv.conf
echo "nameserver 192.168.3.60" | sudo tee /etc/resolv.conf
echo "nameserver 8.8.8.8" | sudo tee -a /etc/resolv.conf
```

---

## Serviços disponíveis

| Serviço | URL | Credenciais |
|---------|-----|-------------|
| ArgoCD | http://argocd.domestic.local | `anderson.filho` / `10203040` (via Keycloak) |
| Grafana | http://grafana.domestic.local | `anderson.filho` / `10203040` (via Keycloak) |
| Keycloak | http://keycloak.domestic.local | `anderson.filho` / `10203040` |
| RabbitMQ | http://queue.domestic.local | `anderson.filho` / `10203040` (via Keycloak) |
| MinIO | http://storage.domestic.local | `anderson.filho` / `10203040` (via Keycloak) |
| Kong Gateway | http://kong.domestic.local | — |
| API (direto) | http://api.domestic.local | — |

---

## Teste de conectividade

```bash
# Da máquina host ou de outro dispositivo após configurar DNS:
curl -s -o /dev/null -w "%{http_code}" http://argocd.domestic.local
# Esperado: 200

curl -s -o /dev/null -w "%{http_code}" http://keycloak.domestic.local/realms/domestic-backend
# Esperado: 200
```
