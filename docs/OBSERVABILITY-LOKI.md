# Observabilidade — Loki (Log Collection)

## Arquitetura

```
Pod logs → CRI (containerd) → /var/log/pods/domestic_*/*/*.log
                                        ↓
                                   Promtail (DaemonSet)
                                        ↓ (pipeline stages)
                                    Loki (StatefulSet)
                                        ↓
                                   Grafana (Datasource)
```

## Labels disponíveis no Loki

Todo log coletado dos pods da namespace `domestic` recebe estes labels:

| Label | Origem | Exemplo de valores |
|---|---|---|
| `job` | Promtail config (estático) | `"domestic"` |
| `service_name` | Extraído de `appName` no JSON do log | `"backend-api"`, `"backend-bff"`, `"backend-cron"`, `"backend-worker"` |
| `level` | Extraído de `level` no JSON do log | `"debug"`, `"info"`, `"warn"`, `"error"` |
| `request_id` | Extraído de `requestId` no JSON do log | `"T2ATNW5M"` |
| `filename` | Caminho do arquivo de log no nó | `/var/log/pods/domestic_api-...` |
| `stream` | stdout/stderr | `"stdout"` |

> **Importante:** Não existe label `namespace` nos streams do Loki. Os dashboards devem usar `{job="domestic"}` para filtrar logs da namespace domestic.

## LogQL — Queries corretas para Grafana

```logql
# Todos os logs da namespace domestic
{job="domestic"}

# Logs de um serviço específico
{job="domestic", service_name="backend-api"}
{job="domestic", service_name="backend-bff"}
{job="domestic", service_name="backend-cron"}
{job="domestic", service_name="backend-worker"}

# Filtrar por nível (lowercase)
{job="domestic", level="error"}
{job="domestic", level="warn"}

# Filtrar por nível + serviço
{job="domestic", service_name="backend-api", level="error"}

# Busca textual
{job="domestic"} |= "error" or "ERROR" or "Exception"
```

## Configuração obrigatória nos serviços NestJS

Para que os logs sejam coletados corretamente, cada serviço deve configurar o `LoggerModule` assim:

```typescript
LoggerModule.forRoot({
  // OBRIGATÓRIO: false → formato texto legível e estruturado
  // true → formato JSON (dificulta leitura no kubectl logs)
  isProduction: false,

  // OBRIGATÓRIO: ?? false garante boolean explícito
  // process.stdout.isTTY retorna undefined em containers (não TTY)
  // O logger usa `config?.colorize !== false` — undefined !== false = true
  // Isso causaria ANSI codes nos logs, poluindo os labels do Loki
  colorize: process.stdout.isTTY ?? false,

  // OBRIGATÓRIO: nome do serviço — aparece como service_name no Loki
  appName: 'backend-api',  // ou bff, cron, worker
})
```

### Por que `?? false` é crítico

```
Container sem TTY:
  process.stdout.isTTY → undefined
  undefined ?? false   → false  ✅ (sem cores)

Terminal local com TTY:
  process.stdout.isTTY → true
  true ?? false        → true   ✅ (com cores)
```

Sem o `?? false`:
```
process.stdout.isTTY → undefined
logger: undefined !== false → true → ANSI codes ligados
log: "\x1b[32mbackend-api" → service_name='\x1b[32mbackend-api'
Grafana: service_name="backend-api" → NO DATA ❌
```

## Pipeline do Promtail

O Promtail (`observability/promtail/promtail.configmap.yaml`) usa estas stages em ordem:

```yaml
pipeline_stages:
  # 1. Parse CRI (formato de container runtime)
  - cri: {}

  # 2. Agrupa linhas multiline (suporte a stack traces)
  - multiline:
      firstline: '(^\[|^\{|^\d{4}-)'

  # 3. CRÍTICO: Remove ANSI color codes ANTES de extrair labels
  #    Previne que escape sequences poluam os label values
  - replace:
      expression: '\x1b\[[0-9;]*m'
      replace: ''

  # 4. Extrai campos do formato JSON (logs dos serviços NestJS)
  - json:
      expressions:
        level: level
        message: message
        timestamp: timestamp
        request_id: requestId
        service_name: appName
      on_error: keep  # não falha para logs de infraestrutura (Mongo, Keycloak, etc.)

  # 5. Fallback: extrai de formato texto (logs de infra sem JSON)
  - regex:
      expression: '^\[(?P<request_id>[^\]]+)\]\[[^\]]+\]\[(?P<service_name>[^:\]]+)'

  # 6. Parse do timestamp para ordenação correta
  - timestamp:
      source: timestamp
      format: RFC3339Nano
      on_error: keep

  # 7. Promove campos extraídos para labels do Loki
  - labels:
      level:
      request_id:
      service_name:

  # 8. Usa o campo message como conteúdo do log
  - output:
      source: message
```

## Posições persistentes (Promtail)

O Promtail persiste a posição de leitura de cada arquivo em um volume hostPath:

```yaml
# promtail.daemonset.yaml
volumes:
  - name: positions
    hostPath:
      path: /var/lib/promtail
      type: DirectoryOrCreate

volumeMounts:
  - name: positions
    mountPath: /var/lib/promtail
```

**Por quê:** Sem persistência, ao reiniciar o Promtail ele re-lê todos os logs desde o início. O Loki rejeita entradas antigas (out-of-order), gerando erro `ingester_error` para centenas de milhares de linhas.

## Troubleshooting

### Dashboard mostra "No data"

1. **Verificar labels no Loki:**
   ```bash
   kubectl port-forward -n domestic loki-0 3100:3100 &
   curl 'http://localhost:3100/loki/api/v1/label/service_name/values'
   ```
   Esperado: `["backend-api", "backend-bff", "backend-cron", "backend-worker"]`

2. **Verificar se logs existem com a query correta:**
   ```bash
   curl -G 'http://localhost:3100/loki/api/v1/query_range' \
     --data-urlencode 'query={job="domestic", service_name="backend-api"}' \
     --data-urlencode "start=$(date -d '1 hour ago' +%s)000000000" \
     --data-urlencode "end=$(date +%s)000000000" \
     --data-urlencode 'limit=5'
   ```

3. **Verificar se labels estão sujos (ANSI):**
   Se o resultado de `/loki/api/v1/label/service_name/values` mostrar `[32mbackend-api` (com escape sequences), o problema é que `colorize: true` está ativo nos serviços. Corrigir com `colorize: process.stdout.isTTY ?? false`.

4. **Verificar métricas do Promtail:**
   ```bash
   kubectl port-forward -n domestic promtail-<pod> 9080:9080 &
   curl 'http://localhost:9080/metrics' | grep -E "dropped|ingester_error|sent"
   ```
   Se `promtail_dropped_entries_total{reason="ingester_error"}` estiver crescendo, o Loki está rejeitando entradas — provavelmente out-of-order após reset das posições.

### Logs com ANSI codes aparecem no Loki

Causa: `colorize: true` ativo em algum serviço.

Fix: Verificar `app.module.ts` de cada serviço e garantir:
```typescript
colorize: process.stdout.isTTY ?? false,
```

Após o fix, o Promtail ainda tem o stage `replace` para strip de ANSI como proteção adicional.

### Promtail dropando muitos logs (ingester_error)

Causa mais comum: reset do arquivo de posições (pod reiniciado sem volume persistente) → re-leitura de todos os logs → Loki rejeita entradas antigas.

Fix: Verificar que o volume hostPath está configurado e montado corretamente no DaemonSet do Promtail.
