# Jaeger - Distributed Tracing Guide

## O que é Jaeger?

Jaeger é um **distributed tracing system** que permite rastrear requisições através de múltiplos serviços em tempo real. Diferente dos logs que mostram linhas individuais, Jaeger mostra o **fluxo completo** de uma requisição.

## Acessar Jaeger

```bash
# URL local (porta padrão K3s NodePort)
http://grafana.domestic.local:30686

# Ou via port-forward
kubectl port-forward svc/jaeger 16686:16686 -n domestic
# Acesse: http://localhost:16686
```

## Como Funciona o Rastreamento

### 1. **Trace ID vs Request ID**

Você vê nos logs `requestId: '2MFCK7HD'`, mas o Jaeger usa um `Trace ID` diferente:

```
Log:     [2MFCK7HD][2026-05-21T21:34:16.973Z][GetUserByKeycloakIdUseCase.execute][INFO]
Jaeger:  traceparent: '00-8b9b4e36746b0b0b206841bf694b067a-dbea1645514964bf-01'
                           ↑ Trace ID (32 hex chars)
```

O `Trace ID` no Jaeger é gerado automaticamente pelo OpenTelemetry e é o que você precisa para buscar a trace completa.

### 2. **Fluxo de uma Requisição com Jaeger**

```
Client HTTP Request
    ↓
Kong (cria trace)
    ↓
API Service (recebe trace, adiciona spans)
    ↓ 
Database Call (auto-instrumentado)
    ↓
Response (trace enviada ao Jaeger)
    ↓
Jaeger armazena e indexa
```

## Como Usar a UI do Jaeger

### **Buscar por Service**

1. Abra Jaeger UI (http://localhost:16686)
2. Select **Service**: `domestic-api` (ou outro)
3. Select **Operation**: `GET /v1/onboarding/address` (etc)
4. Click **Find Traces**

### **Buscar por Tags**

Para rastrear o `requestId` específico:

1. **Service**: `domestic-api`
2. **Tags**: adicione um filtro customizado
   ```
   http.request.body.x_request_id = "2MFCK7HD"
   ```
   Ou procure por qualquer field nos logs:
   ```
   span.tags.userId = "5d030b47-eb7f-49ce-b44a-94ab7c7da14e"
   ```

3. Click **Find Traces**

### **Visualizar uma Trace Completa**

Quando você encontrar uma trace:
- **Timeline View**: mostra sequência temporal de spans
- **Statistics**: latência por serviço
- **Logs**: eventos dentro da trace
- **Tags**: metadata (método HTTP, status, userId, etc)

## Configuração dos Aplicativos

### Verificar Instrumentação (já está configurada):

```typescript
// src/instrumentation.ts
const sdk = new NodeSDK({
  resource: new Resource({
    [ATTR_SERVICE_NAME]: 'domestic-api',
    [ATTR_SERVICE_VERSION]: '1.0.0',
  }),
  traceExporter: new OTLPTraceExporter({
    url: 'http://jaeger:4318/v1/traces', // ← Jaeger OTLP receiver
  }),
  instrumentations: [
    getNodeAutoInstrumentations({
      '@opentelemetry/instrumentation-fs': { enabled: false },
      '@opentelemetry/instrumentation-dns': { enabled: false },
    }),
  ],
});

sdk.start();
```

### Auto-Instrumentações Ativas

Estes são capturados automaticamente:

- **HTTP Calls**: `fetch`, `axios`, chamadas internas
- **Database**: TypeORM queries (PostgreSQL)
- **RabbitMQ**: produtor/consumidor de eventos
- **Express/Fastify**: requisições HTTP recebidas

### Adicionar Spans Customizados

Para rastrear operações específicas dentro do seu código:

```typescript
import { trace } from '@opentelemetry/api';

const tracer = trace.getTracer('domestic-api');

async function processOrder(orderId: string) {
  const span = tracer.startSpan('process_order', {
    attributes: {
      'order.id': orderId,
      'order.status': 'pending',
    },
  });

  try {
    // seu código
    await database.saveOrder(order);
    
    span.addEvent('order_saved', {
      'order.total': 100.00,
    });
  } finally {
    span.end();
  }
}
```

## Casos de Uso Práticos

### 1. **Investigar uma Requisição Lenta**

```
1. Jaeger UI → Service: "domestic-api"
2. Click numa trace com duração alta (vermelho)
3. Veja qual operação demorou: Database? HTTP call? JSON parsing?
4. Analise tags: quantas rows retornadas? Qual índice usado?
```

### 2. **Rastrear Erro em Cascade Entre Serviços**

Se API → Worker → Database falha:

```
1. Busque a trace por erro: "span.status.code = ERROR"
2. Veja timeline: qual serviço falhou primeiro?
3. Leia logs dos spans: mensagem de erro exata
4. Correlacione com banco de dados: timestamp do erro
```

### 3. **Monitorar Performance de Integração**

```
1. Service: "domestic-api"
2. Operation: "POST /v1/orders"
3. Filtre por: "http.status_code = 201"
4. Statistiques: P99 latency, throughput por endpoint
```

## Correlação com Logs

### Extrair Trace ID dos Logs

Se você tem um log interessante:

```
[2MFCK7HD][2026-05-21T21:34:16.973Z][GetUserByKeycloakIdUseCase.execute][INFO]
```

Para **encontrar a trace correspondente**, procure pelo `requestId` em logs de HTTP:

```
[2MFCK7HD]...[HttpLoggingInterceptor.intercept]...
  headers: { 'traceparent': '00-8b9b4e36746b0b0b206841bf694b067a-dbea1645514964bf-01' }
  ↑ Use este Trace ID no Jaeger!
```

## Melhorias para Implementar

### 1. **Adicionar Trace ID aos Logs Estruturados**

Modifique o logger para incluir trace ID:

```typescript
// src/config/logger.ts
import { trace } from '@opentelemetry/api';

function getTraceId() {
  const span = trace.getActiveSpan();
  return span?.spanContext().traceId ?? 'no-trace';
}

// log.info({ traceId: getTraceId(), message: '...' })
```

### 2. **Criar Dashboard no Grafana para Traces**

Configure o Grafana para mostrar traces do Jaeger como datasource (já está configurado em `observability/grafana/grafana-datasources.configmap.yaml`).

### 3. **Alertas Baseados em Traces**

Defina alertas no Prometheus quando traces excederem latência:

```yaml
- alert: HighLatencyAPI
  expr: |
    histogram_quantile(0.99, rate(http_request_duration_seconds_bucket{job="domestic-api"}[5m]))
    > 1
  for: 5m
```

## Troubleshooting

### **Jaeger não recebe traces**

1. Verificar se Jaeger está rodando:
   ```bash
   kubectl get pods -l app=jaeger -n domestic
   ```

2. Verificar endpoint OTLP:
   ```bash
   kubectl logs deployment/jaeger -n domestic | grep "OTLP\|4318"
   ```

3. Verificar conectividade dos apps:
   ```bash
   kubectl exec deployment/api -n domestic -- \
     curl -v http://jaeger:4318/v1/traces
   ```

### **Trace ID 400 Bad Request**

O Trace ID inserido não existe. Jaeger só armazena traces dos **últimos 24 horas** por padrão. Verifique a data da requisição.

## Referências

- [Jaeger Documentation](https://www.jaegertracing.io/docs/)
- [OpenTelemetry Node.js SDK](https://github.com/open-telemetry/opentelemetry-js)
- [OWASP - Distributed Tracing](https://owasp.org/www-community/attacks/Distributed_Tracing)
