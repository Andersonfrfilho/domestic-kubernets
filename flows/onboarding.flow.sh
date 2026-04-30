#!/bin/bash
#
# Onboarding Flow — Full registration via Kong
#
# Usage:
#   ./flows/onboarding.flow.sh              # uses .env
#   ./flows/onboarding.flow.sh .env.local   # uses custom env file
#
# Flow:
#   1. GET  /bff/auth/terms/current        → Get current terms version
#   2. POST /bff/onboarding/verification/send  → Send verification code (QA mode)
#   3. POST /bff/onboarding/verification/verify → Verify code (QA mode)
#   4. POST /bff/onboarding/register       → Register user (Keycloak + API)
#   5. GET  /bff/onboarding/cep/01001000   → Lookup CEP
#   6. POST /bff/auth/terms/accept         → Accept terms
#

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="${1:-$SCRIPT_DIR/.env}"

if [ ! -f "$ENV_FILE" ]; then
  echo "Error: $ENV_FILE not found. Copy .env.example to .env and fill in values."
  exit 1
fi

source "$ENV_FILE"
source "$SCRIPT_DIR/utils.sh"

header "ONBOARDING FLOW"

# ── Step 1: Get current terms version ──────────────────────────────
step "1. Get current terms version"
TERMS_RESPONSE=$(curl -s -w "\n%{http_code}" \
  "${KONG_URL}/bff/auth/terms/current" \
  -H "Content-Type: application/json" \
  -H "Host: kong.domestic.local")

TERMS_HTTP=$(echo "$TERMS_RESPONSE" | tail -1)
TERMS_BODY=$(echo "$TERMS_RESPONSE" | sed '$d')

if [ "$TERMS_HTTP" = "200" ]; then
  success "Got current terms version"
  echo "$TERMS_BODY" | python3 -m json.tool 2>/dev/null || echo "$TERMS_BODY"
  TERMS_VERSION_ID=$(echo "$TERMS_BODY" | python3 -c "import sys,json; print(json.load(sys.stdin).get('id',''))" 2>/dev/null || echo "")
else
  error "Failed to get terms (HTTP $TERMS_HTTP)"
  echo "$TERMS_BODY"
  TERMS_VERSION_ID=""
fi
echo ""

# ── Step 2: Send verification code (QA Mode) ───────────────────────
step "2. Send verification code (QA Mode — email=0000)"
VERIFY_RESPONSE=$(curl -s -w "\n%{http_code}" \
  "${KONG_URL}/bff/onboarding/verification/send" \
  -X POST \
  -H "Content-Type: application/json" \
  -H "Host: kong.domestic.local" \
  -d "{\"destination\":\"${REGISTER_EMAIL}\",\"type\":\"email\"}")

VERIFY_HTTP=$(echo "$VERIFY_RESPONSE" | tail -1)
VERIFY_BODY=$(echo "$VERIFY_RESPONSE" | sed '$d')

if [ "$VERIFY_HTTP" = "200" ]; then
  success "Verification code sent (QA Mode)"
  echo "$VERIFY_BODY" | python3 -m json.tool 2>/dev/null || echo "$VERIFY_BODY"
else
  error "Failed to send verification code (HTTP $VERIFY_HTTP)"
  echo "$VERIFY_BODY"
fi
echo ""

# ── Step 3: Verify code (QA Mode — code=0000) ─────────────────────
step "3. Verify code (QA Mode — code=0000)"
VERIFY_CODE_RESPONSE=$(curl -s -w "\n%{http_code}" \
  "${KONG_URL}/bff/onboarding/verification/verify" \
  -X POST \
  -H "Content-Type: application/json" \
  -H "Host: kong.domestic.local" \
  -d "{\"destination\":\"${REGISTER_EMAIL}\",\"type\":\"email\",\"code\":\"0000\"}")

VERIFY_CODE_HTTP=$(echo "$VERIFY_CODE_RESPONSE" | tail -1)
VERIFY_CODE_BODY=$(echo "$VERIFY_CODE_RESPONSE" | sed '$d')

if [ "$VERIFY_CODE_HTTP" = "200" ]; then
  success "Code verified"
  echo "$VERIFY_CODE_BODY" | python3 -m json.tool 2>/dev/null || echo "$VERIFY_CODE_BODY"
else
  error "Failed to verify code (HTTP $VERIFY_CODE_HTTP)"
  echo "$VERIFY_CODE_BODY"
fi
echo ""

# ── Step 4: Register user ─────────────────────────────────────────
step "4. Register user"
REGISTER_RESPONSE=$(curl -s -w "\n%{http_code}" \
  "${KONG_URL}/bff/onboarding/register" \
  -X POST \
  -H "Content-Type: application/json" \
  -H "Host: kong.domestic.local" \
  -d "{
    \"email\":\"${REGISTER_EMAIL}\",
    \"password\":\"${REGISTER_PASSWORD}\",
    \"firstName\":\"${REGISTER_FIRST_NAME}\",
    \"lastName\":\"${REGISTER_LAST_NAME}\",
    \"phone\":\"${REGISTER_PHONE}\",
    \"cpf\":\"${REGISTER_CPF}\"
  }")

REGISTER_HTTP=$(echo "$REGISTER_RESPONSE" | tail -1)
REGISTER_BODY=$(echo "$REGISTER_RESPONSE" | sed '$d')

if [ "$REGISTER_HTTP" = "201" ] || [ "$REGISTER_HTTP" = "200" ]; then
  success "User registered"
  echo "$REGISTER_BODY" | python3 -m json.tool 2>/dev/null || echo "$REGISTER_BODY"
  KEYCLOAK_ID=$(echo "$REGISTER_BODY" | python3 -c "import sys,json; print(json.load(sys.stdin).get('keycloakId',''))" 2>/dev/null || echo "")
  if [ -n "$KEYCLOAK_ID" ]; then
    success "Keycloak ID: $KEYCLOAK_ID"
  fi
else
  error "Failed to register (HTTP $REGISTER_HTTP)"
  echo "$REGISTER_BODY"
  KEYCLOAK_ID=""
fi
echo ""

# ── Step 5: Lookup CEP ────────────────────────────────────────────
step "5. Lookup CEP (01001000)"
CEP_RESPONSE=$(curl -s -w "\n%{http_code}" \
  "${KONG_URL}/bff/onboarding/cep/01001000" \
  -H "Content-Type: application/json" \
  -H "Host: kong.domestic.local")

CEP_HTTP=$(echo "$CEP_RESPONSE" | tail -1)
CEP_BODY=$(echo "$CEP_RESPONSE" | sed '$d')

if [ "$CEP_HTTP" = "200" ]; then
  success "CEP found"
  echo "$CEP_BODY" | python3 -m json.tool 2>/dev/null || echo "$CEP_BODY"
else
  error "Failed to lookup CEP (HTTP $CEP_HTTP)"
  echo "$CEP_BODY"
fi
echo ""

# ── Step 6: Accept terms ──────────────────────────────────────────
step "6. Accept terms"
if [ -n "$KEYCLOAK_ID" ]; then
  ACCEPT_RESPONSE=$(curl -s -w "\n%{http_code}" \
    "${KONG_URL}/bff/auth/terms/accept" \
    -X POST \
    -H "Content-Type: application/json" \
    -H "Host: kong.domestic.local" \
    -d "{\"userId\":\"${KEYCLOAK_ID}\",\"termsVersionId\":\"${TERMS_VERSION_ID}\"}")

  ACCEPT_HTTP=$(echo "$ACCEPT_RESPONSE" | tail -1)
  ACCEPT_BODY=$(echo "$ACCEPT_RESPONSE" | sed '$d')

  if [ "$ACCEPT_HTTP" = "200" ]; then
    success "Terms accepted"
    echo "$ACCEPT_BODY" | python3 -m json.tool 2>/dev/null || echo "$ACCEPT_BODY"
  else
    error "Failed to accept terms (HTTP $ACCEPT_HTTP)"
    echo "$ACCEPT_BODY"
  fi
else
  warn "Skipping terms acceptance — no Keycloak ID from registration"
fi
echo ""

# ── Summary ───────────────────────────────────────────────────────
header "FLOW COMPLETE"
echo "  Email:    $REGISTER_EMAIL"
echo "  Keycloak: ${KEYCLOAK_ID:-N/A}"
echo "  Terms:    ${TERMS_VERSION_ID:-N/A}"
echo ""
