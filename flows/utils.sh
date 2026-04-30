#!/bin/bash

COLOR_RESET="\033[0m"
COLOR_GREEN="\033[32m"
COLOR_YELLOW="\033[33m"
COLOR_BLUE="\033[34m"
COLOR_RED="\033[31m"
COLOR_CYAN="\033[36m"

step() {
  echo -e "\n${COLOR_CYAN}▸ $1${COLOR_RESET}"
}

success() {
  echo -e "${COLOR_GREEN}  ✓ $1${COLOR_RESET}"
}

warn() {
  echo -e "${COLOR_YELLOW}  ⚠ $1${COLOR_RESET}"
}

error() {
  echo -e "${COLOR_RED}  ✗ $1${COLOR_RESET}"
}

divider() {
  echo -e "${COLOR_BLUE}─────────────────────────────────────────────${COLOR_RESET}"
}

header() {
  echo ""
  divider
  echo -e "${COLOR_BLUE}  $1${COLOR_RESET}"
  divider
}

request() {
  local method=$1
  local url=$2
  local body=$3
  local description=$4

  step "$description"
  echo -e "  ${COLOR_YELLOW}$method $url${COLOR_RESET}"

  if [ -n "$body" ] && [ "$body" != "null" ]; then
    echo -e "  ${COLOR_YELLOW}Body: $body${COLOR_RESET}"
  fi

  local response
  if [ "$method" = "GET" ]; then
    response=$(curl -s -w "\n%{http_code}" "$url" \
      -H "Content-Type: application/json" \
      -H "Host: kong.domestic.local")
  else
    response=$(curl -s -w "\n%{http_code}" "$url" \
      -H "Content-Type: application/json" \
      -H "Host: kong.domestic.local" \
      -d "$body")
  fi

  local http_code
  http_code=$(echo "$response" | tail -1)
  local body_content
  body_content=$(echo "$response" | sed '$d')

  if [ "$http_code" -ge 200 ] && [ "$http_code" -lt 300 ]; then
    success "HTTP $http_code"
  else
    error "HTTP $http_code"
  fi

  echo -e "  $body_content" | python3 -m json.tool 2>/dev/null || echo -e "  $body_content"
  echo ""

  echo "$body_content"
}
