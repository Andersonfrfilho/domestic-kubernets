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

### 3.3 Field Verification (Real-time)

Endpoints para verificar disponibilidade de campos em tempo real durante o cadastro. Usar com **debounce** no frontend (500ms).

#### Verificar Email

```bash
curl -X POST -H "Host: gateway.domestic.local" \
  -H "Content-Type: application/json" \
  -d '{"email": "usuario@email.com"}' \
  http://192.168.3.203/bff/onboarding/verify/email
```

**Success (200) — Available:**
```json
{
  "available": true,
  "valid": true,
  "field": "email"
}
```

**Error (409) — Already exists:**
```json
{
  "statusCode": 409,
  "error": "EMAIL_ALREADY_EXISTS",
  "message": "E-mail já está em uso",
  "field": "email"
}
```

#### Verificar Telefone

```bash
curl -X POST -H "Host: gateway.domestic.local" \
  -H "Content-Type: application/json" \
  -d '{"phone": "11999999999"}' \
  http://192.168.3.203/bff/onboarding/verify/phone
```

**Success (200) — Available:**
```json
{
  "available": true,
  "valid": true,
  "field": "phone"
}
```

**Error (409) — Already exists:**
```json
{
  "statusCode": 409,
  "error": "PHONE_ALREADY_EXISTS",
  "message": "Telefone já está cadastrado",
  "field": "phone"
}
```

#### Verificar Documento (CPF/CNPJ)

```bash
curl -X POST -H "Host: gateway.domestic.local" \
  -H "Content-Type: application/json" \
  -d '{"document": "12345678909"}' \
  http://192.168.3.203/bff/onboarding/verify/document
```

**Success (200) — Available:**
```json
{
  "available": true,
  "valid": true,
  "field": "document"
}
```

**Error (409) — Already exists:**
```json
{
  "statusCode": 409,
  "error": "DOCUMENT_ALREADY_EXISTS",
  "message": "Documento já está cadastrado",
  "field": "document"
}
```

#### Rate Limiting

| Endpoint | Limit | Window |
|---|---|---|
| `/verify/email` | 5 requests | 1 minute |
| `/verify/phone` | 5 requests | 1 minute |
| `/verify/document` | 3 requests | 1 minute |

Response headers included:
```
RateLimit-Limit: 5
RateLimit-Remaining: 3
RateLimit-Reset: 45
X-RateLimit-Limit-Minute: 5
X-RateLimit-Remaining-Minute: 3
```

**Error (429) — Rate limit exceeded:**
```json
{
  "message": "{\"statusCode\":429,\"error\":\"RATE_LIMIT_EXCEEDED\",\"message\":\"Muitas tentativas. Tente novamente em alguns minutos.\",\"field\":\"email\"}",
  "request_id": "abc123..."
}
```

Parse o campo `message` para obter os detalhes:
```typescript
if (response.status === 429) {
  const error = JSON.parse(data.message);
  // error.statusCode, error.error, error.message, error.field
}
```

### 3.4 Register User

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

## Frontend Integration: Field Verification

### Hook `useFieldVerification`

```typescript
// src/modules/auth/hooks/useFieldVerification.ts
import { useState, useRef, useCallback } from 'react';
import { apiClient } from '@/shared/services/api-client';

interface VerificationState {
  isChecking: boolean;
  isAvailable: boolean | null;
  error: string | null;
  isRateLimited: boolean;
}

interface RateLimitInfo {
  remaining: number;
  limit: number;
  resetSeconds: number;
}

export function useFieldVerification() {
  const [fields, setFields] = useState<Record<string, VerificationState>>({
    email: { isChecking: false, isAvailable: null, error: null, isRateLimited: false },
    phone: { isChecking: false, isAvailable: null, error: null, isRateLimited: false },
    document: { isChecking: false, isAvailable: null, error: null, isRateLimited: false },
  });

  const [rateLimitInfo, setRateLimitInfo] = useState<Record<string, RateLimitInfo>>({});

  const debounceTimers = useRef<Record<string, NodeJS.Timeout>>({});
  const abortControllers = useRef<Record<string, AbortController>>({});

  const parseRateLimitHeaders = (headers: Headers, field: string) => {
    const limit = parseInt(headers.get('RateLimit-Limit') || '0', 10);
    const remaining = parseInt(headers.get('RateLimit-Remaining') || '0', 10);
    const reset = parseInt(headers.get('RateLimit-Reset') || '0', 10);

    if (limit > 0) {
      setRateLimitInfo(prev => ({
        ...prev,
        [field]: { limit, remaining, resetSeconds: reset },
      }));
    }
  };

  const parseRateLimitError = (data: any): { message: string; retryAfter?: number } => {
    try {
      const parsed = typeof data.message === 'string' ? JSON.parse(data.message) : data.message;
      return {
        message: parsed.message || 'Muitas tentativas. Tente novamente.',
        retryAfter: parsed.retryAfter,
      };
    } catch {
      return { message: data.message || 'Muitas tentativas. Tente novamente.' };
    }
  };

  const verifyField = useCallback(async (field: string, value: string) => {
    if (abortControllers.current[field]) {
      abortControllers.current[field].abort();
    }

    const controller = new AbortController();
    abortControllers.current[field] = controller;

    setFields(prev => ({
      ...prev,
      [field]: { isChecking: true, isAvailable: null, error: null, isRateLimited: false },
    }));

    try {
      const response = await apiClient.post(
        `/bff/onboarding/verify/${field}`,
        { [field]: value },
        { signal: controller.signal },
      );

      parseRateLimitHeaders(response.headers, field);

      setFields(prev => ({
        ...prev,
        [field]: {
          isChecking: false,
          isAvailable: response.data.available && response.data.valid,
          error: null,
          isRateLimited: false,
        },
      }));

      return { success: true, available: response.data.available };
    } catch (error: any) {
      if (error.name === 'AbortError') return null;

      if (error.response?.status === 409) {
        setFields(prev => ({
          ...prev,
          [field]: {
            isChecking: false,
            isAvailable: false,
            error: error.response.data.message,
            isRateLimited: false,
          },
        }));
        return { success: false, available: false, error: error.response.data.message };
      }

      if (error.response?.status === 429) {
        const { message } = parseRateLimitError(error.response.data);
        setFields(prev => ({
          ...prev,
          [field]: {
            isChecking: false,
            isAvailable: null,
            error: message,
            isRateLimited: true,
          },
        }));
        return { success: false, rateLimited: true, error: message };
      }

      if (error.response?.status === 400) {
        const validationErrors = error.response.data?.details?.validationErrors || [];
        const errorMessage = validationErrors[0]?.constraints
          ? Object.values(validationErrors[0].constraints)[0] as string
          : 'Formato inválido';

        setFields(prev => ({
          ...prev,
          [field]: {
            isChecking: false,
            isAvailable: null,
            error: errorMessage,
            isRateLimited: false,
          },
        }));
        return { success: false, error: errorMessage };
      }

      setFields(prev => ({
        ...prev,
        [field]: { isChecking: false, isAvailable: null, error: null, isRateLimited: false },
      }));

      return null;
    }
  }, []);

  const verifyWithDebounce = useCallback((field: string, value: string, delay = 500) => {
    if (debounceTimers.current[field]) {
      clearTimeout(debounceTimers.current[field]);
    }

    const cleanedValue = value.replace(/\D/g, '');
    const minLengths: Record<string, number> = { email: 5, phone: 10, document: 8 };
    const minLength = minLengths[field] || 1;

    if (!value || cleanedValue.length < minLength) {
      setFields(prev => ({
        ...prev,
        [field]: { isChecking: false, isAvailable: null, error: null, isRateLimited: false },
      }));
      return;
    }

    if (fields[field]?.isRateLimited) return;

    debounceTimers.current[field] = setTimeout(() => {
      verifyField(field, value);
    }, delay);
  }, [fields, verifyField]);

  const resetField = useCallback((field: string) => {
    setFields(prev => ({
      ...prev,
      [field]: { isChecking: false, isAvailable: null, error: null, isRateLimited: false },
    }));
  }, []);

  return {
    fields,
    rateLimitInfo,
    verifyWithDebounce,
    resetField,
  };
}
```

### Usage in RegisterScreen

```typescript
// src/modules/auth/screens/register/register.screen.tsx
import { useFieldVerification } from '@/modules/auth/hooks/useFieldVerification';

export default function RegisterScreen() {
  const { fields, rateLimitInfo, verifyWithDebounce, resetField } = useFieldVerification();

  const handleEmailChange = (value: string) => {
    verifyWithDebounce('email', value, 500);
  };

  const handlePhoneChange = (value: string) => {
    verifyWithDebounce('phone', value.replace(/\D/g, ''), 500);
  };

  const handleDocumentChange = (value: string) => {
    verifyWithDebounce('document', value.replace(/\D/g, ''), 500);
  };

  return (
    <RegisterForm
      control={control}
      errors={errors}
      fieldStatus={fields}
      rateLimitInfo={rateLimitInfo}
      onEmailChange={handleEmailChange}
      onPhoneChange={handlePhoneChange}
      onDocumentChange={handleDocumentChange}
    />
  );
}
```

### UI Components

```typescript
// FieldStatusIndicator.tsx
interface FieldStatusIndicatorProps {
  field: string;
  status: VerificationState;
}

export function FieldStatusIndicator({ status }: FieldStatusIndicatorProps) {
  if (status.isChecking) {
    return (
      <View style={styles.checkingIndicator}>
        <ActivityIndicator size="small" color={theme.colors.primary.DEFAULT} />
        <Text style={styles.checkingText}>Verificando...</Text>
      </View>
    );
  }

  if (status.isRateLimited) {
    return (
      <View style={styles.rateLimitContainer}>
        <Ionicons name="time-outline" size={14} color={theme.colors.warning} />
        <Text style={styles.rateLimitText}>{status.error}</Text>
      </View>
    );
  }

  if (status.isAvailable === false && status.error) {
    return (
      <View style={styles.fieldErrorContainer}>
        <Ionicons name="alert-circle" size={14} color={theme.colors.status.error} />
        <Text style={styles.fieldErrorMessage}>{status.error}</Text>
        {status.error.includes('E-mail') && (
          <TouchableOpacity onPress={() => router.push('/forgot-password')}>
            <Text style={styles.forgotPasswordLink}>Esqueci minha senha</Text>
          </TouchableOpacity>
        )}
      </View>
    );
  }

  if (status.isAvailable === true) {
    return (
      <View style={styles.successIndicator}>
        <Ionicons name="checkmark-circle" size={14} color={theme.colors.status.success} />
        <Text style={styles.successText}>Disponível</Text>
      </View>
    );
  }

  return null;
}
```

### Error Handling Summary

| Scenario | HTTP Status | Frontend Action |
|---|---|---|
| Field available | 200 | Show green checkmark |
| Field already exists | 409 | Show error + "Esqueci minha senha" link (email) |
| Invalid format | 400 | Show validation error inline |
| Rate limit exceeded | 429 | Show warning, disable verification, parse `message` JSON |
| Network error | — | Silent fail, don't show error |
| User keeps typing | — | Cancel previous request (AbortController) |

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

Returns SDUI layout + featured categories + featured providers. Used as the main tab screen.

```bash
curl -H "Host: gateway.domestic.local" \
  http://192.168.3.203/bff/home
```

**Success (200):**
```json
{
  "layout": [
    {
      "id": "categories",
      "type": "category_list",
      "order": 0,
      "config": { "scroll": "horizontal", "showSeeAll": true },
      "action": { "type": "navigate", "route": "/search?category={slug}" },
      "data": [
        { "id": "uuid", "name": "Limpeza", "slug": "limpeza", "iconUrl": null },
        { "id": "uuid", "name": "Encanamento", "slug": "encanamento", "iconUrl": null }
      ]
    },
    {
      "id": "featured_providers",
      "type": "provider_grid",
      "order": 1,
      "config": { "columns": 2, "showRating": true },
      "action": { "type": "navigate", "route": "/providers/{id}" },
      "data": [
        {
          "id": "uuid",
          "businessName": "Maria Servicos Domesticos",
          "averageRating": 4.9,
          "reviewCount": 127,
          "services": [
            { "name": "Limpeza residencial", "priceBase": 150, "priceType": "FIXED" }
          ],
          "city": "Sao Paulo",
          "state": "SP",
          "latitude": "-23.550520",
          "longitude": "-46.633308",
          "isAvailable": true
        }
      ]
    }
  ],
  "featuredCategories": [
    { "id": "uuid", "name": "Limpeza", "slug": "limpeza", "iconUrl": null }
  ],
  "featuredProviders": [
    {
      "id": "uuid",
      "businessName": "Maria Servicos Domesticos",
      "averageRating": 4.9,
      "reviewCount": 127,
      "services": [
        { "name": "Limpeza residencial", "priceBase": 150, "priceType": "FIXED" }
      ],
      "city": "Sao Paulo",
      "state": "SP",
      "latitude": "-23.550520",
      "longitude": "-46.633308",
      "isAvailable": true
    }
  ]
}
```

#### FeaturedProvider Fields

| Field | Type | Description |
|---|---|---|
| `id` | `string` | Provider UUID |
| `businessName` | `string` | Provider business/display name |
| `averageRating` | `number` | Average rating (0-5) |
| `reviewCount` | `number` | Total number of reviews |
| `services` | `ProviderService[]` | Services offered with pricing |
| `services[].name` | `string` | Service name |
| `services[].priceBase` | `number` | Base price |
| `services[].priceType` | `string` | `FIXED`, `HOURLY`, or `VARIABLE` |
| `city` | `string` | Provider city |
| `state` | `string` | Provider state (2-letter code) |
| `latitude` | `string` | Latitude for map display |
| `longitude` | `string` | Longitude for map display |
| `isAvailable` | `boolean` | Whether provider accepts new requests |

#### FeaturedCategory Fields

| Field | Type | Description |
|---|---|---|
| `id` | `string` | Category UUID |
| `name` | `string` | Display name (e.g., "Limpeza") |
| `slug` | `string` | URL-friendly name (e.g., "limpeza") |
| `iconUrl` | `string \| null` | Icon URL (may be null) |

#### SDUI Layout Components

The `layout` array contains screen components for Server-Driven UI rendering:

| Component Type | Config Keys | Action Types |
|---|---|---|
| `search_bar` | `placeholder` | `null` |
| `category_list` | `scroll`, `showSeeAll` | `navigate` → `/search?category={slug}` |
| `category_grid` | `columns`, `showSeeAll` | `navigate` → `/search?category={slug}` |
| `provider_grid` | `columns`, `showRating` | `navigate` → `/providers/{id}` |
| `provider_list` | `showRating` | `navigate` → `/providers/{id}` |
| `banner_carousel` | `auto_play`, `interval` | `external_link` → `url` |

**Action templates** support `{field}` substitution from the item data:
- `/providers/{id}` → `/providers/059d690e-aada-479a-980f-bd615846940e`
- `/search?category={slug}` → `/search?category=limpeza`

### 5.2 Search

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
  "description": "Servicos eletricos residenciais e comerciais...",
  "averageRating": 4.8,
  "reviewCount": 23,
  "city": "Sao Paulo",
  "state": "SP",
  "latitude": "-23.550520",
  "longitude": "-46.633308",
  "isAvailable": true,
  "services": [
    { "id": "uuid", "name": "Instalacao eletrica", "priceBase": 120, "priceType": "FIXED" }
  ],
  "workLocations": [
    { "id": "uuid", "name": "Escritorio Central", "city": "Sao Paulo", "state": "SP" }
  ],
  "recentReviews": [
    { "id": "uuid", "rating": 5, "comment": "Excelente servico!", "createdAt": "2026-04-30T15:00:00Z" }
  ]
}
```

### 5.8 List Providers (API Direct)

For custom filtering beyond the home endpoint. Accessible via Kong.

```bash
# List providers sorted by rating, limited to 10, only available
curl -H "Host: gateway.domestic.local" \
  "http://192.168.3.203/v1/providers?sort=rating&limit=10&available=true"
```

**Query Parameters:**

| Param | Type | Description |
|---|---|---|
| `sort` | `string` | Sort field: `rating` (default: `created_at`) |
| `limit` | `number` | Max results |
| `available` | `boolean` | Filter only available providers |

**Success (200):**
```json
[
  {
    "id": "uuid",
    "businessName": "Maria Servicos",
    "averageRating": "4.9",
    "isAvailable": true,
    "city": "Sao Paulo",
    "state": "SP",
    "latitude": "-23.550520",
    "longitude": "-46.633308",
    "services": [
      { "id": "uuid", "name": "Limpeza", "priceBase": 150, "priceType": "FIXED" }
    ],
    "reviewCount": 127
  }
]
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

5. POST /bff/onboarding/verify/email
    Body: { email: "user@example.com" }
    → Check if email is available (debounced, 500ms)

6. POST /bff/onboarding/verify/phone
    Body: { phone: "11999999999" }
    → Check if phone is available (debounced, 500ms)

7. POST /bff/onboarding/verify/document
    Body: { document: "12345678909" }
    → Check if CPF/CNPJ is available (debounced, 500ms)

8. POST /bff/onboarding/register
    Body: { email, password, firstName, lastName, phone, cpf }
    → Create user in Keycloak + API
    Response: { keycloakId, email, success, message }

9. POST /bff/auth/terms/check-pending
    Body: { userId: "<keycloakId>" }
    → Check if user needs to accept terms
    Response: { hasPending: true, currentVersion: "1.0.0", lastAcceptedVersion: null }

10. POST /bff/auth/terms/accept
    Body: { userId: "<keycloakId>", termsVersionId: "<version-id>" }
    → Accept terms
    Response: { success: true, message: "Termos de uso aceitos", termsVersion: "1.0.0" }

11. → Navigate to Main App (Tab Bar)
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
| `bff-verify-email-route` | `/bff/onboarding/verify/email` | BFF (rate limit: 5/min) |
| `bff-verify-phone-route` | `/bff/onboarding/verify/phone` | BFF (rate limit: 5/min) |
| `bff-verify-document-route` | `/bff/onboarding/verify/document` | BFF (rate limit: 3/min) |
| `bff-terms-public-route` | `/bff/auth/terms/current`<br>`/bff/auth/terms/versions`<br>`/bff/auth/terms/check-pending`<br>`/bff/auth/terms/accept` | BFF |
| `bff-public-route` | `/bff/app-config`<br>`/bff/home`<br>`/bff/search`<br>`/bff/health` | BFF |
| `api-public-route` | `/v1/categories`<br>`/v1/services`<br>`/v1/providers` | API |
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

---

## Database Connections

### External Access (via Ingress TCP Passthrough)

All databases are accessible through the Ingress Controller using DNS names:

| Database | DNS Link | Port | User | Password | Connection String |
|---|---|---|---|---|---|
| **PostgreSQL** | `postgres.domestic.local` | `5432` | `domestic` | `postgres1234` | `postgresql://domestic:postgres1234@postgres.domestic.local:5432/domestic_postgres` |
| **MongoDB** | `mongo.domestic.local` | `27017` | — | — | `mongodb://mongo.domestic.local:27017/domestic_mongo` |
| **Redis** | `redis.domestic.local` | `6379` | — | — | `redis://redis.domestic.local:6379` |

> DNS `*.domestic.local` resolve para `192.168.3.203` via dnsmasq.

### DataGrip Connection Setup

1. **PostgreSQL**
   - Host: `192.168.3.203`
   - Port: `5432`
   - User: `domestic`
   - Password: `postgres1234`
   - Database: `domestic_postgres`

2. **MongoDB**
   - Host: `192.168.3.203`
   - Port: `27017`
   - Database: `domestic_mongo`
   - Auth: None

3. **Redis**
   - Host: `192.168.3.203`
   - Port: `6379`
   - Auth: None

### Web Panels

| Service | URL | User | Password |
|---|---|---|---|
| **RabbitMQ** | `http://192.168.3.60:30672` | `domestic` | `backendapi123` |
| **MinIO** | `http://192.168.3.60:30901` | `domestic` | `minioadmin` |
| **Keycloak** | `http://keycloak.domestic.local` | `domestic` | `admin` |
| **ArgoCD** | `http://argocd.domestic.local` | `admin` | *(auto-generated)* |

---

## Route Test Results (2026-05-01)

All routes tested via Kong (`Host: gateway.domestic.local`) at `http://192.168.3.203`.

| # | Route | Method | Status | Notes |
|---|---|---|---|---|
| 1 | `/bff/app-config` | GET | ✅ 200 | Returns tab bar config, feature flags, version |
| 2 | `/bff/health` | GET | ✅ 200 | `{"status":true}` |
| 3 | `/bff/home` | GET | ✅ 200 | 8 categories, 2 featured providers |
| 4 | `/bff/search?q=eletricista` | GET | ✅ 200 | Returns matching providers |
| 5 | `/bff/auth/terms/current` | GET | ✅ 200 | Returns v1.0.0 terms |
| 6 | `/bff/auth/terms/versions` | GET | ✅ 200 | Returns list of all versions |
| 7 | `/bff/auth/terms/check-pending` | POST | ⚠️ 400 | Expected for invalid userId (needs valid UUID) |
| 8 | `/bff/auth/terms/accept` | POST | ⚠️ 400 | Expected for invalid userId (needs valid UUID) |
| 9 | `/bff/onboarding/verification/send` | POST | ✅ 200 | QA Mode: code `0000` |
| 10 | `/bff/onboarding/verification/verify` | POST | ✅ 200 | `{"verified":true}` |
| 11 | `/bff/onboarding/cep/01001000` | GET | ✅ 200 | Returns São Paulo address |
| 12 | `/bff/auth/forgot-password` | POST | ⚠️ 404 | Expected for non-existent email |
| 13 | `/bff/onboarding/verify/email` | POST | ✅ 200 | `{"available":true,"valid":true,"field":"email"}` |
| 14 | `/bff/onboarding/verify/phone` | POST | ✅ 200 | `{"available":true,"valid":true,"field":"phone"}` |
| 15 | `/bff/onboarding/verify/document` | POST | ✅ 200 | `{"available":true,"valid":true,"field":"document"}` |
| 16 | `/bff/onboarding/verify/email` (6th req) | POST | ✅ 429 | Rate limit triggered, custom error message |
| 17 | `/bff/onboarding/verify/document` (4th req) | POST | ✅ 429 | Rate limit triggered (3/min limit) |
| 18 | `/bff/onboarding/verify/email` (invalid) | POST | ✅ 400 | Validation error: "Formato de e-mail inválido" |
| 19 | `/bff/onboarding/verify/phone` (invalid) | POST | ✅ 400 | Validation error: "Telefone deve conter 10 ou 11 dígitos" |
| 20 | `/bff/onboarding/verify/document` (invalid) | POST | ✅ 400 | Validation error: "Documento deve conter entre 8 e 20 caracteres" |
| 21 | `/v1/categories` | GET | ✅ 200 | 8 categories (Limpeza, Encanamento, etc.) |
| 22 | `/v1/providers?sort=rating&available=true` | GET | ✅ 200 | 2 providers with services, location |
