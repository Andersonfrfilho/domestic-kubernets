#!/bin/bash

# Script para testar tracing distribuído
# Gera requisições e mostra como visualizar os traces no Jaeger/Grafana

set -e

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuração
API_URL="${API_URL:-http://localhost:3000}"
BFF_URL="${BFF_URL:-http://localhost:3001}"
JAEGER_URL="${JAEGER_URL:-http://localhost:16686}"
GRAFANA_URL="${GRAFANA_URL:-http://localhost:3000}"
EXAMPLE_URL="${EXAMPLE_URL:-http://localhost:3000}"

echo -e "${BLUE}═══════════════════════════════════════════${NC}"
echo -e "${BLUE}  Distributed Tracing Test Suite${NC}"
echo -e "${BLUE}═══════════════════════════════════════════${NC}\n"

# Função para fazer request e extrair traceId
function test_endpoint() {
  local name=$1
  local url=$2

  echo -e "${YELLOW}Testing: ${name}${NC}"
  echo -e "URL: ${BLUE}${url}${NC}\n"

  # Fazer request
  response=$(curl -s -i "${url}" 2>&1)

  # Extrair headers de trace
  trace_id=$(echo "$response" | grep -i "x-trace-id" | awk '{print $2}' | tr -d '\r')
  request_id=$(echo "$response" | grep -i "x-request-id" | awk '{print $2}' | tr -d '\r')

  # Se não encontrou via headers, tentar extrair do response body
  if [ -z "$trace_id" ]; then
    trace_id=$(echo "$response" | grep -o '"trace[Id]*":"[^"]*' | head -1 | awk -F'"' '{print $4}')
  fi

  echo -e "Response Status:"
  echo "$response" | head -5
  echo ""

  if [ -n "$trace_id" ]; then
    echo -e "${GREEN}✓ Trace ID encontrado: ${BLUE}${trace_id}${NC}\n"
  else
    echo -e "${YELLOW}⚠ Trace ID não encontrado nos headers${NC}\n"
  fi

  # Salvar para uso posterior
  echo "$trace_id"
}

# Menu principal
echo -e "${BLUE}Selecione o teste:${NC}\n"
echo "1) Testar Example App (/tracing/order/*)"
echo "2) Testar API Health (/health)"
echo "3) Testar BFF (/bff/health)"
echo "4) Testar Correlação Logs ↔ Traces"
echo "5) Abrir Jaeger UI"
echo "6) Abrir Grafana Dashboard de Tracing"
echo "0) Sair"
echo ""

read -p "Escolha uma opção: " choice

case $choice in
  1)
    echo -e "\n${BLUE}=== Test: Example App ===${NC}\n"

    order_id="order-$(date +%s)"
    trace_1=$(test_endpoint "Example - POST /tracing/order" "${EXAMPLE_URL}/tracing/order/${order_id}")

    sleep 1

    trace_2=$(test_endpoint "Example - GET /tracing/order (cache hit)" "${EXAMPLE_URL}/tracing/order/${order_id}")

    if [ -n "$trace_1" ]; then
      echo -e "${GREEN}═══════════════════════════════════════════${NC}"
      echo -e "${GREEN}✓ Traces capturados com sucesso!${NC}\n"
      echo -e "TraceID 1: ${BLUE}${trace_1}${NC}"
      echo -e "TraceID 2: ${BLUE}${trace_2}${NC}\n"

      echo -e "${YELLOW}Próximos passos:${NC}"
      echo "1. Abra Jaeger: ${BLUE}${JAEGER_URL}${NC}"
      echo "2. Service → example"
      echo "3. Procure pelos traceIds acima"
      echo ""
      echo -e "${YELLOW}Ou no Grafana:${NC}"
      echo "1. Abra ${BLUE}${GRAFANA_URL}${NC}"
      echo "2. Dashboards → Trace Search by TraceID"
      echo "3. Cole um dos traceIds acima"
    fi
    ;;

  2)
    echo -e "\n${BLUE}=== Test: API Health ===${NC}\n"
    trace=$(test_endpoint "API - /health" "${API_URL}/health")

    if [ -n "$trace" ]; then
      echo -e "${YELLOW}TraceID: ${BLUE}${trace}${NC}"
    fi
    ;;

  3)
    echo -e "\n${BLUE}=== Test: BFF Health ===${NC}\n"
    trace=$(test_endpoint "BFF - /bff/health" "${BFF_URL}/bff/health")

    if [ -n "$trace" ]; then
      echo -e "${YELLOW}TraceID: ${BLUE}${trace}${NC}"
    fi
    ;;

  4)
    echo -e "\n${BLUE}=== Test: Correlação Logs ↔ Traces ===${NC}\n"

    echo -e "${YELLOW}Passo 1: Gerar uma requisição${NC}\n"
    order_id="order-test-$(date +%s)"

    echo "Fazendo requisição para: ${EXAMPLE_URL}/tracing/order/${order_id}"
    trace_id=$(curl -s "${EXAMPLE_URL}/tracing/order/${order_id}" | grep -o '"requestId":"[^"]*' | head -1 | awk -F'"' '{print $4}')

    echo -e "TraceID: ${BLUE}${trace_id}${NC}\n"

    echo -e "${YELLOW}Passo 2: Verificar logs${NC}\n"
    echo "Os logs devem conter: [${trace_id}]"

    # Se estiver em k8s, mostrar comando kubectl
    if command -v kubectl &> /dev/null; then
      echo -e "\n${YELLOW}Para visualizar os logs:${NC}"
      echo "${BLUE}kubectl logs -n domestic deployment/api -c api | grep ${trace_id}${NC}"
    else
      # Se estiver rodando localmente
      log_file="fullstack-monorepo/packages/backend/example/logs/example-*.log"
      if ls ${log_file} 1> /dev/null 2>&1; then
        echo -e "\n${YELLOW}Logs locais encontrados:${NC}"
        grep -i "${trace_id}" ${log_file} 2>/dev/null | head -3 || echo "Ainda não há logs com esse traceId"
      fi
    fi

    echo -e "\n${YELLOW}Passo 3: Correlacionar no Grafana${NC}"
    echo "1. Abra Grafana: ${BLUE}${GRAFANA_URL}${NC}"
    echo "2. Dashboards → Logs"
    echo "3. Procure por logs com [${trace_id}]"
    echo "4. Clique no traceId para ver o trace no Jaeger"
    ;;

  5)
    echo -e "\n${BLUE}=== Abrindo Jaeger UI ===${NC}\n"
    echo "Jaeger: ${BLUE}${JAEGER_URL}${NC}"

    if command -v open &> /dev/null; then
      open "${JAEGER_URL}"
    elif command -v xdg-open &> /dev/null; then
      xdg-open "${JAEGER_URL}"
    else
      echo -e "${YELLOW}Abra manualmente: ${BLUE}${JAEGER_URL}${NC}"
    fi
    ;;

  6)
    echo -e "\n${BLUE}=== Abrindo Grafana - Trace Dashboard ===${NC}\n"

    dashboard_url="${GRAFANA_URL}/d/trace-search?orgId=1"
    echo "Dashboard: ${BLUE}${dashboard_url}${NC}"

    if command -v open &> /dev/null; then
      open "${dashboard_url}"
    elif command -v xdg-open &> /dev/null; then
      xdg-open "${dashboard_url}"
    else
      echo -e "${YELLOW}Abra manualmente: ${BLUE}${dashboard_url}${NC}"
    fi
    ;;

  0)
    echo -e "\n${GREEN}Até logo!${NC}\n"
    exit 0
    ;;

  *)
    echo -e "\n${RED}Opção inválida${NC}\n"
    exit 1
    ;;
esac

echo -e "\n${BLUE}═══════════════════════════════════════════${NC}\n"
