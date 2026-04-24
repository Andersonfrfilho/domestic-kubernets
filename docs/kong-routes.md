# Kong — Rotas, Testes e Como Expor Novos Endpoints

## Endereços de acesso (macOS)

O cluster roda no Ubuntu (`192.168.3.60`). Dois modos de acesso do Mac:

| Modo | Base URL | Quando usar |
|---|---|---|
| **NodePort (sem DNS)** | `http://192.168.3.60:30800` | Sempre funciona, sem configuração |
| **DNS (domínio)** | `http://gateway.domestic.local` | Após configurar DNS — ver `docs/network-access.md` |

Todos os exemplos abaixo usam variáveis para facilitar a troca:

```bash
# Cole no terminal antes de testar — escolha um dos dois:

# Opção A — NodePort (sem DNS)
KONG="http://192.168.3.60:30800"
KEYCLOAK="http://192.168.3.60:30808"   # Keycloak NodePort

# Opção B — DNS configurado
KONG="http://gateway.domestic.local"
KEYCLOAK="http://keycloak.domestic.local"
```

---

## Rotas ativas no Kong

> Arquivo de configuração declarativa: `domestic-backend-api/kong/kong.yml`
> Kong está em modo **DB-less** — toda config vem do arquivo, o Manager é read-only.

| Rota | Método | Path Kong | Upstream real | Plugins |
|---|---|---|---|---|
| `auth-authorize` | `GET` | `/auth/authorize` | Keycloak `/realms/domestic-backend/protocol/openid-connect/auth` | `request-transformer`, `cors` |
| `auth-token` | `POST` | `/auth/token` | Keycloak `/realms/domestic-backend/protocol/openid-connect/token` | `request-transformer` (injeta `client_id` + `client_secret`), `cors` |

> **BFF** (`/api/v1`) está comentado no `kong.yml` — aguardando o serviço BFF estar pronto.

---

## Testes rápidos — verificar que o Kong responde

```bash
# Smoke test: Kong proxy up?
curl -s -o /dev/null -w "Kong proxy: %{http_code}\n" $KONG/

# Admin API up? (via Ingress)
curl -s -o /dev/null -w "Kong admin: %{http_code}\n" http://192.168.3.60:30801/status
# Ou via DNS: curl -s http://kong-admin.domestic.local/status | python3 -m json.tool

# Ver todas as rotas declaradas
curl -s http://192.168.3.60:30801/routes | python3 -c "
import sys, json
d = json.load(sys.stdin)
for r in d['data']:
    print(r['name'], '-', r.get('methods'), r.get('paths'))
"
```

---

## Rota 1 — `GET /auth/authorize` (Inicia fluxo PKCE)

O Kong injeta `client_id=domestic-backend-bff` e redireciona para o Keycloak.

```bash
# Deve retornar 302 → redirect para keycloak.domestic.local/login
curl -v "$KONG/auth/authorize" \
  --get \
  --data-urlencode "response_type=code" \
  --data-urlencode "scope=openid profile email" \
  --data-urlencode "redirect_uri=http://localhost:3000/callback" \
  --data-urlencode "state=test-state-123" \
  --data-urlencode "code_challenge=dummychallenge" \
  --data-urlencode "code_challenge_method=S256" \
  2>&1 | grep -E "< HTTP|Location:"
```

Saída esperada:
```
< HTTP/1.1 302 Found
< Location: http://keycloak.domestic.local/realms/domestic-backend/protocol/openid-connect/auth?...&client_id=domestic-backend-bff&...
```

---

## Rota 2 — `POST /auth/token` (Troca code por tokens)

O Kong injeta `client_id` e `client_secret` antes de encaminhar ao Keycloak.

```bash
# Com um code real (obtido após login PKCE), o retorno é JSON com os tokens.
# Sem code válido, o Keycloak retorna erro descritivo — confirma que a rota existe.
curl -s -X POST "$KONG/auth/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=authorization_code" \
  -d "code=COLE_O_CODE_AQUI" \
  -d "redirect_uri=http://localhost:3000/callback" \
  -d "code_verifier=COLE_O_VERIFIER_AQUI" \
  | python3 -m json.tool
```

Saída esperada (sem code válido):
```json
{
    "error": "invalid_grant",
    "error_description": "Code not valid"
}
```

---

## Fluxo PKCE completo (obter access_token real)

### Passo 1 — Gerar code_verifier e code_challenge

```bash
# Gerar code_verifier (string aleatória base64url, 43+ chars)
CODE_VERIFIER=$(python3 -c "
import secrets, base64
raw = secrets.token_bytes(32)
print(base64.urlsafe_b64encode(raw).rstrip(b'=').decode())
")

# Derivar code_challenge (SHA-256 do verifier, base64url)
CODE_CHALLENGE=$(python3 -c "
import sys, hashlib, base64
v = '$CODE_VERIFIER'
digest = hashlib.sha256(v.encode()).digest()
print(base64.urlsafe_b64encode(digest).rstrip(b'=').decode())
")

echo "verifier : $CODE_VERIFIER"
echo "challenge: $CODE_CHALLENGE"
```

### Passo 2 — Abrir a URL de authorize no browser

```bash
# Montar a URL e abrir no browser (macOS)
AUTHORIZE_URL="$KONG/auth/authorize?response_type=code&scope=openid+profile+email&redirect_uri=http://localhost:3000/callback&state=test&code_challenge=$CODE_CHALLENGE&code_challenge_method=S256"

echo "Abra no browser:"
echo "$AUTHORIZE_URL"
open "$AUTHORIZE_URL"   # ou cole manualmente no Chrome/Safari
```

Faça login com `anderson.filho` / `10203040`. Após o login, o browser redireciona para:
```
http://localhost:3000/callback?code=AUTH_CODE_AQUI&state=test
```

Copie o valor de `code=`.

### Passo 3 — Trocar code por tokens

```bash
AUTH_CODE="COLE_O_CODE_DO_REDIRECT_AQUI"

curl -s -X POST "$KONG/auth/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=authorization_code" \
  -d "code=$AUTH_CODE" \
  -d "redirect_uri=http://localhost:3000/callback" \
  -d "code_verifier=$CODE_VERIFIER" \
  | python3 -m json.tool
```

Saída esperada:
```json
{
    "access_token": "eyJhbGciOiJSUzI1NiIs...",
    "expires_in": 300,
    "refresh_token": "eyJhbGciOiJIUzI1NiIs...",
    "token_type": "Bearer",
    "scope": "openid profile email"
}
```

### Atalho para dev — token direto (sem PKCE, sem browser)

> Só funciona porque `directAccessGrantsEnabled: true` no client `domestic-backend-bff`.
> Use apenas para testes locais — nunca em produção.

```bash
ACCESS_TOKEN=$(curl -s -X POST "$KEYCLOAK/realms/domestic-backend/protocol/openid-connect/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=password" \
  -d "client_id=domestic-backend-bff" \
  -d "client_secret=backend-bff-client-secret" \
  -d "username=anderson.filho" \
  -d "password=10203040" \
  -d "scope=openid" \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])")

echo "Token: ${ACCESS_TOKEN:0:60}..."
```

---

## Como expor uma nova rota pelo Kong

> Kong está em modo **DB-less** (`KONG_DATABASE=off`).
> **Kong Manager é read-only** — toda mudança de config é feita no `kong.yml` e aplicada via `kubectl`.

### 1. Editar `kong.yml`

Arquivo: `domestic-backend-api/kong/kong.yml`

#### Exemplo — expor `/api/v1` via BFF (já está comentado no arquivo)

```yaml
services:
  - name: bff
    url: http://bff:3001          # service name dentro do namespace domestic
    connect_timeout: 10000
    read_timeout: 30000
    write_timeout: 30000

    routes:
      - name: bff-all
        paths:
          - /api/v1
        methods:
          - GET
          - POST
          - PUT
          - DELETE
          - OPTIONS
        strip_path: false
        plugins:
          - name: rate-limiting
            config:
              minute: 120
              policy: local
          - name: cors
            config:
              origins:
                - "http://localhost:3000"
                - "http://localhost:3001"
              methods: [GET, POST, PUT, DELETE, OPTIONS]
              headers: [Authorization, Content-Type, X-Request-Id]
              credentials: true
              max_age: 3600
```

#### Exemplo — expor rota protegida por JWT do Keycloak

```yaml
services:
  - name: meu-servico
    url: http://meu-servico:3000

    routes:
      - name: meu-servico-api
        paths:
          - /meu-servico
        methods: [GET, POST]
        strip_path: false
        plugins:
          - name: jwt
            config:
              key_claim_name: kid
              claims_to_verify: [exp]
          - name: cors
            config:
              origins: ["*"]
              methods: [GET, POST, OPTIONS]
              headers: [Authorization, Content-Type]
              credentials: false
```

### 2. Aplicar no cluster

Execute a partir da pasta `domestic-kubernets/`:

```bash
# Recriar o ConfigMap com o kong.yml atualizado
kubectl create configmap kong-declarative-config \
  --from-file=kong.yml=../domestic-backend-api/kong/kong.yml \
  -n domestic \
  --dry-run=client -o yaml | kubectl apply -f -

# Recarregar Kong sem downtime (graceful reload)
kubectl exec -n domestic deployment/kong -- kong reload

# Confirmar que as novas rotas estão ativas
curl -s http://192.168.3.60:30801/routes | python3 -c "
import sys, json
d = json.load(sys.stdin)
for r in d['data']:
    print(r['name'], '-', r.get('methods'), r.get('paths'))
"
```

### 3. Validar no Kong Manager

Acesse `http://kong-manager.domestic.local` (login via Keycloak) e vá em **Routes** ou **Services** para confirmar que as rotas apareceram.

> Kong Manager em modo DB-less é somente leitura — use-o para **verificar**, não para **editar**.

---

## Referência rápida — Admin API

```bash
ADMIN="http://192.168.3.60:30801"
# Ou: ADMIN="http://kong-admin.domestic.local"

# Listar serviços
curl -s $ADMIN/services | python3 -m json.tool

# Listar rotas
curl -s $ADMIN/routes | python3 -m json.tool

# Listar plugins ativos
curl -s $ADMIN/plugins | python3 -m json.tool

# Status geral do Kong
curl -s $ADMIN/status | python3 -m json.tool

# Ver config declarativa carregada (DB-less)
curl -s $ADMIN/config | python3 -c "
import sys, json
d = json.load(sys.stdin)
for svc in d.get('services', []):
    print('service:', svc['name'], '→', svc.get('url') or svc.get('host'))
    for r in svc.get('routes', []):
        print('  route:', r['name'], r.get('paths'), r.get('methods'))
"
```

---

## Plugins úteis do Kong (open-source)

| Plugin | O que faz | Exemplo de uso |
|---|---|---|
| `cors` | Adiciona headers CORS | Qualquer rota exposta ao frontend |
| `rate-limiting` | Limita requests por IP/min | Rotas públicas |
| `jwt` | Valida JWT (Keycloak) | Rotas que exigem autenticação |
| `request-transformer` | Adiciona/remove headers e params | Injetar `client_secret` (como no `/auth/token`) |
| `response-transformer` | Modifica response | Remover headers internos |
| `ip-restriction` | Whitelist/blacklist de IPs | Restringir acesso |
| `request-size-limiting` | Limita tamanho do body | Upload de arquivos |
