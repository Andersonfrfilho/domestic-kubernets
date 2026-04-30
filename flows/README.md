# Flows — Integration Test Scripts

Curl-based flow scripts que testam o stack completo via **Kong**. Todos os requests passam pelo Kong Ingress (`Host: kong.domestic.local`).

## Setup

```bash
cp .env.example .env
# Edite os valores conforme seu ambiente
```

## Prerequisites

- Stack rodando (Docker Compose ou K8s)
- Kong acessível no IP configurado (padrão: `192.168.1.200`)
- `python3` instalado (para formatar JSON)
- Migrações do banco aplicadas

## Flows

### `onboarding.flow.sh` — Fluxo completo de cadastro

Executa o onboarding ponta a ponta:

```
1. GET  /bff/auth/terms/current         → Versão atual dos termos
2. POST /bff/onboarding/verification/send  → Envia código (QA mode: email=0000)
3. POST /bff/onboarding/verification/verify → Verifica código (QA mode)
4. POST /bff/onboarding/register        → Registra usuário (Keycloak + API)
5. GET  /bff/onboarding/cep/01001000    → Consulta CEP
6. POST /bff/auth/terms/accept          → Aceita termos
```

```bash
./flows/onboarding.flow.sh
./flows/onboarding.flow.sh .env.staging
```

### `terms.flow.sh` — Fluxo de termos de uso

Testa o ciclo de vida de versões de termos:

```
1. GET  /bff/auth/terms/current     → Versão ativa atual
2. GET  /bff/auth/terms/versions    → Lista todas as versões
3. POST /bff/auth/terms/check-pending → Verifica termos pendentes
4. POST /bff/auth/terms/accept      → Aceita termos
5. POST /bff/auth/terms/check-pending → Confirma que não há pendência
```

```bash
./flows/terms.flow.sh <user-keycloak-id>
./flows/terms.flow.sh abc-123-def .env.staging
```

## QA Mode

Em desenvolvimento, os códigos de verificação são determinísticos:

| Tipo | Código |
|---|---|
| Email | `0000` |
| SMS/Phone | Últimos 4 dígitos do telefone |

## Architecture

```
curl → Kong (192.168.1.200) → BFF → API → PostgreSQL
                                    ↓
                              Keycloak / RabbitMQ / MinIO
```

Todos os scripts enviam o header `Host: kong.domestic.local` para o Kong rotear corretamente.
