#!/bin/bash
#
# Terms Versioning Flow — Full terms lifecycle via Kong
#
# Usage:
#   ./flows/terms.flow.sh <user-keycloak-id>          # uses .env
#   ./flows/terms.flow.sh <user-keycloak-id> .env.local  # uses custom env file
#
# Flow:
#   1. GET  /bff/auth/terms/current     → Get current active version
#   2. GET  /bff/auth/terms/versions    → List all versions
#   3. POST /bff/auth/terms/check-pending → Check if user has pending terms
#   4. POST /bff/auth/terms/accept      → Accept current terms
#   5. POST /bff/auth/terms/check-pending → Verify no longer pending
#

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ -z "$1" ]; then
  echo "Usage: $0 <user-keycloak-id> [env-file]"
  echo ""
  echo "  user-keycloak-id  The Keycloak user ID to check/accept terms for"
  echo "  env-file          Optional path to .env file (default: .env)"
  exit 1
fi

USER_ID="$1"
ENV_FILE="${2:-$SCRIPT_DIR/.env}"

if [ ! -f "$ENV_FILE" ]; then
  echo "Error: $ENV_FILE not found. Copy .env.example to .env and fill in values."
  exit 1
fi

source "$ENV_FILE"
source "$SCRIPT_DIR/utils.sh"

header "TERMS VERSIONING FLOW"
echo "  User ID: $USER_ID"
echo ""

# ── Step 1: Get current terms version ──────────────────────────────
step "1. Get current active terms version"
CURRENT_RESPONSE=$(curl -s -w "\n%{http_code}" \
  "${KONG_URL}/bff/auth/terms/current" \
  -H "Content-Type: application/json" \
  -H "Host: kong.domestic.local")

CURRENT_HTTP=$(echo "$CURRENT_RESPONSE" | tail -1)
CURRENT_BODY=$(echo "$CURRENT_RESPONSE" | sed '$d')

if [ "$CURRENT_HTTP" = "200" ]; then
  success "Got current terms version"
  echo "$CURRENT_BODY" | python3 -m json.tool 2>/dev/null || echo "$CURRENT_BODY"
  CURRENT_VERSION_ID=$(echo "$CURRENT_BODY" | python3 -c "import sys,json; print(json.load(sys.stdin).get('id',''))" 2>/dev/null || echo "")
  CURRENT_VERSION=$(echo "$CURRENT_BODY" | python3 -c "import sys,json; print(json.load(sys.stdin).get('version',''))" 2>/dev/null || echo "")
else
  error "Failed to get current terms (HTTP $CURRENT_HTTP)"
  echo "$CURRENT_BODY"
  CURRENT_VERSION_ID=""
  CURRENT_VERSION=""
fi
echo ""

# ── Step 2: List all versions ─────────────────────────────────────
step "2. List all terms versions"
LIST_RESPONSE=$(curl -s -w "\n%{http_code}" \
  "${KONG_URL}/bff/auth/terms/versions" \
  -H "Content-Type: application/json" \
  -H "Host: kong.domestic.local")

LIST_HTTP=$(echo "$LIST_RESPONSE" | tail -1)
LIST_BODY=$(echo "$LIST_RESPONSE" | sed '$d')

if [ "$LIST_HTTP" = "200" ]; then
  success "Got terms versions list"
  echo "$LIST_BODY" | python3 -m json.tool 2>/dev/null || echo "$LIST_BODY"
else
  error "Failed to list versions (HTTP $LIST_HTTP)"
  echo "$LIST_BODY"
fi
echo ""

# ── Step 3: Check pending terms ───────────────────────────────────
step "3. Check if user has pending terms (before accept)"
PENDING_RESPONSE=$(curl -s -w "\n%{http_code}" \
  "${KONG_URL}/bff/auth/terms/check-pending" \
  -X POST \
  -H "Content-Type: application/json" \
  -H "Host: kong.domestic.local" \
  -d "{\"userId\":\"${USER_ID}\"}")

PENDING_HTTP=$(echo "$PENDING_RESPONSE" | tail -1)
PENDING_BODY=$(echo "$PENDING_RESPONSE" | sed '$d')

if [ "$PENDING_HTTP" = "200" ]; then
  success "Got pending status"
  echo "$PENDING_BODY" | python3 -m json.tool 2>/dev/null || echo "$PENDING_BODY"
  HAS_PENDING=$(echo "$PENDING_BODY" | python3 -c "import sys,json; print(json.load(sys.stdin).get('hasPending',False))" 2>/dev/null || echo "unknown")
else
  error "Failed to check pending (HTTP $PENDING_HTTP)"
  echo "$PENDING_BODY"
  HAS_PENDING="unknown"
fi
echo ""

# ── Step 4: Accept terms ──────────────────────────────────────────
step "4. Accept current terms"
if [ -n "$CURRENT_VERSION_ID" ]; then
  ACCEPT_RESPONSE=$(curl -s -w "\n%{http_code}" \
    "${KONG_URL}/bff/auth/terms/accept" \
    -X POST \
    -H "Content-Type: application/json" \
    -H "Host: kong.domestic.local" \
    -d "{\"userId\":\"${USER_ID}\",\"termsVersionId\":\"${CURRENT_VERSION_ID}\"}")

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
  warn "Skipping — no current version ID available"
fi
echo ""

# ── Step 5: Verify no longer pending ──────────────────────────────
step "5. Check pending terms (after accept)"
PENDING2_RESPONSE=$(curl -s -w "\n%{http_code}" \
  "${KONG_URL}/bff/auth/terms/check-pending" \
  -X POST \
  -H "Content-Type: application/json" \
  -H "Host: kong.domestic.local" \
  -d "{\"userId\":\"${USER_ID}\"}")

PENDING2_HTTP=$(echo "$PENDING2_RESPONSE" | tail -1)
PENDING2_BODY=$(echo "$PENDING2_RESPONSE" | sed '$d')

if [ "$PENDING2_HTTP" = "200" ]; then
  success "Got updated pending status"
  echo "$PENDING2_BODY" | python3 -m json.tool 2>/dev/null || echo "$PENDING2_BODY"
  HAS_PENDING_AFTER=$(echo "$PENDING2_BODY" | python3 -c "import sys,json; print(json.load(sys.stdin).get('hasPending',False))" 2>/dev/null || echo "unknown")
else
  error "Failed to check pending (HTTP $PENDING2_HTTP)"
  echo "$PENDING2_BODY"
  HAS_PENDING_AFTER="unknown"
fi
echo ""

# ── Summary ───────────────────────────────────────────────────────
header "FLOW COMPLETE"
echo "  User ID:         $USER_ID"
echo "  Current version: ${CURRENT_VERSION:-N/A}"
echo "  Pending before:  $HAS_PENDING"
echo "  Pending after:   $HAS_PENDING_AFTER"
echo ""

if [ "$HAS_PENDING_AFTER" = "False" ] || [ "$HAS_PENDING_AFTER" = "false" ]; then
  success "User is up to date with terms"
else
  warn "User may still have pending terms"
fi
echo ""
