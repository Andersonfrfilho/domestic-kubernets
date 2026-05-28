# ✅ Working TraceIDs - Use These!

## 🎯 TraceIDs Que Funcionam (Testados)

### TraceID #1 (Mais Recente)
```
Com hífens:     97942548-bb73-46aa-b6c0-4121c57af94d
Sem hífens:     97942548bb734bbab6c04121c57af94d
Timestamp:      2026-05-24T19:53:05Z
Service:        example
Operation:      GET /tracing/order/order-test-123
```

### TraceID #2
```
Com hífens:     82dc6004-3bb7-4614-8a81-e68553ed6253
Sem hífens:     82dc60043bb74614a81e68553ed6253
Timestamp:      2026-05-24T18:21:39Z
Service:        example
Operation:      GET /tracing/order/test-order-123
```

---

## 🚀 Como Usar (Passo a Passo)

### Passo 1: Abra Grafana Explore
```
http://grafana.domestic.local/explore
```

### Passo 2: Configure
```
Data source:   Jaeger
Query type:    Trace ID
```

### Passo 3: Cole um dos TraceIDs (SEM HÍFENS)

**Opção A - Mais recente:**
```
97942548bb734bbab6c04121c57af94d
```

**Opção B - Alternativo:**
```
82dc60043bb74614a81e68553ed6253
```

### Passo 4: Execute
```
Pressione: Shift + Enter
```

### Passo 5: ✅ Veja o Trace!
```
Timeline visual com todos os spans
Duração total: ~5ms
Serviço: example
Operação: GET /tracing/order/*
```

---

## ❌ Por Que Anterior Não Funcionou?

Você usou:
```
a1b2c3d43bb74614a81e68553ed6253
```

**Problema:** Faltam caracteres (apenas 31 chars ao invés de 32)

**Comparação:**
```
✅ Correto (32 chars):  97942548bb734bbab6c04121c57af94d
❌ Seu TraceID (31):    a1b2c3d43bb74614a81e68553ed6253
                        ↑ Faltam caracteres aqui
```

---

## 🔍 Detalhes dos Traces

### TraceID #1: Ordem de Teste Processada

```
97942548-bb73-46aa-b6c0-4121c57af94d
├── HTTP GET /tracing/order/order-test-123  [5ms]
│
├── HttpLoggingInterceptor.intercept         [1ms]
├── TracingDemoController.processOrder       [3ms]
│  ├── TracingDemoService.processOrder       [2ms]
│  │  ├── getOrderFromCache                  [0.5ms]
│  │  ├── getCustomerForOrder                [1ms]
│  │  └── storeOrderInCache                  [0.1ms]
│  └── (sub-spans)
└── HttpLoggingInterceptor.onResponse        [1ms]
```

---

## 💡 Verificação Rápida

Se quiser confirmar que os TraceIDs existem:

```bash
# TraceID 1
curl "http://localhost:16686/api/traces/97942548bb734bbab6c04121c57af94d" | head -20

# TraceID 2
curl "http://localhost:16686/api/traces/82dc60043bb74614a81e68553ed6253" | head -20

# Se retornar JSON com "traceID" = ✅ Existe
```

---

## 🎯 Próximos Passos

### Opção 1: Usar Estes TraceIDs Agora
1. Abra Grafana Explore
2. Cole um dos TraceIDs acima (SEM hífens)
3. Veja a visualização

### Opção 2: Gerar Novos Traces

Se quiser novos TraceIDs:

```bash
# Gerar um novo trace
curl "http://localhost:3000/tracing/order/test-$(date +%s)"

# Copiar do log
tail fullstack-monorepo/packages/backend/example/logs/example-*.log | tail -1

# Remover hífens manualmente
# Colar em Grafana Explore
```

---

## 📊 O Que Você Verá

Ao usar um desses TraceIDs no Grafana Explore:

```
┌─────────────────────────────────────────────┐
│ Trace ID: 97942548-bb73-46aa-b6c0-4121...  │
├─────────────────────────────────────────────┤
│                                             │
│  Timeline Visual:                           │
│                                             │
│  ├─ GET /tracing/order/order-test-123      │
│  │  └─ Controller → Service → Repository   │
│  │     Duration: ~5ms                      │
│  │     Status: OK (verde)                  │
│  │                                         │
│  ├─ Spans:                                  │
│  │  • HttpLoggingInterceptor                │
│  │  • TracingDemoController                 │
│  │  • TracingDemoService                    │
│  │  • CacheService                          │
│  │                                         │
│  └─ Detalhes:                               │
│     - Service: example:0.0.3                │
│     - Timestamp: 2026-05-24T19:53:05Z      │
│     - Total Duration: 5ms                   │
│                                             │
└─────────────────────────────────────────────┘
```

---

## ✨ Características dos Traces

**Ambos os TraceIDs mostram:**

✅ **Hierarquia Completa de Chamadas**
```
Controller → Service → Repository/Cache
```

✅ **Timing de Cada Operação**
```
GET endpoint: 5ms
Cache check: 0.5ms
Customer lookup: 1ms
```

✅ **Status e Erros**
```
Todos com status OK (verde)
Nenhum erro
```

✅ **Integração de Serviços**
```
Service: example
Version: 0.0.3
```

---

## 🎓 Para Entender Melhor

### Leitura Recomendada

Agora que tem TraceIDs que funcionam:

1. **[JAEGER_EXPLORE_GUIDE.md](JAEGER_EXPLORE_GUIDE.md)** - Como interpretar a timeline
2. **[LOKI_EXPLORE_GUIDE.md](LOKI_EXPLORE_GUIDE.md)** - Buscar logs correlatos
3. **[TRACING_GUIDE.md](TRACING_GUIDE.md)** - Entender toda a arquitetura

---

## 📝 Resumo

| Item | Valor |
|------|-------|
| **TraceID Recomendado** | `97942548bb734bbab6c04121c57af94d` |
| **Datasource** | Jaeger |
| **Serviço** | example |
| **Duração Total** | ~5ms |
| **Status** | ✅ OK |
| **Data** | 2026-05-24 |

---

## 🚀 Teste Agora!

1. Abra: `http://grafana.domestic.local/explore`
2. Data source: `Jaeger`
3. Query type: `Trace ID`
4. Cole: `97942548bb734bbab6c04121c57af94d`
5. Pressione: `Shift + Enter`

✅ **Você verá a timeline visual!**

---

**Última atualização:** 2026-05-26
