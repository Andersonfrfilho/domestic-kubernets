# API de Verificação de Campos - Cadastro (React Native)

**Data:** 2026-05-01  
**Status:** 📝 Especificação para implementação  
**Prioridade:** Alta

---

## 🎯 Visão Geral

Endpoints para validação em tempo real de campos durante o cadastro no app React Native, com proteções contra ataques de stress e chamadas excessivas.

---

## 📋 Rotas Necessárias

### 1. Verificar Email

**Rota Kong:** `POST /bff/onboarding/verify/email`

**Backend:** `POST /onboarding/verify/email`

**Descrição:** Valida se email está disponível para cadastro

**Request:**
```json
{
  "email": "usuario@email.com"
}
```

**Response 200 - Email disponível:**
```json
{
  "available": true,
  "valid": true
}
```

**Response 409 - Email já cadastrado:**
```json
{
  "statusCode": 409,
  "error": "EMAIL_ALREADY_EXISTS",
  "message": "E-mail já está em uso",
  "field": "email"
}
```

**Response 422 - Email inválido:**
```json
{
  "statusCode": 422,
  "error": "INVALID_EMAIL",
  "message": "Formato de e-mail inválido",
  "field": "email"
}
```

**Response 429 - Rate limit:**
```json
{
  "statusCode": 429,
  "error": "RATE_LIMIT_EXCEEDED",
  "message": "Muitas tentativas. Tente novamente em 5 minutos.",
  "retryAfter": 300
}
```

---

### 2. Verificar Telefone

**Rota Kong:** `POST /bff/onboarding/verify/phone`

**Backend:** `POST /onboarding/verify/phone`

**Descrição:** Valida se telefone está disponível para cadastro

**Request:**
```json
{
  "phone": "11999999999"
}
```

**Response 200 - Telefone disponível:**
```json
{
  "available": true,
  "valid": true
}
```

**Response 409 - Telefone já cadastrado:**
```json
{
  "statusCode": 409,
  "error": "PHONE_ALREADY_EXISTS",
  "message": "Telefone já está cadastrado",
  "field": "phone"
}
```

**Response 422 - Telefone inválido:**
```json
{
  "statusCode": 422,
  "error": "INVALID_PHONE",
  "message": "Formato de telefone inválido",
  "field": "phone"
}
```

**Response 429 - Rate limit:**
```json
{
  "statusCode": 429,
  "error": "RATE_LIMIT_EXCEEDED",
  "message": "Muitas tentativas. Tente novamente em 5 minutos.",
  "retryAfter": 300
}
```

---

### 3. Verificar CPF

**Rota Kong:** `POST /bff/onboarding/verify/cpf`

**Backend:** `POST /onboarding/verify/cpf`

**Descrição:** Valida se CPF está disponível e é válido

**Request:**
```json
{
  "cpf": "12345678909"
}
```

**Response 200 - CPF disponível:**
```json
{
  "available": true,
  "valid": true
}
```

**Response 409 - CPF já cadastrado:**
```json
{
  "statusCode": 409,
  "error": "CPF_ALREADY_EXISTS",
  "message": "CPF já está cadastrado",
  "field": "cpf"
}
```

**Response 422 - CPF inválido:**
```json
{
  "statusCode": 422,
  "error": "INVALID_CPF",
  "message": "CPF inválido",
  "field": "cpf"
}
```

**Response 429 - Rate limit:**
```json
{
  "statusCode": 429,
  "error": "RATE_LIMIT_EXCEEDED",
  "message": "Muitas tentativas. Tente novamente em 5 minutos.",
  "retryAfter": 300
}
```

---

## 🛡️ Requisitos de Segurança

### Rate Limiting (Backend)

```yaml
windowMs: 60000        # 1 minuto
maxPerField: 5         # 5 requisições por campo
maxPerSession: 10      # 10 requisições totais por sessão
blockDuration: 300000  # 5 minutos de bloqueio
```

### Debounce (Frontend)

```typescript
delay: 500ms           // Aguarda 500ms após parar de digitar
minLength: {
  email: 5,
  phone: 10,
  cpf: 11
}
```

### Proteções

- ✅ Não validar campo vazio
- ✅ Não validar enquanto usuário digita (debounce)
- ✅ Cancelar requisição anterior se nova digitação começar
- ✅ Mostrar indicador "Verificando..." durante validação
- ✅ Tratar erro 429 gracefulmente (não mostrar erro, apenas parar de verificar)

---

## 🔧 Configuração Kong

### Routes

```yaml
# Email verification
- name: onboarding-verify-email
  paths: [/bff/onboarding/verify/email]
  methods: [POST]
  strip_path: true
  plugins:
    - rate-limiting:
        minute: 5
        policy: local
        fault_tolerant: true
        hide_client_headers: true

# Phone verification
- name: onboarding-verify-phone
  paths: [/bff/onboarding/verify/phone]
  methods: [POST]
  strip_path: true
  plugins:
    - rate-limiting:
        minute: 5
        policy: local
        fault_tolerant: true
        hide_client_headers: true

# CPF verification
- name: onboarding-verify-cpf
  paths: [/bff/onboarding/verify/cpf]
  methods: [POST]
  strip_path: true
  plugins:
    - rate-limiting:
        minute: 5
        policy: local
        fault_tolerant: true
        hide_client_headers: true
```

### Apply Kong Config

```bash
cd /Users/anderson.filho/Documents/personal/domestic/kubernetes/flows

# Edit onboarding flow
vim onboarding.flow.js

# Add routes after existing onboarding routes
# Run the flow
./onboarding.flow.sh
```

---

## 📱 Implementação Frontend

### Hook useFieldVerification

```typescript
// src/modules/auth/hooks/useFieldVerification.ts
import { useState, useRef, useCallback } from 'react';
import { apiClient } from '@/shared/services/api-client';

export function useFieldVerification() {
  const [checkingFields, setCheckingFields] = useState<Record<string, boolean>>({});
  const [verificationResults, setVerificationResults] = useState<Record<string, any>>({});
  
  const debounceTimers = useRef<Record<string, NodeJS.Timeout>>({});
  const abortControllers = useRef<Record<string, AbortController>>({});

  const verifyField = useCallback(async (field: string, value: string) => {
    // Cancela verificação anterior
    if (abortControllers.current[field]) {
      abortControllers.current[field].abort();
    }

    const controller = new AbortController();
    abortControllers.current[field] = controller;

    setCheckingFields(prev => ({ ...prev, [field]: true }));

    try {
      const response = await apiClient.post(
        `/bff/onboarding/verify/${field}`,
        { [field]: value },
        { signal: controller.signal }
      );

      setVerificationResults(prev => ({
        ...prev,
        [field]: {
          isValid: response.data.valid,
          isAvailable: response.data.available,
        }
      }));

      return { isValid: true, isAvailable: true };
    } catch (error: any) {
      if (error.name === 'AbortError') return null;

      if (error.response?.status === 409) {
        setVerificationResults(prev => ({
          ...prev,
          [field]: {
            isValid: true,
            isAvailable: false,
            error: error.response.data.message,
          }
        }));
        return { isValid: true, isAvailable: false };
      }

      if (error.response?.status === 429) {
        console.warn('[RATE LIMIT] Exceeded for field:', field);
        return null;
      }

      return { isValid: false, isAvailable: false };
    } finally {
      setCheckingFields(prev => ({ ...prev, [field]: false }));
    }
  }, []);

  const verifyWithDebounce = useCallback((field: string, value: string, delay = 500) => {
    if (debounceTimers.current[field]) {
      clearTimeout(debounceTimers.current[field]);
    }

    const minLength = { email: 5, phone: 10, cpf: 11 }[field] || 1;
    if (!value || value.replace(/\D/g, '').length < minLength) return;

    debounceTimers.current[field] = setTimeout(() => {
      verifyField(field, value);
    }, delay);
  }, [verifyField]);

  return {
    checkingFields,
    verificationResults,
    verifyWithDebounce,
  };
}
```

### Uso no RegisterScreen

```typescript
// src/modules/auth/screens/register/register.screen.tsx
import { useFieldVerification } from '@/modules/auth/hooks/useFieldVerification';

export default function RegisterScreen() {
  const { 
    checkingFields, 
    verificationResults, 
    verifyWithDebounce 
  } = useFieldVerification();

  const handleEmailChange = (value: string) => {
    verifyWithDebounce('email', value, 500);
  };

  const handlePhoneChange = (value: string) => {
    verifyWithDebounce('phone', value, 500);
  };

  const handleCpfChange = (value: string) => {
    verifyWithDebounce('cpf', value, 500);
  };

  return (
    <RegisterForm
      control={control}
      errors={errors}
      checkingFields={checkingFields}
      serverError={verificationResults}
      onEmailChange={handleEmailChange}
      onPhoneChange={handlePhoneChange}
      onCpfChange={handleCpfChange}
    />
  );
}
```

### UI Components

```typescript
// Mostrar indicador de verificação
{checkingFields.email && (
  <View style={styles.checkingIndicator}>
    <ActivityIndicator size="small" color={theme.colors.primary.DEFAULT} />
    <Text style={styles.checkingText}>Verificando e-mail...</Text>
  </View>
)}

// Mostrar erro de campo já cadastrado
{verificationResults.email?.isAvailable === false && (
  <View style={styles.fieldErrorContainer}>
    <Ionicons name="alert-circle" size={14} color={theme.colors.status.error} />
    <Text style={styles.fieldErrorMessage}>
      {verificationResults.email.error}
    </Text>
    <TouchableOpacity onPress={() => router.push('/forgot-password')}>
      <Text style={styles.forgotPasswordLink}>Esqueci minha senha</Text>
    </TouchableOpacity>
  </View>
)}
```

---

## ✅ Checklist de Implementação

### Backend (BFF)
- [ ] Criar endpoint `POST /onboarding/verify/email`
- [ ] Criar endpoint `POST /onboarding/verify/phone`
- [ ] Criar endpoint `POST /onboarding/verify/cpf`
- [ ] Implementar validação de email (regex + disponibilidade)
- [ ] Implementar validação de telefone (regex + disponibilidade)
- [ ] Implementar validação de CPF (algoritmo + disponibilidade)
- [ ] Configurar rate limiting por IP/campo
- [ ] Retornar erros padronizados (statusCode, error, message, field)
- [ ] Adicionar logs de verificação
- [ ] Testar com Postman/curl

### Kong Gateway
- [ ] Adicionar rota `/bff/onboarding/verify/email`
- [ ] Adicionar rota `/bff/onboarding/verify/phone`
- [ ] Adicionar rota `/bff/onboarding/verify/cpf`
- [ ] Configurar rate limiting plugin (5 req/min)
- [ ] Testar rotas via gateway
- [ ] Atualizar onboarding.flow.js

### Frontend (React Native)
- [ ] Criar hook `useFieldVerification`
- [ ] Implementar debounce (500ms)
- [ ] Implementar cancelamento (AbortController)
- [ ] Adicionar indicador "Verificando..."
- [ ] Mostrar erro inline no campo
- [ ] Adicionar botão "Esqueci minha senha" no erro de email
- [ ] Tratar erro 429 (silencioso)
- [ ] Testar digitação rápida
- [ ] Testar com backend mockado

### Testes
- [ ] Testar validação de email válido
- [ ] Testar validação de email já cadastrado
- [ ] Testar validação de email inválido
- [ ] Testar validação de telefone válido
- [ ] Testar validação de telefone já cadastrado
- [ ] Testar validação de CPF válido
- [ ] Testar validação de CPF já cadastrado
- [ ] Testar rate limiting (6+ requisições)
- [ ] Testar debounce (digitação rápida)
- [ ] Testar cancelamento (nova digitação)

---

## 📊 Monitoramento

### Métricas (Backend)

```typescript
// Log de verificação
console.log('[VERIFY] Field check', { 
  field: 'email',
  value: 'user@email.com', 
  result: 'available', // ou 'exists', 'invalid'
  duration: 123,
  ip: '192.168.1.1'
});

// Log de rate limit
console.warn('[RATE LIMIT] Exceeded', {
  field: 'email',
  ip: '192.168.1.1',
  attempts: 6,
  windowMs: 60000
});
```

### Dashboard (Grafana/Prometheus)

- Requests por minuto por endpoint
- Taxa de aprovação vs reprovação
- Rate limit hits
- Response time percentis (p50, p95, p99)
- Erros por tipo (409, 422, 429)

---

## 🔗 Referências

- [README-REACT-NATIVE.md](./README-REACT-NATIVE.md) - Guia principal React Native
- [onboarding.flow.js](./onboarding.flow.js) - Flow de deploy do onboarding
- [../docs/kong-routes.md](../docs/kong-routes.md) - Documentação de rotas Kong

---

**Próximos Passos:**

1. Implementar endpoints no BFF
2. Configurar rotas no Kong
3. Implementar frontend com debounce
4. Testar end-to-end
5. Monitorar métricas

**Status:** 📝 Aguardando implementação
