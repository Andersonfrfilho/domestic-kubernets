# Loki Explorer Guide - Grafana

## 🚀 Quick Start: Buscar Logs por TraceID

### Passo 1: Acessar Explore

```
http://grafana.domestic.local/explore
```

Ou no Grafana:
- Menu lateral → **Explore**

### Passo 2: Selecionar Datasource

```
Data source: Loki
```

### Passo 3: Selecionar Labels (Queryless)

Clique em **"Go queryless"** para interface visual.

Ou escreva a query diretamente:

```loki
{job="domestic"} | json | trace_id="a1b2c3d4"
```

### Passo 4: Buscar por TraceID

**Opção A: Via Label Browser (visual)**

1. **Label filters** → Select label → `trace_id`
2. → `=` (equals)
3. → Cole o TraceID: `a1b2c3d4`
4. → Pressione **Enter**

**Opção B: Via Query (texto)**

```loki
{job="domestic"} | json | trace_id="a1b2c3d4"
```

Pressione: **Shift + Enter**

---

## 📊 O Que Você Verá

### Formato dos Logs

Cada linha de log contém:

```
[requestId][timestamp][service:version][Class.method][LEVEL] - message
```

**Exemplo:**
```
[a1b2c3d4-3bb7-4614-8a81-e68553ed6253][2026-05-24T19:51:37.422Z][example:0.0.3][Controller.processOrder][INFO] - Processing order
```

### Interpretação

| Campo | Significado |
|-------|-------------|
| `a1b2c3d4-...` | RequestID / TraceID (correlação com Jaeger) |
| `2026-05-24T19:51:37.422Z` | Timestamp ISO 8601 |
| `example:0.0.3` | Service name e version |
| `Controller.processOrder` | Hierarquia de chamadas |
| `INFO` | Log level (DEBUG, INFO, WARN, ERROR) |
| `Processing order` | Mensagem de log |

---

## 🔍 Tipos de Query

### 1. Buscar por TraceID

```loki
{job="domestic"} | json | trace_id="a1b2c3d4"
```

**Resultado:** Todos os logs correlatos ao trace

### 2. Buscar por Serviço

```loki
{job="domestic", service="api"}
```

**Resultado:** Apenas logs do serviço API

### 3. Buscar por Nível (ERROR, WARN, etc)

```loki
{job="domestic"} | json | level="ERROR"
```

**Resultado:** Apenas logs de erro

### 4. Buscar por Palavra-chave

```loki
{job="domestic"} |= "user created"
```

**Resultado:** Logs contendo "user created"

### 5. Combinar Filtros

```loki
{job="domestic", service="api"} | json | level="ERROR" |= "timeout"
```

**Resultado:**
- Serviço: api
- Nível: ERROR
- Contém: "timeout"

### 6. Buscar com Regex

```loki
{job="domestic"} |~ "user.*created"
```

**Resultado:** Logs que matcham regex

---

## 💡 Exemplos Práticos

### Caso 1: Debugar uma Requisição

**Cenário:** Você fez uma requisição e quer ver TODOS os logs dela.

```bash
# 1. Fazer a requisição
curl http://localhost:3000/users/123

# 2. Copiar o requestId do log
# [a1b2c3d4-3bb7-...][...]...

# 3. Em Grafana Loki Explorer
{job="domestic"} | json | trace_id="a1b2c3d4"

# 4. Ver toda a sequência de logs da requisição
```

**Resultado esperado:**
```
[a1b2c3d4-...][T1][Controller][GET /users/123][INFO] - HTTP Request
[a1b2c3d4-...][T2][Service][fetchUser][INFO] - Fetching user
[a1b2c3d4-...][T3][Repository][find][DEBUG] - Query: SELECT * FROM users
[a1b2c3d4-...][T4][Service][fetchUser][INFO] - User fetched successfully
[a1b2c3d4-...][T5][Controller][HTTP Response][INFO] - Response 200 OK
```

### Caso 2: Encontrar Erros

**Cenário:** Houve um erro no sistema e você quer rastrear a causa.

```loki
{job="domestic"} | json | level="ERROR"
```

**Resultado:**
```
[xyz789...][T1][Service][validateEmail][ERROR] - Invalid email format
[abc123...][T2][Database][query][ERROR] - Connection timeout
[def456...][T3][Queue][publish][ERROR] - Message queue full
```

### Caso 3: Performance - Operações Lentas

**Cenário:** Encontrar chamadas ao banco de dados que levam muito tempo.

```loki
{job="domestic"} |= "Database" | json | duration > 1000
```

(Se o log tiver o campo duration em ms)

**Resultado:**
```
[...]Database.query took 1523ms
[...]Database.findAll took 2150ms
```

### Caso 4: Rastrear Fluxo Entre Serviços

**Cenário:** Uma requisição passa por api → bff → worker.

```bash
# 1. Fazer requisição no BFF
curl http://localhost:3001/bff/home

# 2. Copiar traceId
# [a1b2c3d4-...]

# 3. Buscar em Loki
{job="domestic"} | json | trace_id="a1b2c3d4"

# 4. Ver os logs de todos os 3 serviços
```

**Logs esperados:**
```
[a1b2c3d4-...][T1][bff][Controller][GET /bff/home][INFO] - Request started
[a1b2c3d4-...][T2][bff][BffService][getHome][INFO] - Fetching data from API
[a1b2c3d4-...][T3][api][Controller][GET /api/home][INFO] - API request received
[a1b2c3d4-...][T4][api][Service][getHome][INFO] - Processing...
[a1b2c3d4-...][T5][api][Controller][HTTP Response][INFO] - Returning 200
[a1b2c3d4-...][T6][bff][BffService][getHome][INFO] - Data received
[a1b2c3d4-...][T7][bff][Controller][HTTP Response][INFO] - Response sent
```

---

## 🎓 Linguagem de Query do Loki

### Sintaxe Básica

```
{label="value"} | filter1 | filter2 | format
```

### Label Filters

```loki
{job="domestic"}              # Labels simples
{service="api", level="warn"} # Múltiplos labels
{service!="worker"}           # Negação (!= opposite)
{service=~"api|bff"}          # Regex (=~ match, !~ não match)
```

### Pipe Filters (|)

```loki
{job="domestic"} 
  | json                      # Parse JSON
  | level="error"             # Filtrar por JSON field
  |= "keyword"                # Contém (=|) 
  |~ "pattern.*regex"         # Regex match (!~ opposite)
```

### Extração de Valores

```loki
{job="domestic"} 
  | json 
  | trace_id
  | duration
```

---

## 📈 Operações Avançadas

### Agrupar por Label

No painel, mude para **Type: Range** e use:

```loki
{job="domestic"} | json | level="error" 
| stats count() by service
```

**Resultado:**
```
service="api"     count=5
service="bff"     count=2
service="worker"  count=1
```

### Contar Ocorrências

```loki
{job="domestic"} 
| json 
| level="error" 
| stats count()
```

**Resultado:** Total de erros

### Taxa de Erro

```loki
{job="domestic"} 
| json 
| stats count() as total, count(level="error") as errors
| eval error_rate=errors/total*100
```

---

## 🔗 Correlação Logs ↔ Traces

### Ligação Automática

Quando visualizando logs no Loki:

1. **Veja um log com traceId**
   ```
   [a1b2c3d4-...][timestamp][service][method][LEVEL] - message
   ```

2. **Clique no traceId** (primeiro campo)

3. **Será redirecionado para Jaeger** com o trace aberto

### Processo Inverso (Trace → Logs)

1. Visualize um trace no **Jaeger Explore**
2. Clique em **"Logs"** (no painel de detalhes do span)
3. **Será redirecionado para Loki** com os logs correspondentes

---

## 🛠️ Troubleshooting

### "No data" aparece

**Razão 1: TraceID inválido**
```
Formato válido:
✓ a1b2c3d4-3bb7-4614-8a81-e68553ed6253 (UUID)
✓ a1b2c3d4 (short hash)

Formato inválido:
✗ a1b2c3d4- (incompleto)
✗ trace_id=xyz (não é um ID)
```

**Razão 2: Logs não foram gerados**
```bash
# Fazer uma requisição para gerar logs
curl http://localhost:3000/health

# Aguardar 1-2 segundos
# Tentar a query novamente
```

**Razão 3: Label filter incorreto**
```
Verificar:
- O nome do label existe?
- O valor é exato (case-sensitive)?
- Usar = em vez de ==
```

### Query não retorna resultados

**Verificar estrutura do log:**
```bash
# Ver um log recente
tail fullstack-monorepo/packages/backend/example/logs/example-*.log | head -1

# Deve ser JSON ou texto estruturado
[requestId][timestamp][...][LEVEL] - message
```

**Se não for JSON:**
```loki
{job="domestic"} |= "word"  # Buscar por palavra-chave
```

**Se for JSON:**
```loki
{job="domestic"} | json | field="value"
```

---

## 📝 Query Cheat Sheet

| Caso | Query |
|------|-------|
| Todos logs recentes | `{job="domestic"}` |
| Por serviço | `{service="api"}` |
| Por nível | `{job="domestic"} \| json \| level="ERROR"` |
| Por traceId | `{job="domestic"} \| json \| trace_id="abc123"` |
| Contém palavra | `{job="domestic"} \|= "error"` |
| Erros apenas | `{job="domestic"} \|= "error" or "failed" or "exception"` |
| Últimas 100 linhas | `{job="domestic"} \| limit 100` |

---

## 🔄 Workflow Completo: Logs + Traces

### Cenário: Debugar uma falha

```
1. Ver um erro no Loki
   ↓
2. Copiar traceId do log
   ↓
3. Abrir Jaeger Explore
   ↓
4. Colar traceId
   ↓
5. Ver timeline visual do trace
   ↓
6. Identificar qual span causou o erro
   ↓
7. Voltar para Loki para investigar logs específicos
   ↓
8. Encontrar a causa raiz!
```

---

## 📊 Dashboard de Logs

Para visualizar logs em um dashboard (não apenas no Explore):

1. Ir para Dashboards
2. Procurar por **"Domestic Logs"**
3. Ver painéis com:
   - Todos os logs
   - Logs de email
   - Logs de autenticação
   - Logs de fila/RabbitMQ
   - Logs de database

---

## 🎯 Best Practices

1. **Sempre correlacione logs com traces**
   - Logs mostram mensagens detalhadas
   - Traces mostram timing visual

2. **Use traceIds para debugging**
   - Siga uma requisição do início ao fim
   - Veja todos os serviços envolvidos

3. **Alerte sobre padrões de erro**
   - Configure alertas no Grafana
   - Baseado em padrões de logs

4. **Archive logs antigos**
   - Loki tem limite de armazenamento
   - Configure retenção adequadamente

---

## 📞 Suporte Rápido

```bash
# Verificar se Loki tem dados
curl http://localhost:3100/loki/api/v1/labels

# Fazer uma requisição para gerar logs
curl http://localhost:3000/health

# Ver logs diretos
tail -f fullstack-monorepo/packages/backend/example/logs/example-*.log
```

---

**Última atualização:** 2026-05-26
