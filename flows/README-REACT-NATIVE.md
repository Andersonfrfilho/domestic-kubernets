# Zolve - React Native App Development Guide

## Architecture Overview

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│  React      │     │   Kong      │     │     BFF     │     │     API     │
│  Native     │────▶│  Gateway    │────▶│  (NestJS)   │────▶│  (NestJS)   │
│  App        │     │  :8000      │     │  :3001      │     │  :3000      │
└─────────────┘     └─────────────┘     └─────────────┘     └─────────────┘
                          │                   │                   │
                          ▼                   ▼                   ▼
                    ┌─────────────┐     ┌─────────────┐     ┌─────────────┐
                    │   Keycloak  │     │    Mongo    │     │  PostgreSQL │
                    │   (Auth)    │     │    (Cache)  │     │   (Data)    │
                    └─────────────┘     └─────────────┘     └─────────────┘
```

### Base URL

| Environment | URL |
|---|---|
| **Local (K8s)** | `http://192.168.3.203` |
| **DNS** | `http://gateway.domestic.local` |

All requests must include the header:
```
Host: gateway.domestic.local
```

### Auth Mechanism

Kong uses **JWT plugin** on private routes (`/bff/*` catch-all). After login via Keycloak, the app receives a JWT token which must be passed on subsequent requests.

**Private routes** (require JWT):
- `/bff/dashboard/*`
- `/bff/notifications/*`
- `/bff/chat/*`

**Public routes** (no auth):
- `/bff/app-config`, `/bff/health`, `/bff/home`, `/bff/search`
- `/bff/onboarding/*`
- `/bff/auth/terms/*`
- `/bff/auth/forgot-password`

For local testing with JWT:
```bash
curl -H "Host: gateway.domestic.local" \
  -H "Authorization: Bearer <jwt-token>" \
  http://192.168.3.203/bff/dashboard/contractor
```

---

## Screen Flow

```
┌──────────────────┐
│   Splash Screen  │
│  (App Config)    │
└────────┬─────────┘
         │
         ▼
┌──────────────────┐     ┌──────────────────┐
│   Login Screen   │────▶│  Forgot Password │
│                  │     │     Screen       │
└────────┬─────────┘     └──────────────────┘
         │
         ▼
┌──────────────────┐
│  Register Screen │
│  (Email + Phone) │
└────────┬─────────┘
         │
         ▼
┌──────────────────┐
│  Verification    │
│  Code Screen     │
└────────┬─────────┘
         │
         ▼
┌──────────────────┐
│  Terms of Use    │
│  Screen          │
└────────┬─────────┘
         │
         ▼
┌──────────────────────────────────────────────┐
│              Main App (Tab Bar)              │
│  ┌────────┐ ┌────────┐ ┌────────┐ ┌───────┐ │
│  │  Home  │ │ Search │ │Orders  │ │ Chat  │ │
│  │        │ │        │ │(Dash)  │ │       │ │
│  └────────┘ └────────┘ └────────┘ └───────┘ │
│                                              │
│  ┌────────────────────────────────────────┐  │
│  │           Notifications               │  │
│  │           (Bell Icon)                 │  │
│  └────────────────────────────────────────┘  │
└──────────────────────────────────────────────┘
```

---

## Phase 1: App Startup

### 1.1 App Config

Called on app launch to get navigation config, feature flags, and version info.

```bash
curl -H "Host: gateway.domestic.local" \
  http://192.168.3.203/bff/app-config
```

**Success (200):**
```json
{
  "navigation": {
    "tabBar": {
      "visible": true,
      "items": [
        { "id": "home", "label": "Inicio", "icon": "home", "route": "/home", "visible": true },
        { "id": "search", "label": "Buscar", "icon": "search", "route": "/search", "visible": true },
        { "id": "dashboard", "label": "Pedidos", "icon": "list", "route": "/dashboard", "visible": true },
        { "id": "chat", "label": "Chat", "icon": "chat", "route": "/chat", "visible": true },
        { "id": "notifications", "label": "Avisos", "icon": "bell", "route": "/notifications", "visible": true }
      ]
    },
    "header": { "title": null, "showBack": false, "actions": [] }
  },
  "features": {
    "chatEnabled": true,
    "notificationsEnabled": true,
    "reviewsEnabled": true,
    "providerSearchEnabled": true
  },
  "version": {
    "minRequired": "1.0.0",
    "latest": "1.0.0",
    "forceUpdate": false
  }
}
```

**Error (500):**
```json
{
  "statusCode": 500,
  "message": "Internal server error"
}
```

### 1.2 Health Check

```bash
curl -H "Host: gateway.domestic.local" \
  http://192.168.3.203/bff/health
```

**Success (200):**
```json
{ "status": true }
```

---

## Phase 2: Authentication

### 2.1 Login (via Keycloak)

Login is handled directly by Keycloak through Kong. The app opens a WebView or browser tab.

```bash
# Open this URL in browser/WebView
http://gateway.domestic.local/auth/protocol/openid-connect/auth?
  client_id=zolve-app&
  redirect_uri=zolve://callback&
  response_type=code&
  scope=openid
```

After successful login, Kong injects `X-User-Id` into all subsequent requests.

### 2.2 Forgot Password

```bash
curl -X POST -H "Host: gateway.domestic.local" \
  -H "Content-Type: application/json" \
  -d '{"email": "user@example.com"}' \
  http://192.168.3.203/bff/auth/forgot-password
```

**Success (200):**
```
(empty body — 200 OK)
```

**Error (404) — Email not found:**
```json
{
  "statusCode": 404,
  "message": "Usuario nao encontrado"
}
```

**Error (400) — Invalid email:**
```json
{
  "statusCode": 400,
  "message": "Validation failed",
  "details": {
    "validationErrors": [
      { "field": "email", "constraints": { "isEmail": "Email invalido" } }
    ]
  }
}
```

---

## Phase 3: Onboarding (Registration)

### 3.1 Send Verification Code

```bash
curl -X POST -H "Host: gateway.domestic.local" \
  -H "Content-Type: application/json" \
  -d '{"destination": "user@example.com", "type": "email"}' \
  http://192.168.3.203/bff/onboarding/verification/send
```

**Success (200):**
```json
{
  "success": true,
  "message": "Codigo de verificacao gerado (QA Mode): 0000"
}
```

**Error (400) — Invalid destination:**
```json
{
  "statusCode": 400,
  "message": "Validation failed",
  "details": {
    "validationErrors": [
      { "field": "destination", "constraints": { "isNotEmpty": "Destino e obrigatorio" } }
    ]
  }
}
```

### 3.2 Verify Code

```bash
curl -X POST -H "Host: gateway.domestic.local" \
  -H "Content-Type: application/json" \
  -d '{"destination": "user@example.com", "type": "email", "code": "0000"}' \
  http://192.168.3.203/bff/onboarding/verification/verify
```

**Success (200):**
```json
{
  "success": true,
  "verified": true,
  "message": "Codigo verificado com sucesso"
}
```

**Error (400) — Invalid/expired code:**
```json
{
  "statusCode": 400,
  "message": "Codigo invalido ou expirado"
}
```

### 3.3 Register User

```bash
curl -X POST -H "Host: gateway.domestic.local" \
  -H "Content-Type: application/json" \
  -d '{
    "email": "user@example.com",
    "password": "SecurePass123!",
    "firstName": "Joao",
    "lastName": "Silva",
    "phone": "11999999999",
    "cpf": "12345678900"
  }' \
  http://192.168.3.203/bff/onboarding/register
```

**Success (201):**
```json
{
  "keycloakId": "bc7b9565-fdb1-4300-b0c1-aca8230c14d5",
  "email": "user@example.com",
  "success": true,
  "message": "Usuario criado com sucesso"
}
```

**Error (409) — Email already in use:**
```json
{
  "statusCode": 409,
  "message": "E-mail ja esta em uso"
}
```

**Error (400) — Validation failed:**
```json
{
  "statusCode": 400,
  "message": "Validation failed",
  "details": {
    "validationErrors": [
      { "field": "phone", "constraints": { "matches": "Telefone deve conter 10 ou 11 digitos" } },
      { "field": "password", "constraints": { "minLength": "Senha deve ter no minimo 8 caracteres" } }
    ],
    "count": 2
  }
}
```

### 3.4 CEP Lookup (Address)

```bash
curl -H "Host: gateway.domestic.local" \
  http://192.168.3.203/bff/onboarding/cep/01001000
```

**Success (200):**
```json
{
  "cep": "01001-000",
  "street": "Praca da Se",
  "neighborhood": "Se",
  "city": "Sao Paulo",
  "state": "SP",
  "lat": -23.5505,
  "lng": -46.6333
}
```

**Error (404) — CEP not found:**
```json
{
  "statusCode": 404,
  "message": "CEP nao encontrado"
}
```

### 3.5 Upload Document

```bash
curl -X POST -H "Host: gateway.domestic.local" \
  -F "file=@/path/to/document.pdf" \
  -F "documentType=CPF" \
  http://192.168.3.203/bff/onboarding/documents/upload
```

**Success (200):**
```json
{
  "success": true,
  "message": "Documento enviado com sucesso",
  "documentId": "abc123"
}
```

---

## Phase 4: Terms of Use

### 4.1 Get Current Terms

```bash
curl -H "Host: gateway.domestic.local" \
  http://192.168.3.203/bff/auth/terms/current
```

**Success (200):**
```json
{
  "id": "56b54392-ebe0-4851-ac89-c8bff134a8df",
  "version": "1.0.0",
  "title": "Termos de Uso - Versao Inicial",
  "contentUrl": null,
  "effectiveDate": "2026-04-30T15:29:55.051Z"
}
```

### 4.2 List All Versions

```bash
curl -H "Host: gateway.domestic.local" \
  http://192.168.3.203/bff/auth/terms/versions
```

**Success (200):**
```json
[
  {
    "id": "56b54392-ebe0-4851-ac89-c8bff134a8df",
    "version": "1.0.0",
    "title": "Termos de Uso - Versao Inicial",
    "contentUrl": null,
    "isActive": true,
    "effectiveDate": "2026-04-30T15:29:55.051Z"
  }
]
```

### 4.3 Check Pending Terms

```bash
curl -X POST -H "Host: gateway.domestic.local" \
  -H "Content-Type: application/json" \
  -d '{"userId": "bc7b9565-fdb1-4300-b0c1-aca8230c14d5"}' \
  http://192.168.3.203/bff/auth/terms/check-pending
```

**Success (200) — Has pending:**
```json
{
  "hasPending": true,
  "currentVersion": "1.0.0",
  "lastAcceptedVersion": null
}
```

**Success (200) — No pending:**
```json
{
  "hasPending": false,
  "currentVersion": "1.0.0",
  "lastAcceptedVersion": "1.0.0"
}
```

### 4.4 Accept Terms

```bash
curl -X POST -H "Host: gateway.domestic.local" \
  -H "Content-Type: application/json" \
  -d '{
    "userId": "bc7b9565-fdb1-4300-b0c1-aca8230c14d5",
    "termsVersionId": "56b54392-ebe0-4851-ac89-c8bff134a8df"
  }' \
  http://192.168.3.203/bff/auth/terms/accept
```

**Success (200):**
```json
{
  "success": true,
  "message": "Termos de uso aceitos",
  "termsVersion": "1.0.0",
  "acceptedAt": "2026-04-30T17:45:09.429Z"
}
```

**Success (200) — Already accepted:**
```json
{
  "success": true,
  "message": "Termos ja aceitos para esta versao",
  "termsVersion": "1.0.0",
  "acceptedAt": "2026-04-30T17:45:09.429Z"
}
```

**Error (400):**
```json
{
  "statusCode": 400,
  "message": "Falha ao aceitar termos"
}
```

---

## Phase 5: Main App (Authenticated)

### 5.1 Home Screen

```bash
curl -H "Host: gateway.domestic.local" \
  http://192.168.3.203/bff/home
```

**Success (200):**
```json
{
  "layout": { ... },
  "featuredCategories": [ ... ],
  "featuredProviders": [ ... ]
}
```

### 5.2 Search

> **Note:** Currently returns 500 — pre-existing bug in the search service.

```bash
curl -H "Host: gateway.domestic.local" \
  "http://192.168.3.203/bff/search?q=eletricista&category=home-services&page=1&limit=20"
```

**Success (200):**
```json
{
  "layout": { ... },
  "filters": [ ... ],
  "data": [ ... ],
  "meta": { "total": 42, "page": 1, "limit": 20 },
  "links": { "next": "/bff/search?q=eletricista&page=2" }
}
```

### 5.3 Dashboard — Contractor

> **Requires JWT authentication** via Kong JWT plugin.

```bash
curl -H "Host: gateway.domestic.local" \
  -H "Authorization: Bearer <jwt-token>" \
  http://192.168.3.203/bff/dashboard/contractor
```

**Success (200):**
```json
{
  "activeRequests": 3,
  "pendingRequests": 1,
  "recentHistory": [ ... ],
  "unreadNotifications": 2
}
```

### 5.4 Dashboard — Provider

> **Requires JWT authentication** via Kong JWT plugin.

```bash
curl -H "Host: gateway.domestic.local" \
  -H "Authorization: Bearer <jwt-token>" \
  http://192.168.3.203/bff/dashboard/provider
```

**Success (200):**
```json
{
  "incomingRequests": 5,
  "activeRequests": 2,
  "averageRating": 4.8,
  "reviewCount": 23,
  "verificationStatus": "approved",
  "unreadNotifications": 3
}
```

### 5.5 Notifications

> **Requires JWT authentication** via Kong JWT plugin.

```bash
# List notifications
curl -H "Host: gateway.domestic.local" \
  -H "Authorization: Bearer <jwt-token>" \
  http://192.168.3.203/bff/notifications

# Unread count
curl -H "Host: gateway.domestic.local" \
  -H "Authorization: Bearer <jwt-token>" \
  http://192.168.3.203/bff/notifications/unread-count

# Mark as read
curl -X PUT -H "Host: gateway.domestic.local" \
  -H "Authorization: Bearer <jwt-token>" \
  http://192.168.3.203/bff/notifications/<notification-id>/read

# Mark all as read
curl -X PUT -H "Host: gateway.domestic.local" \
  -H "Authorization: Bearer <jwt-token>" \
  http://192.168.3.203/bff/notifications/read-all
```

### 5.6 Chat

> **Requires JWT authentication** via Kong JWT plugin.

```bash
# Create chat room
curl -X POST -H "Host: gateway.domestic.local" \
  -H "Authorization: Bearer <jwt-token>" \
  -H "Content-Type: application/json" \
  -d '{"providerId": "provider-uuid"}' \
  http://192.168.3.203/bff/chat/rooms

# List rooms
curl -H "Host: gateway.domestic.local" \
  -H "Authorization: Bearer <jwt-token>" \
  http://192.168.3.203/bff/chat/rooms

# Get messages
curl -H "Host: gateway.domestic.local" \
  -H "Authorization: Bearer <jwt-token>" \
  "http://192.168.3.203/bff/chat/rooms/<room-id>/messages?page=1&limit=50"

# Send message
curl -X POST -H "Host: gateway.domestic.local" \
  -H "Authorization: Bearer <jwt-token>" \
  -H "Content-Type: application/json" \
  -d '{"content": "Ola, preciso de um orcamento"}' \
  http://192.168.3.203/bff/chat/rooms/<room-id>/messages
```

### 5.7 Provider Profile

```bash
curl -H "Host: gateway.domestic.local" \
  http://192.168.3.203/bff/providers/<provider-id>/profile
```

**Success (200):**
```json
{
  "businessName": "Joao Servicos Eletricos",
  "services": [ ... ],
  "workLocations": [ ... ],
  "recentReviews": [ ... ],
  "averageRating": 4.8
}
```

---

## Error Response Format

All errors follow this structure:

### Validation Error (400)
```json
{
  "statusCode": 400,
  "timestamp": "2026-04-30T17:45:09.429Z",
  "path": "/bff/onboarding/register",
  "message": "Validation failed",
  "details": {
    "validationErrors": [
      { "field": "fieldName", "constraints": { "rule": "error message" } }
    ],
    "count": 1
  }
}
```

### Not Found (404)
```json
{
  "statusCode": 404,
  "timestamp": "2026-04-30T17:45:09.429Z",
  "path": "/bff/onboarding/cep/00000000",
  "message": "CEP nao encontrado"
}
```

### Conflict (409)
```json
{
  "statusCode": 409,
  "timestamp": "2026-04-30T17:45:09.429Z",
  "path": "/bff/onboarding/register",
  "message": "E-mail ja esta em uso"
}
```

### Unauthorized (401)
```json
{
  "statusCode": 401,
  "message": "Unauthorized"
}
```

### Internal Server Error (500)
```json
{
  "statusCode": 500,
  "timestamp": "2026-04-30T17:45:09.429Z",
  "path": "/bff/auth/terms/accept",
  "message": "Falha ao aceitar termos"
}
```

---

## Complete Onboarding Flow (Step by Step)

```
1. GET  /bff/app-config
    → Get feature flags, tab bar config, app version

2. GET  /bff/auth/terms/current
    → Get current terms version (show to user)

3. POST /bff/onboarding/verification/send
    Body: { destination: "email", type: "email" }
    → Send verification code

4. POST /bff/onboarding/verification/verify
    Body: { destination: "email", type: "email", code: "0000" }
    → Verify code

5. POST /bff/onboarding/register
    Body: { email, password, firstName, lastName, phone, cpf }
    → Create user in Keycloak + API
    Response: { keycloakId, email, success, message }

6. POST /bff/auth/terms/check-pending
    Body: { userId: "<keycloakId>" }
    → Check if user needs to accept terms
    Response: { hasPending: true, currentVersion: "1.0.0", lastAcceptedVersion: null }

7. POST /bff/auth/terms/accept
    Body: { userId: "<keycloakId>", termsVersionId: "<version-id>" }
    → Accept terms
    Response: { success: true, message: "Termos de uso aceitos", termsVersion: "1.0.0" }

8. → Navigate to Main App (Tab Bar)
```

---

## QA Mode

In development/QA mode:
- **Verification code is always `0000`** (for email type)
- **Phone verification code = last 4 digits** of the phone number
- No real email/SMS is sent

---

## Running the Flow Scripts

You can test the full flow from the K8s machine:

```bash
# Onboarding flow (all steps)
cd /home/miyazaki/Documents/personal/domestic/domestic-kubernets
node flows/onboarding.flow.js

# Terms flow (for existing user)
node flows/terms.flow.js <user-keycloak-id>
```

---

## Kong Routes Reference

All routes are served through Kong at `http://192.168.3.203` (or `http://gateway.domestic.local`).

### Public Routes (no auth)

| Kong Route | Paths | Backend |
|---|---|---|
| `bff-auth-route` | `/bff/auth/*` | BFF (`/bff/auth/forgot-password`) |
| `bff-onboarding-public-route` | `/bff/onboarding/register`<br>`/bff/onboarding/verification/send`<br>`/bff/onboarding/verification/verify`<br>`/bff/onboarding/cep/*`<br>`/bff/onboarding/documents/upload` | BFF |
| `bff-terms-public-route` | `/bff/auth/terms/current`<br>`/bff/auth/terms/versions`<br>`/bff/auth/terms/check-pending`<br>`/bff/auth/terms/accept` | BFF |
| `bff-public-route` | `/bff/app-config`<br>`/bff/home`<br>`/bff/search`<br>`/bff/health` | BFF |
| `auth-route` | `/auth/*` | Keycloak (login, token, etc.) |
| `account-route` | `/account/*` | Keycloak (password reset) |

### Private Routes (JWT required)

| Kong Route | Paths | Backend | Plugin |
|---|---|---|---|
| `bff-private-route` | `/bff/*` (catch-all) | BFF | JWT (`iss` claim) |
| `api-route` | `/api/*` | API | JWT (`iss` claim) |

### How Kong Routing Works

```
Request: POST /bff/onboarding/register
  ↓
Kong matches: bff-onboarding-public-route (priority 95)
  ↓
strip_path: false → forwards full path to BFF
  ↓
BFF receives: POST /bff/onboarding/register
  ↓
@ Controller('bff/onboarding') + @Post('register') → handled
```

**Important:** `strip_path: false` means the BFF receives the full path including `/bff/...`. This is why all BFF controllers use `@Controller('bff/...')` prefix.
