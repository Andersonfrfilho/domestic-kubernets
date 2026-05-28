# Tracing Guide - Jaeger, Tempo e Grafana

## Visão Geral

O projeto Domestic usa uma stack de tracing distribuído:
- **Jaeger**: Captura e armazena traces via OpenTelemetry (OTLP)
- **Tempo**: Backend de tracing do Grafana (armazena dados em Loki)
- **Grafana**: Interface unificada para visualizar traces, logs e métricas
- **Loki**: Armazenamento de logs com suporte a correlação por traceId

## Fluxo de Dados

```
App (com OpenTelemetry)
  ↓
OTLP Exporter (porta 4318/HTTP ou 4317/gRPC)
  ↓
Jaeger Collector
  ↓
Jaeger Storage + Tempo
  ↓
Grafana (visualização)
```

## Acessar os Painéis

### 1. **Jaeger UI** (detalhes completos dos traces)
```
http://jaeger.domestic.local
http://localhost:16686  (local)
```

**Funcionalidades:**
- Buscar por serviço
- Filtrar por operação
- Ver timeline de spans
- Detalhes de cada span (tags, logs, status)

### 2. **Grafana - Painel de Tracing** (visão integrada)
```
http://grafana.domestic.local
```

**Passos:**
1. Login com credenciais do Grafana (padrão: admin/admin)
2. Menu lateral → Dashboards
3. Procurar por **"Trace Search by TraceID"**

**Painéis disponíveis:**
- **TraceID Input**: Campo para colar um traceId
- **Jaeger Trace Viewer**: Visualização de nós e conexões entre serviços
- **Trace Details & Logs**: Spans detalhados
- **Service Dependencies**: Mapa de dependências entre serviços
- **Logs for TraceID**: Logs correlatos no Loki

### 3. **Grafana - Painel de Logs** (com correlação de tracing)
Selecione um log e clique no traceId para ver o trace correspondente.

## Formatos de TraceID

O traceId é gerado automaticamente e pode estar em diferentes formatos:

**Short Hash (padrão):**
```
a1b2c3d4e5f6  (12 caracteres)
```

**Full Hash (compatível com Jaeger):**
```
a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4  (32 caracteres)
```

**Configurar o formato:**
```bash
# Variável de ambiente
export OTEL_ID_FORMAT=short-hash  # ou full-hash, uuid-no-hyphens, uuid-with-hyphens
```

## Visualizando um Trace

### Método 1: Copiar TraceID de um Log

**No arquivo de log:**
```
[a1b2c3d4-3bb7-4614-8a81-e68553ed6253][2026-05-24T19:51:37.422Z][example:0.0.3][Controller][Service.processOrder][INFO] - Processing order
```

O primeiro campo é o `requestId` que correlaciona com o `traceId`.

**No Grafana:**
1. Painel "Trace Search by TraceID"
2. Cole o traceId no campo **TraceID Input**
3. Veja a visualização de nós e o detalhe dos spans

### Método 2: Buscar pelo Serviço no Jaeger

1. Acesse **http://jaeger.domestic.local**
2. Service dropdown → selecione **"example"**, **"api"**, **"bff"**, etc.
3. Clique em traces recentes
4. Veja a timeline completa

### Método 3: Correlação Logs ↔ Traces

**No painel de Logs do Grafana:**
1. Veja um log com `[traceId]`
2. Clique no link de traceId (se configurado)
3. Será redirecionado para o trace correspondente

## Entendendo um Trace

### Estrutura de um Trace

```
Trace (a1b2c3d4...)
├── Span: HTTP GET /api/users (duration: 145ms)
│   ├── Span: UserService.getUsers (duration: 100ms)
│   │   ├── Span: UserRepository.find (duration: 50ms)
│   │   └── Span: CacheService.get (duration: 10ms)
│   └── Span: ResponseInterceptor (duration: 5ms)
└── [Eventos de erro, se houver]
```

**Cada Span tem:**
- **Duration**: Tempo gasto
- **Status**: OK, ERROR, UNSET
- **Tags**: Atributos customizados (request.id, service.name, etc.)
- **Events**: Logs capturados durante a execução
- **Parent**: Link para o span pai

### Informações Importantes

| Campo | Significado | Exemplo |
|-------|-------------|---------|
| Trace ID | Identificador único da requisição | `a1b2c3d4e5f6` |
| Span ID | Identificador do segmento | `1a2b3c4d` |
| Operation | Nome da operação | `GET /api/users` |
| Service | Serviço que executou | `api` |
| Duration | Tempo total | `145ms` |
| Status | Sucesso/Erro | `OK`, `ERROR` |

## Monitorando em Produção

### Métricas importantes para alertar

**1. Latência alta de traces:**
```
histogram_quantile(0.95, rate(span_latency_bucket[5m])) > 1000ms
```

**2. Taxa de erro nos traces:**
```
rate(span_errors_total[5m]) > 0.01  (1% de erro)
```

**3. Serviços não reportando traces:**
```
up{job="tempo"} == 0
```

### Dashboards úteis

- **API Performance**: Latência por endpoint
- **Service Health**: Status de cada serviço
- **Error Rates**: Taxa de erro por serviço
- **Database Performance**: Queries lentas

## Configuração de Amostragem (Sampling)

Para reduzir volume de dados em produção:

```bash
# Registrar 10% dos traces
export OTEL_TRACES_SAMPLER=parentbased_traceidratio
export OTEL_TRACES_SAMPLER_ARG=0.1
```

## Dados Armazenados

**Localização:** Tempo utiliza Loki como backend de storage:
```
/loki/data  (volume persistente)
```

**Retenção:** Configurável no `loki-config.configmap.yaml`:
```yaml
retention_deletes_enabled: true
retention_period: 720h  # 30 dias
```

## Troubleshooting

### "Nenhum trace encontrado"

1. Verifique se o `initTracing()` foi chamado:
   ```bash
   kubectl logs -n domestic deployment/api -c api | grep -i "tracing\|OpenTelemetry"
   ```

2. Confirme que o Jaeger está recebendo dados:
   ```bash
   curl http://localhost:16686/api/services
   ```

3. Verifique a configuração do endpoint:
   ```bash
   echo $OTEL_EXPORTER_OTLP_ENDPOINT
   # Deve ser: http://jaeger:4318
   ```

### "TraceID não correlaciona com logs"

1. Confirme que o `requestId` está sendo propagado em todos os serviços
2. Verifique se o Loki está indexando o campo `trace_id`:
   ```bash
   kubectl logs -n domestic statefulset/loki | grep -i "trace"
   ```

### Jaeger mostra poucos spans

1. Verifique a amostragem (sampler):
   ```bash
   echo $OTEL_TRACES_SAMPLER
   ```

2. Confirme que a auto-instrumentação está habilitada:
   ```bash
   grep "getNodeAutoInstrumentations" /path/to/init-tracing.ts
   ```

## Links Úteis

| Recurso | URL |
|---------|-----|
| Jaeger UI | http://jaeger.domestic.local |
| Grafana Dashboards | http://grafana.domestic.local |
| OpenTelemetry Docs | https://opentelemetry.io/docs/instrumentation/js/getting-started/ |
| Jaeger Docs | https://www.jaegertracing.io/docs/ |
| Tempo Docs | https://grafana.com/docs/tempo/ |
| Loki Docs | https://grafana.com/docs/loki/ |
