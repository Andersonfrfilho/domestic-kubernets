# Jaeger Explorer Guide - Grafana

## 🚀 Quick Start: Visualizar Traces por TraceID

### Passo 1: Acessar Explore

```
http://grafana.domestic.local/explore
```

Ou no Grafana:
- Menu lateral → **Explore** (ícone de bússola)

### Passo 2: Selecionar Datasource

```
Data source: Jaeger
```

Se não aparecer:
1. Clique no dropdown "Data source"
2. Procure por **Jaeger**
3. Selecione

### Passo 3: Selecionar Query Type

```
Query type: Trace ID
```

### Passo 4: Colar o TraceID

Campo **"Trace ID"**:
```
a1b2c3d4e5f6  (ou o traceId que você quer visualizar)
```

### Passo 5: Executar

```
Pressione: Shift + Enter
```

**Resultado esperado:**
- Timeline visual dos spans
- Detalhes de cada operação
- Duração total do trace

---

## 📊 Como Obter um TraceID

### Opção 1: Do Log do Arquivo

```bash
# Verificar os logs do serviço
tail fullstack-monorepo/packages/backend/example/logs/example-*.log

# Saída típica:
[a1b2c3d4-3bb7-4614-8a81-e68553ed6253][2026-05-24T19:51:37.422Z][example:0.0.3][Controller][Service.processOrder][INFO] - Processing order
 ↑
 Primeiro campo entre [ ] = requestId (correlato do traceId)
```

### Opção 2: Do Header da Response

```bash
curl -v http://localhost:3000/health 2>&1 | grep -i "x-trace-id"

# Esperado:
# x-trace-id: a1b2c3d4e5f6
```

### Opção 3: Do Kubernetes

```bash
# Ver logs dos últimos 100 eventos
kubectl logs deployment/api -n domestic -c api --tail=100 | grep "^\[" | head -1

# Copiar o traceId (primeiro campo)
```

### Opção 4: Gerar um Novo

```bash
# Fazer uma requisição para criar um trace
curl http://localhost:3000/tracing/order/test-order-$(date +%s)

# Os logs aparecerão em tempo real:
tail -f fullstack-monorepo/packages/backend/example/logs/example-*.log
```

---

## 🔍 Interpretando a Visualização

### Exemplo de Trace Completo

```
GET /tracing/order/test-order-123          [duration: 145ms]
│
├─ HttpLoggingInterceptor.intercept         [5ms]    ✓
│
├─ TracingDemoController.processOrder       [100ms]  ✓
│  ├─ TracingDemoService.processOrder       [95ms]   ✓
│  │  ├─ getOrderFromCache                  [10ms]   ✓
│  │  ├─ getCustomerForOrder                [40ms]   ✓
│  │  │  └─ getCustomerId                   [35ms]   ✓
│  │  └─ storeOrderInCache                  [5ms]    ✓
│  └─ (other internal spans)
│
└─ HttpLoggingInterceptor.onResponse        [10ms]   ✓
```

**Legenda:**
- ✓ = Sucesso (verde)
- ✗ = Erro (vermelho)
- Duration = Tempo em ms

---

## 🎯 Casos de Uso Práticos

### Caso 1: Debugar Latência Alta

**Problema:** Uma rota está lenta

**Solução:**
1. Fazer a requisição: `curl http://localhost:3000/users?page=1`
2. Copiar traceId do log
3. Abrir Explore no Grafana
4. Query Type: **Trace ID**
5. Colar traceId
6. Executar (Shift + Enter)

**Resultado:**
```
GET /users?page=1                    [2000ms] ← LENTO!
│
├─ UserService.getUsers             [1800ms] ← CULPADO IDENTIFICADO
│  └─ PostgreSQL query               [1700ms] ← INDEX FALTANDO?
│
└─ ResponseInterceptor               [100ms]  ← OK
```

### Caso 2: Investigar Erro

**Problema:** Erro em uma operação

**Solução:**
1. Ver log: `[ERROR] user not found`
2. Encontrar traceId desse log
3. Abrir em Explore
4. Ver em qual span ocorreu o erro

**Resultado:**
```
POST /users                          [ERRO]
│
├─ UserService.create               [OK]
│  ├─ validateEmail                 [OK]
│  ├─ KeycloakClient.create         [ERROR] ← AQUI
│  │  └─ Connection timeout         ← CAUSA RAIZ
│  └─ [Transaction rolled back]
│
└─ ResponseInterceptor               [OK]
```

### Caso 3: Rastrear Fluxo Entre Serviços

**Problema:** Request vai de API → BFF → Worker

**Solução:**
1. Fazer request no BFF: `curl http://localhost:3001/bff/home`
2. Obter traceId
3. Abrir em Explore
4. Ver os spans de múltiplos serviços

**Resultado:**
```
GET /bff/home                        [200ms] [service: bff]
│
├─ BffHomeService.get               [180ms] [service: bff]
│  ├─ ApiClient.getUsers            [150ms] [service: bff→api]
│  │  └─ GET /api/users             [140ms] [service: api]
│  │     ├─ UserService.getUsers    [100ms]
│  │     └─ ResponseInterceptor     [20ms]
│  │
│  └─ CacheService.set              [10ms]  [service: bff]
│
└─ ResponseInterceptor               [10ms]
```

---

## 🛠️ Opções Avançadas

### Query Type: "Search"

Buscar traces sem saber o TraceID:

1. Query type: **Search**
2. Preencher filtros:
   - **Service:** api (ou exemplo, bff, etc)
   - **Operation:** GET /users
   - **Tags:** error=true (para erros)
   - **Min Duration:** 100ms (para operações lentas)
3. Executar

**Resultado:** Lista de últimos traces que correspondem aos critérios

### Filtrar por Serviço

```
Filtros disponíveis:
- Service: api, bff, example, worker, cron
- Operation: GET /path, POST /path, etc
- Status: OK, ERROR, UNSET
- Duration: min...max
- Tags: key=value
```

### Análise de Performance

**Para encontrar operações lentas:**

1. Query type: Search
2. Service: api
3. Min Duration: 500ms (500 milissegundos)
4. Executar
5. Ver quais operações aparecem

---

## 📈 Visualizações Disponíveis

No Explore, você pode ver:

### 1. **Timeline** (padrão)
- Mostra spans em ordem temporal
- Hierarquia visual
- Clique em um span para expandir

### 2. **Trace Statistics**
- Total duration
- Service count
- Span count
- Error count

### 3. **Service Graph**
- Mostra quais serviços se comunicam
- Latência entre serviços
- Taxa de erro entre serviços

### 4. **Logs**
- Logs capturados durante a execução
- Correlados ao span específico

---

## 🔗 Atalhos de Teclado

| Atalho | Ação |
|--------|------|
| `Shift + Enter` | Executar query |
| `Ctrl + K` | Busca rápida (search) |
| `Escape` | Fechar painel de detalhes |
| `Click span` | Expandir/recolher |

---

## ⚠️ Troubleshooting

### "No data" aparece

**Razão 1: TraceID inválido**
```bash
# Verificar formato do traceId
# Deve ter 12 ou 32 caracteres hex (0-9, a-f)

# Exemplo válido:
a1b2c3d4e5f6        ✓ (12 chars)
a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4  ✓ (32 chars)

# Exemplo inválido:
a1b2c3d4     ✗ (muito curto)
xyz123       ✗ (caracteres inválidos)
```

**Razão 2: TraceID não existe mais**
```bash
# Jaeger tem retenção de dados (padrão: 72 horas)
# Se o trace é muito antigo, foi deletado

# Solução: Gerar um novo trace
curl http://localhost:3000/health
```

**Razão 3: Datasource não está conectado**
```bash
# Verificar se Jaeger está acessível
curl http://localhost:16686/api/services

# Se falhar:
# - Verificar if Jaeger container está rodando
# - Verificar se Jaeger está em http://jaeger:16686 no kubernetes
```

### "Trace ID não encontrado"

1. Copie o traceId completo (sem espaços)
2. Execute: `Shift + Enter`
3. Aguarde alguns segundos (latência de rede)
4. Se ainda não aparecer, tente outro traceId

---

## 📝 Exemplo Prático Completo

### Passo a Passo

```bash
# 1. Gerar um trace
curl "http://localhost:3000/tracing/order/order-$(date +%s%N | cut -c1-13)"

# 2. Copiar traceId do log
tail fullstack-monorepo/packages/backend/example/logs/example-*.log | tail -1
# Output: [a1b2c3d4-3bb7-4614-...][timestamp][...]...

# 3. Abrir Grafana Explore
# http://grafana.domestic.local/explore

# 4. Preencher:
# - Data source: Jaeger
# - Query type: Trace ID
# - Trace ID: a1b2c3d4-3bb7-4614

# 5. Executar: Shift + Enter

# 6. Visualizar a timeline completa!
```

---

## 🎓 Dicas Profissionais

1. **Salve TraceIDs importantes**
   - Copie para um arquivo de referência
   - Use para comparações posteriores

2. **Compare dois traces**
   - Abra dois painéis side-by-side
   - Veja diferenças de latência

3. **Corrija problemas de performance**
   - Identifique o span mais lento
   - Otimize aquela função/query

4. **Monitore em produção**
   - Use alertas baseados em latência
   - Crie dashboards com traces agregados

---

## 📞 Suporte

Se os traces não aparecem:

```bash
# 1. Verificar se Jaeger está rodando
kubectl get pod -n domestic | grep jaeger

# 2. Ver logs do Jaeger
kubectl logs -n domestic deployment/jaeger -c jaeger

# 3. Testar conectividade
kubectl exec -it deployment/api -n domestic -- curl http://jaeger:16686/api/services

# 4. Verificar se há dados
curl http://localhost:16686/api/services
# Esperado: {"data":["api","bff","example","worker","cron"]}
```
