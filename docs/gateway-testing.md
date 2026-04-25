# Gateway Testing — curl Reference

Base URL: `http://gateway.domestic.local`

All authenticated requests require a Bearer token obtained from the login step.
Store it in `$TOKEN` for reuse across commands.

---

## 1. Auth Flow

### Login
```bash
TOKEN=$(curl -s -X POST http://gateway.domestic.local/auth/token \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=password" \
  -d "client_id=domestic-bff" \
  -d "client_secret=backend-bff-client-secret" \
  -d "username=anderson.filho" \
  -d "password=10203040" \
  | jq -r '.access_token')
echo $TOKEN
```

### Refresh Token
```bash
REFRESH=$(curl -s -X POST http://gateway.domestic.local/auth/token \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=password" \
  -d "client_id=domestic-bff" \
  -d "client_secret=backend-bff-client-secret" \
  -d "username=anderson.filho" \
  -d "password=10203040" \
  | jq -r '.refresh_token')

TOKEN=$(curl -s -X POST http://gateway.domestic.local/auth/token \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=refresh_token" \
  -d "client_id=domestic-bff" \
  -d "client_secret=backend-bff-client-secret" \
  -d "refresh_token=$REFRESH" \
  | jq -r '.access_token')
echo $TOKEN
```

### Userinfo
```bash
curl -s http://gateway.domestic.local/auth/userinfo \
  -H "Authorization: Bearer $TOKEN" | jq
```

### JWKs (chave pública do realm)
```bash
curl -s http://gateway.domestic.local/auth/certs | jq
```

### Logout
```bash
# Pegar o refresh_token primeiro (guarde junto com o access_token no login)
curl -s -X POST http://gateway.domestic.local/auth/logout \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "client_id=domestic-bff" \
  -d "client_secret=backend-bff-client-secret" \
  -d "refresh_token=$REFRESH"
```

---

## 2. Redefinição de Senha

### Passo 1 — Disparar e-mail de reset (via API NestJS)
```bash
# A API expõe endpoint de forgot-password que chama Admin REST do Keycloak
curl -s -X POST http://gateway.domestic.local/api/users/forgot-password \
  -H "Content-Type: application/json" \
  -d '{"email": "anderson@domestic.local"}'
```

### Passo 2 — Verificar e-mail no Mailpit
Abra no browser: **http://mail.domestic.local/**

O e-mail de reset aparece na caixa de entrada. Clique no link ou copie a URL.

### Passo 3 — O link abre no browser
```
http://keycloak.domestic.local/realms/domestic/login-actions/reset-credentials?...
```
O usuário preenche a nova senha diretamente na tela do Keycloak.

### Alternativa — Abrir tela de reset direto (sem e-mail)
```bash
# Abre no browser — não funciona via curl pois exige sessão de browser
open "http://gateway.domestic.local/account/login-actions/reset-credentials?client_id=domestic-bff"
```

---

## 3. Health Checks

```bash
# API
curl -s http://gateway.domestic.local/api/health | jq

# BFF
curl -s http://gateway.domestic.local/bff/health | jq
```

---

## 4. Rotas BFF (`/bff/*`) — requer JWT

> Todas as rotas abaixo precisam de `Authorization: Bearer $TOKEN`

### Notifications
```bash
# Listar notificações
curl -s http://gateway.domestic.local/bff/notifications \
  -H "Authorization: Bearer $TOKEN" | jq

# Contagem não lidas
curl -s http://gateway.domestic.local/bff/notifications/unread-count \
  -H "Authorization: Bearer $TOKEN" | jq

# Marcar uma como lida
curl -s -X PUT http://gateway.domestic.local/bff/notifications/{id}/read \
  -H "Authorization: Bearer $TOKEN" | jq

# Marcar todas como lidas
curl -s -X PUT http://gateway.domestic.local/bff/notifications/read-all \
  -H "Authorization: Bearer $TOKEN" | jq
```

### Provider Profile
```bash
curl -s http://gateway.domestic.local/bff/providers/{id}/profile \
  -H "Authorization: Bearer $TOKEN" | jq
```

### Dashboard
```bash
# Dashboard do contratante
curl -s http://gateway.domestic.local/bff/dashboard/contractor \
  -H "Authorization: Bearer $TOKEN" | jq

# Dashboard do prestador
curl -s http://gateway.domestic.local/bff/dashboard/provider \
  -H "Authorization: Bearer $TOKEN" | jq
```

### App Config
```bash
curl -s http://gateway.domestic.local/bff/app-config \
  -H "Authorization: Bearer $TOKEN" | jq
```

### Navigation
```bash
# Listar navegação
curl -s http://gateway.domestic.local/bff/navigation \
  -H "Authorization: Bearer $TOKEN" | jq

# Item por screenId
curl -s http://gateway.domestic.local/bff/navigation/{screenId} \
  -H "Authorization: Bearer $TOKEN" | jq
```

### Screens
```bash
# Listar telas
curl -s http://gateway.domestic.local/bff/screens \
  -H "Authorization: Bearer $TOKEN" | jq

# Tela específica
curl -s http://gateway.domestic.local/bff/screens/{screenId} \
  -H "Authorization: Bearer $TOKEN" | jq
```

### Search
```bash
curl -s "http://gateway.domestic.local/bff/search?q=limpeza" \
  -H "Authorization: Bearer $TOKEN" | jq
```

### Chat
```bash
# Criar sala
curl -s -X POST http://gateway.domestic.local/bff/chat/rooms \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"participantId": "{userId}"}' | jq

# Listar salas
curl -s http://gateway.domestic.local/bff/chat/rooms \
  -H "Authorization: Bearer $TOKEN" | jq

# Mensagens de uma sala
curl -s http://gateway.domestic.local/bff/chat/rooms/{roomId}/messages \
  -H "Authorization: Bearer $TOKEN" | jq

# Enviar mensagem
curl -s -X POST http://gateway.domestic.local/bff/chat/rooms/{roomId}/messages \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"content": "Olá!"}' | jq
```

### Home
```bash
curl -s http://gateway.domestic.local/bff/home \
  -H "Authorization: Bearer $TOKEN" | jq
```

---

## 5. Rotas API (`/api/*`) — requer JWT

### Users
```bash
# Perfil do usuário logado
curl -s http://gateway.domestic.local/api/users/me \
  -H "Authorization: Bearer $TOKEN" | jq

# Listar usuários
curl -s http://gateway.domestic.local/api/users \
  -H "Authorization: Bearer $TOKEN" | jq

# Endereços do usuário
curl -s http://gateway.domestic.local/api/users/me/addresses \
  -H "Authorization: Bearer $TOKEN" | jq

# Telefones do usuário
curl -s http://gateway.domestic.local/api/users/me/phones \
  -H "Authorization: Bearer $TOKEN" | jq

# E-mails do usuário
curl -s http://gateway.domestic.local/api/users/me/emails \
  -H "Authorization: Bearer $TOKEN" | jq
```

### Providers
```bash
# Listar prestadores
curl -s http://gateway.domestic.local/api/providers \
  -H "Authorization: Bearer $TOKEN" | jq

# Perfil do prestador
curl -s http://gateway.domestic.local/api/providers/{id} \
  -H "Authorization: Bearer $TOKEN" | jq

# Serviços do prestador
curl -s http://gateway.domestic.local/api/providers/{id}/services \
  -H "Authorization: Bearer $TOKEN" | jq

# Locais de atendimento
curl -s http://gateway.domestic.local/api/providers/{id}/work-locations \
  -H "Authorization: Bearer $TOKEN" | jq
```

### Categories
```bash
curl -s http://gateway.domestic.local/api/categories \
  -H "Authorization: Bearer $TOKEN" | jq
```

### Services
```bash
curl -s http://gateway.domestic.local/api/services \
  -H "Authorization: Bearer $TOKEN" | jq
```

### Service Requests
```bash
# Listar solicitações
curl -s http://gateway.domestic.local/api/service-requests \
  -H "Authorization: Bearer $TOKEN" | jq

# Criar solicitação
curl -s -X POST http://gateway.domestic.local/api/service-requests \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"serviceId": "{id}", "providerId": "{id}"}' | jq
```

### Notifications
```bash
curl -s http://gateway.domestic.local/api/notifications \
  -H "Authorization: Bearer $TOKEN" | jq
```

### Reviews
```bash
curl -s http://gateway.domestic.local/api/reviews \
  -H "Authorization: Bearer $TOKEN" | jq
```

### Documents
```bash
curl -s http://gateway.domestic.local/api/documents \
  -H "Authorization: Bearer $TOKEN" | jq
```

---

## 6. Verificar token JWT (debug)

```bash
# Decodificar payload sem verificar assinatura
echo $TOKEN | cut -d. -f2 | base64 -d 2>/dev/null | jq
```

---

## Referência rápida

| Operação | Comando |
|---|---|
| Login | `POST /auth/token` (grant_type=password) |
| Refresh | `POST /auth/token` (grant_type=refresh_token) |
| Logout | `POST /auth/logout` |
| Userinfo | `GET /auth/userinfo` |
| JWKs | `GET /auth/certs` |
| Reset senha (browser) | `GET /account/login-actions/reset-credentials` |
| E-mails capturados | http://mail.domestic.local/ |
