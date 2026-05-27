# Traces - Quick Start Guide

## 🚀 Em 5 Minutos

### 1. Deploy do Dashboard

```bash
# Aplicar o novo dashboard
kubectl apply -f observability/grafana/grafana-dashboard-traces-simple.configmap.yaml
kubectl apply -f observability/grafana/grafana.deployment.yaml

# Aguardar o Grafana recarregar
sleep 30
```

### 2. Acessar o Painel

```
http://grafana.domestic.local/d/traces-simple
http://localhost:3000/d/traces-simple  (local)
```

### 3. Gerar um Trace

```bash
# Request simples
curl http://localhost:3000/health

# Ou no exemplo
curl http://localhost:3000/tracing/order/test-123

# Ou no BFF
curl http://localhost:3001/bff/health
```

## 📊 O Que Você Verá

**Painéis:**

| Painel | O que mostra |
|--------|-------------|
| **Recent Traces (API)** | Últimos traces do serviço `api` |
| **Recent Traces (Example)** | Últimos traces do serviço `example` |
| **Service Health** | Quantos serviços estão enviando traces |
| **Span Rate** | Quantos spans por segundo |
| **Error Rate** | Taxa de erro em % |
| **Latency P95** | 95º percentil de latência |

## 🔍 Como Buscar um TraceID Específico

### Método 1: Via Jaeger (direto)

```
http://jaeger.domestic.local/search?service=api
```

1. Selecione o serviço
2. Veja os traces recentes
3. Clique em um trace para ver detalhes

### Método 2: Via Grafana (integrado)

1. Abra: `http://grafana.domestic.local/d/traces-simple`
2. Veja a lista de traces nos painéis **Recent Traces**
3. Clique em um trace para expandir e ver spans

### Método 3: Correlação com Logs

**Se você tem um traceId de um log:**

1. Vá para Dashboard **Logs** no Grafana
2. Procure por `[traceId]`
3. Clique no traceId para ir direto pro trace

## 🎯 Entendendo os Dados

### TraceID vs RequestID

- **RequestID**: Gerado pela aplicação, aparece nos logs `[requestId]`
- **TraceID**: Gerado pelo OpenTelemetry, aparece no Jaeger/Tempo

**Eles estão correlacionados:**
```
Log:   [a1b2c3d4][timestamp][service][method][INFO] - msg
Trace: traceId=a1b2c3d4, spanId=xyz, service=api
```

## ⚙️ Verificar Status do Tracing

### Jeager está recebendo dados?

```bash
# Ver serviços conhecidos
curl http://localhost:16686/api/services

# Resposta esperada:
# {"data":["api","bff","example","worker","cron"]}
```

### Prometheus está coletando métricas de traces?

```bash
# Acessar Prometheus
http://localhost:9090

# Query: 
span_received_total

# Esperado: gráfico subindo
```

### Loki está correlacionando traces?

```bash
# Em um log do Grafana, procure por:
{job="domestic"} | json | trace_id="..."
```

## 🛠️ Troubleshooting

### "Nenhum trace aparece"

**1. Verificar se os serviços estão iniciando tracing:**
```bash
kubectl logs deployment/api -n domestic | grep -i "OpenTelemetry initialized"
# Esperado: [tracing] OpenTelemetry initialized — service=api...
```

**2. Verificar conectividade com Jaeger:**
```bash
kubectl exec -it deployment/api -n domestic -- curl http://jaeger:16686/api/services
# Esperado: {"data":["api",...]}
```

**3. Verificar configuração do endpoint:**
```bash
kubectl get configmap api-config -n domestic -o yaml | grep OTEL
# Esperado: OTEL_EXPORTER_OTLP_ENDPOINT=http://jaeger:4318
```

### "Dashboard vazio"

**Razões possíveis:**

1. **Grafana ainda está carregando o ConfigMap**
   - Solução: Aguardar 30 segundos e recarregar a página

2. **Nenhuma métrica de traces em Prometheus**
   - Verificar se Prometheus está scrapeando Jaeger/Tempo
   - Verificar `prometheus.yml`

3. **Jaeger não está recebendo dados**
   - Ver seção "Verificar Status" acima

## 📈 Interpretar os Spans

### Estrutura de um Trace

```
Trace (ID: a1b2c3d4...)
├── Span 1: HTTP GET /tracing/order/test-123  (duration: 145ms)
│   ├── Span 2: Controller.processOrder  (duration: 100ms)
│   │   └── Span 3: Service.processOrder  (duration: 95ms)
│   └── Span 4: ResponseInterceptor  (duration: 10ms)
└── [Logs capturados durante execução]
```

**Leitura:**
- Verde = sucesso (status: OK)
- Vermelho = erro (status: ERROR)
- Cinza = não definido (status: UNSET)

### Tags Importantes

| Tag | Significado |
|-----|-------------|
| `service.name` | Qual serviço executou |
| `span.kind` | Tipo: INTERNAL, SERVER, CLIENT, PRODUCER, CONSUMER |
| `http.method` | GET, POST, etc |
| `http.status_code` | 200, 400, 500, etc |
| `error.type` | Tipo de erro, se houver |

## 🔗 Links Úteis

| Serviço | URL |
|---------|-----|
| **Grafana Traces** | http://grafana.domestic.local/d/traces-simple |
| **Jaeger UI** | http://jaeger.domestic.local |
| **Prometheus** | http://prometheus.domestic.local:9090 |
| **Loki** | http://loki.domestic.local:3100 |

## 📝 Próximas Ações

1. **Deploy:** `kubectl apply -f observability/grafana/grafana-dashboard-traces-simple.configmap.yaml`
2. **Acessar:** `http://grafana.domestic.local/d/traces-simple`
3. **Testar:** `curl http://localhost:3000/tracing/order/test`
4. **Visualizar:** Veja o novo trace no painel do Grafana
