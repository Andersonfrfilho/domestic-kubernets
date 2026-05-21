# Observability Fixes — Resumo das Mudanças

## Status: ✅ MÉTRICAS PERSONALIZADAS CORRIGIDAS

Todos os serviços agora registram suas próprias métricas via interceptors e handlers.

## Problemas Encontrados e Solucionados

### 1. ✅ Configuração de Métricas Inconsistente
**Problema:** BFF, API e Cron não tinham `path` explícito no PrometheusModule, causando conflitos de scrape.

**Solução:**
- ✅ API: Adicionado `path: '/metrics'` em `src/modules/metrics/metrics.module.ts`
- ✅ BFF: Adicionado `path: '/metrics'` em `src/modules/metrics/metrics.module.ts`
- ✅ Cron: Adicionado `path: '/metrics'` em `src/modules/metrics/metrics.module.ts`
- ✅ Prometheus scrape config: Corrigido path do BFF de `/bff/metrics` para `/metrics`

**Arquivos modificados:**
```
domestic-backend-api/src/modules/metrics/metrics.module.ts
domestic-backend-bff/src/modules/metrics/metrics.module.ts
domestic-backend-cron/src/modules/metrics/metrics.module.ts
domestic-kubernets/observability/prometheus/prometheus-scrape.configmap.yaml
```

---

### 1.5. ✅ Métricas Customizadas Implementadas nos Jobs/Consumers
**Problema:** Serviços de métricas existiam, mas **não eram chamados** nos jobs e consumers.

**Solução — Cron (4 jobs):**
- ✅ `account-cleanup.job.ts` — agora registra `cron_job_runs_total` e `cron_job_duration_seconds`
- ✅ `rating-recalculator.job.ts` — agora registra métricas
- ✅ `request-reminder.job.ts` — agora registra métricas
- ✅ `weekly-report.job.ts` — agora registra métricas

**Solução — Worker (6 consumers):**
- ✅ `email.consumer.ts` — agora registra `queue_messages_processed_total` e `queue_message_processing_duration_seconds`
- ✅ `provider-approval.consumer.ts` — agora registra métricas
- ✅ `rating.consumer.ts` — agora registra métricas
- ✅ `service-request.consumer.ts` — agora registra métricas
- ✅ `user-verification.consumer.ts` — agora registra métricas
- ✅ `push.consumer.ts` — agora registra métricas

**Padrão implementado:** 
```typescript
const startTime = Date.now();
try {
  await handler.run();
  this.metrics.record(jobName, 'success', Date.now() - startTime);
} catch (err) {
  this.metrics.record(jobName, 'failed', Date.now() - startTime);
  throw err;
}
```

**Arquivos modificados:**
```
domestic-backend-cron/src/modules/*/[job-name].job.ts (4 files)
domestic-backend-worker/src/modules/*/[consumer-name].consumer.ts (6 files)
```

---

### 2. ✅ Adicionados Redis e MongoDB Exporters

**Criados:**
- `domestic-kubernets/redis/redis-exporter.deployment.yaml`
- `domestic-kubernets/mongo/mongodb-exporter.deployment.yaml`

**O que cada exporter faz:**
- **Redis Exporter:** Expõe métricas do Redis (clientes, memória, taxa de hit, comandos/s)
- **MongoDB Exporter:** Expõe métricas do MongoDB (conexões, operações, tamanho de databases)

**Configuração Prometheus:**
- Scrape job `redis` → `redis-exporter:9121`
- Scrape job `mongodb` → `mongodb-exporter:9216`

---

### 3. ✅ Novos Dashboards do Grafana

**Criados:**
- `domestic-kubernets/observability/grafana/grafana-dashboard-redis.configmap.yaml`
  - Mostra: Clientes conectados, Memória, Keyspace, Taxa de commands, Hit rate
  
- `domestic-kubernets/observability/grafana/grafana-dashboard-mongodb.configmap.yaml`
  - Mostra: Conexões, Uptime, Memória, Taxa de operações, Tamanho de databases

**Atualizado:**
- `domestic-kubernets/observability/grafana/grafana.deployment.yaml`
  - Adicionados volumeMounts para novos dashboards (Redis, MongoDB, Logs)

---

## Como Aplicar as Mudanças

### Passo 1: Rebuild das imagens (API, BFF, Cron)
```bash
# Localmente (macOS + minikube)
eval $(minikube docker-env)
docker build -f ../domestic-backend-api/Dockerfile.dev -t domestic-api:local ../domestic-backend-api
docker build -f ../domestic-backend-bff/Dockerfile.dev -t domestic-bff:local ../domestic-backend-bff
docker build -f ../domestic-backend-cron/Dockerfile.dev -t domestic-cron:local ../domestic-backend-cron

# Ou via ArgoCD (Ubuntu + k3s)
# — ArgoCD detecta as mudanças automaticamente
```

### Passo 2: Aplicar as mudanças do Kubernetes
```bash
# Redis Exporter
kubectl apply -f domestic-kubernets/redis/redis-exporter.deployment.yaml

# MongoDB Exporter
kubectl apply -f domestic-kubernets/mongo/mongodb-exporter.deployment.yaml

# Atualizar Prometheus scrape config
kubectl apply -f domestic-kubernets/observability/prometheus/prometheus-scrape.configmap.yaml
kubectl rollout restart deployment/prometheus -n domestic

# Atualizar Grafana (novos dashboards + volumes)
kubectl apply -f domestic-kubernets/observability/grafana/grafana-dashboard-redis.configmap.yaml
kubectl apply -f domestic-kubernets/observability/grafana/grafana-dashboard-mongodb.configmap.yaml
kubectl apply -f domestic-kubernets/observability/grafana/grafana.deployment.yaml
kubectl rollout restart deployment/grafana -n domestic
```

Ou aplicar tudo:
```bash
./scripts/start-macos.sh --with-observability
# ou
argocd app sync domestic-infra
```

---

## Status dos Dashboards

| Dashboard | Status | Métrica |
|-----------|--------|---------|
| API | ✅ Existente | HTTP requests, duration, heap |
| BFF | ✅ Existente | HTTP requests, duration, heap |
| Worker | ✅ Existente | Queue messages, processing duration, heap |
| Cron | ✅ Existente | Job executions, duration, heap |
| **Redis** | ✅ **Novo** | Clients, Memory, Hit rate, Commands |
| **MongoDB** | ✅ **Novo** | Connections, Operations, Database sizes |
| Logs | ✅ Existente | Application logs via Loki |
| Jaeger | ✅ Existente | Distributed tracing |

---

## O que ainda falta (Not yet)

### Não Implementado (Requeriria mudanças no Kong)
- **Kong Dashboard** — Kong 3.6 não expõe métricas Prometheus nativamente
  - Solução: Upgrade para Kong 3.7+ ou usar plugin `prometheus`

### Não Implementado (Keycloak)
- **Keycloak Dashboard** — Keycloak tem métricas via JMX, não Prometheus nativo
  - Solução: Adicionar JMX exporter como sidecar

---

## Verificação

Após aplicar as mudanças:

1. **Redis Exporter rodando:**
   ```bash
   kubectl get pods -n domestic | grep redis-exporter
   ```

2. **MongoDB Exporter rodando:**
   ```bash
   kubectl get pods -n domestic | grep mongodb-exporter
   ```

3. **Prometheus scrape jobs:**
   ```bash
   kubectl port-forward svc/prometheus 9090:9090 -n domestic
   # Abrir http://localhost:9090/targets
   # Verificar: redis, mongodb devem estar com status UP
   ```

4. **Novos dashboards no Grafana:**
   ```bash
   kubectl port-forward svc/grafana 3000:3000 -n domestic
   # Abrir http://localhost:3000
   # Verificar: Redis, MongoDB, Logs, Jaeger devem estar listados
   ```

---

## Notas

- **Redis Exporter:** Usa imagem `oliver006/redis_exporter:latest` (comunitária, bem mantida)
- **MongoDB Exporter:** Usa imagem `percona/mongodb_exporter:latest` (Percona, oficial)
- **Métrica de Heap:** Todas as aplicações já coletam via `defaultMetrics: { enabled: true }`
- **Métricas Customizadas:** Cron e Worker têm métricas específicas no código — se não aparecerem, verificar se o código está gerando as métricas

---

## Troubleshooting

### "No data" nos novos dashboards?
1. Verificar se exporters estão rodando: `kubectl logs deployment/redis-exporter -n domestic`
2. Verificar se Prometheus consegue fazer scrape: porta 9121 (Redis) e 9216 (MongoDB) aberta?
3. Aguardar alguns minutos para dados chegarem (retention é 200h)

### "BFF metrics empty"?
1. Verificar se BFF foi rebuild com o novo `path: '/metrics'`
2. Testar manualmente: `kubectl port-forward svc/bff 3001:3001 -n domestic && curl http://localhost:3001/metrics`

### Prometheus não tem os novos jobs?
1. Reapplicar prometheus-scrape.configmap.yaml: `kubectl apply -f prometheus-scrape.configmap.yaml`
2. Restart Prometheus: `kubectl rollout restart deployment/prometheus -n domestic`
3. Aguardar 30s para Prometheus recarregar config
