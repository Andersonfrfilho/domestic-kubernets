#!/bin/bash
# Script para atualizar o schedule do GitHub Actions Poller via ConfigMap

set -e

NAMESPACE="argocd-poller"
CONFIG_MAP="github-poller-config"
CRONJOB="github-actions-poller"

# Se passado argumento, atualizar o schedule
if [ -n "$1" ]; then
  NEW_SCHEDULE="$1"
  echo "Atualizando schedule para: $NEW_SCHEDULE"

  kubectl patch configmap "$CONFIG_MAP" \
    -n "$NAMESPACE" \
    -p "{\"data\":{\"SCHEDULE\":\"$NEW_SCHEDULE\"}}"

  echo "ConfigMap atualizado"
else
  # Mostrar schedule atual
  CURRENT=$(kubectl get configmap "$CONFIG_MAP" -n "$NAMESPACE" -o jsonpath='{.data.SCHEDULE}')
  echo "Schedule atual: $CURRENT"
  echo ""
  echo "Uso:"
  echo "  $(basename "$0") '*/10 * * * *'     # Atualizar para cada 10 minutos"
  echo "  $(basename "$0") '0 * * * *'         # Atualizar para cada hora"
  echo "  $(basename "$0") '*/5 * * * *'       # Atualizar para cada 5 minutos (padrão)"
  exit 0
fi

# Ler a template do CronJob
TEMPLATE_PATH="$(dirname "$0")/../argocd/cronjob-poller-template.yaml"

if [ -f "$TEMPLATE_PATH" ]; then
  SCHEDULE=$(kubectl get configmap "$CONFIG_MAP" -n "$NAMESPACE" -o jsonpath='{.data.SCHEDULE}')

  echo "Aplicando novo schedule ao CronJob..."
  sed "s|SCHEDULE_PLACEHOLDER|$SCHEDULE|g" "$TEMPLATE_PATH" | kubectl apply -f -

  echo "✓ CronJob atualizado com schedule: $SCHEDULE"
else
  echo "⚠ Template não encontrado em: $TEMPLATE_PATH"
  echo "Aplicando patch direto ao CronJob (próxima execução usará novo schedule)..."

  SCHEDULE=$(kubectl get configmap "$CONFIG_MAP" -n "$NAMESPACE" -o jsonpath='{.data.SCHEDULE}')
  kubectl patch cronjob "$CRONJOB" -n "$NAMESPACE" \
    -p "{\"spec\":{\"schedule\":\"$SCHEDULE\"}}"

  echo "✓ CronJob patched"
fi
