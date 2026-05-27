# 🔍 Generate Valid TraceID - Fix "404 Not Found"

## ❌ O Erro

```
request failed: 404 Not Found
```

**Significa:** O TraceID não existe no Jaeger

---

## ✅ A Solução

### Passo 1: Gerar um NOVO Trace

```bash
# Fazer uma requisição para criar um trace
curl http://localhost:3000/tracing/order/test-$(date +%s)

# Ou mais simples
curl http://localhost:3000/health
```

**Aguarde 1-2 segundos** para o Jaeger receber os dados.

### Passo 2: Obter o TraceID

**Opção A: Do arquivo de log**

```bash
# Ver os logs do serviço
tail -f fullstack-monorepo/packages/backend/example/logs/example-*.log

# Procurar por uma linha RECENTE como:
[a1b2c3d4-3bb7-4614-8a81-e68553ed6253][2026-05-24T19:51:37.422Z][example:0.0.3][Controller][INFO] - HTTP Request

# Copiar o primeiro campo:
a1b2c3d4-3bb7-4614-8a81-e68553ed6253
```

**Opção B: Ver direto no Jaeger UI**

```
http://jaeger.domestic.local
→ Service: example
→ Operation: GET /tracing/order/*
→ Ver traces recentes
→ Clicar em um
→ TraceID aparece na URL: /trace/{traceId}
```

### Passo 3: Remover Hífens

Se o TraceID tiver hífens:
```
c19f3886-5014-4778-a1e9-025ef700e450
```

Remova:
```
c19f38865014477a1e9025ef700e450
```

### Passo 4: Colar no Grafana

1. Abra: `http://grafana.domestic.local/explore`
2. Data source: **Jaeger**
3. Query type: **Trace ID**
4. Cole o TraceID (SEM hífens)
5. Pressione: **Shift + Enter**

✅ **Pronto!** Você verá o trace.

---

## 🔧 Verificar Se Jaeger Tem Dados

### Teste 1: Jaeger API

```bash
# Ver que serviços reportam traces
curl http://localhost:16686/api/services

# Esperado:
# {"data":["api","bff","example","worker","cron"]}

# Se vazio = nenhum serviço está enviando traces
```

### Teste 2: Traços de um Serviço

```bash
# Ver traces do serviço "example"
curl "http://localhost:16686/api/traces?service=example&limit=10"

# Esperado: JSON com lista de traces recentes
```

### Teste 3: Verificar um TraceID

```bash
# Buscar um TraceID específico
curl "http://localhost:16686/api/traces/{traceId}"

# Se retornar 200 OK = exists ✅
# Se retornar 404 = doesn't exist ❌
```

---

## 🆘 Por Que Pode Não Existir?

### Motivo 1: Muito Antigo (Expirou)

Jaeger mantém traces por **72 horas** por padrão.

**Verificar:**
```bash
# Ver quando o trace foi criado
# Se for mais de 72h atrás → foi deletado

# Solução: Gerar um NOVO trace agora
curl http://localhost:3000/health
```

### Motivo 2: Serviço Não Está Enviando Traces

**Verificar se OpenTelemetry iniciou:**

```bash
# Ver logs do serviço
kubectl logs deployment/api -n domestic | grep -i "OpenTelemetry initialized"

# Esperado:
# [tracing] OpenTelemetry initialized — service=api idFormat=short-hash endpoint=http://jaeger:4318 sampler=parentbased_always_on
```

**Se NÃO aparecer:**
- ✅ Verificar se `initTracing()` está sendo chamado
- ✅ Verificar se `instrumentation.ts` é importado em `main.ts`
- ✅ Reiniciar o serviço

### Motivo 3: Jaeger Não Está Recebendo Dados

**Verificar conectividade:**

```bash
# Do pod do serviço, testar conexão com Jaeger
kubectl exec -it deployment/api -n domestic -- \
  curl http://jaeger:16686/api/services

# Se falhar = Jaeger não está acessível
```

**Verificar Jaeger está rodando:**

```bash
# Ver se o pod existe
kubectl get pods -n domestic | grep jaeger

# Ver logs do Jaeger
kubectl logs deployment/jaeger -n domestic
```

### Motivo 4: TraceID Digitado Incorretamente

```
c19f38865014477a1e9025ef700e450  ← Correto (32 chars hex)
c19f388650144778a1e9025ef700e45   ← Errado (falta 1 char)
c19f388650144778a1e9025ef700e450x ← Errado (char extra)
```

**Solução:** Copiar-colar cuidadosamente

---

## ✅ Teste Completo: Passo a Passo

### Passo 1: Gerar Trace

```bash
cd /home/miyazaki/Documents/personal/domestic
curl "http://localhost:3000/tracing/order/order-test-$(date +%s%N | cut -c1-13)"
```

**Esperado:** Resposta JSON com dados do pedido.

### Passo 2: Copiar TraceID

```bash
# Ver os logs imediatamente
tail -1 fullstack-monorepo/packages/backend/example/logs/example-*.log

# Exemplo de saída:
# [a1b2c3d4-3bb7-4614-8a81-e68553ed6253][2026-05-24T19:51:37.422Z][example:0.0.3][Controller.processOrder][INFO] - Processing order

# Copiar: a1b2c3d4-3bb7-4614-8a81-e68553ed6253
```

### Passo 3: Verificar no Jaeger API

```bash
# Remover hífens primeiro
# c19f3886-5014-4778-a1e9-025ef700e450 → c19f38865014477a1e9025ef700e450

curl "http://localhost:16686/api/traces/c19f38865014477a1e9025ef700e450"

# Se retornar JSON com spans = ✅ Existe
# Se retornar erro 404 = ❌ Não existe (aguardar mais um pouco)
```

### Passo 4: Visualizar no Grafana

1. Abra: `http://grafana.domestic.local/explore`
2. Data source: **Jaeger**
3. Query type: **Trace ID**
4. Cole (SEM hífens): `c19f38865014477a1e9025ef700e450`
5. Pressione: **Shift + Enter**

✅ **Sucesso!** Você verá a timeline.

---

## 🚀 Script Automático

Crie um script para fazer isso automaticamente:

```bash
#!/bin/bash
# get-and-visualize-trace.sh

# 1. Generate trace
echo "Generating trace..."
curl -s "http://localhost:3000/tracing/order/test-$(date +%s)" > /dev/null

# 2. Wait
sleep 2

# 3. Get traceId from logs
echo "Extracting traceId..."
trace_id=$(tail -1 fullstack-monorepo/packages/backend/example/logs/example-*.log | grep -o '\[.*\]' | head -1 | tr -d '[]')

# 4. Remove hyphens
trace_id_clean="${trace_id//-/}"

echo "TraceID: $trace_id_clean"

# 5. Verify in Jaeger
echo "Verifying in Jaeger..."
if curl -s "http://localhost:16686/api/traces/$trace_id_clean" | grep -q "traceID"; then
  echo "✅ Trace found!"
  echo "Open in Grafana: http://grafana.domestic.local/explore"
  echo "Paste TraceID: $trace_id_clean"
else
  echo "❌ Trace not found (yet). Wait a few seconds and try again."
fi
```

**Uso:**
```bash
chmod +x get-and-visualize-trace.sh
./get-and-visualize-trace.sh
```

---

## 📊 Checklist: Jaeger Está Funcionando?

- [ ] `curl http://localhost:16686/api/services` retorna `{"data":["api",...]}` ✅
- [ ] Pelo menos um serviço na lista
- [ ] Fazer `curl http://localhost:3000/health`
- [ ] `curl http://localhost:16686/api/services` mostra `"example"` na lista
- [ ] Ver logs do example: `tail fullstack-monorepo/packages/backend/example/logs/example-*.log`
- [ ] TraceID aparece nos logs `[xxx-xxx-xxx]`
- [ ] Remover hífens do TraceID
- [ ] `curl http://localhost:16686/api/traces/{traceId}` retorna 200 OK
- [ ] Colar no Grafana Explore → Jaeger → TraceID
- [ ] Ver timeline visual ✅

Se todos os passos passarem → Jaeger está 100% funcional!

---

## 🆘 Ainda Não Funciona?

### Verificação 1: OpenTelemetry Inicializando?

```bash
# Ver logs de inicialização
kubectl logs deployment/api -n domestic | grep -A2 -B2 "OpenTelemetry"

# Se NÃO aparecer "OpenTelemetry initialized":
# 1. Verificar src/instrumentation.ts
# 2. Verificar src/main.ts import './instrumentation'
# 3. Reiniciar: kubectl rollout restart deployment/api -n domestic
```

### Verificação 2: Jaeger Recebendo Dados?

```bash
# Ver logs do Jaeger
kubectl logs deployment/jaeger -n domestic | tail -20

# Procurar por:
# - "Started gRPC server"
# - "Started HTTP server"
# - Nenhum erro de conexão
```

### Verificação 3: Prometheus Vendo Spans?

```bash
# Ver métricas de spans
curl http://localhost:9090/api/v1/query?query=span_received_total

# Se vazio = nenhum span foi recebido
# Se tem dados = ✅ Jaeger está recebendo
```

### Verificação 4: Firewall/Network?

```bash
# Do pod da app, pode alcançar Jaeger?
kubectl exec -it deployment/api -n domestic -- \
  curl -v http://jaeger:16686/api/services

# Se falhar = problema de rede
# Se passar = ✅ Conectividade OK
```

---

## 📝 Resumo Rápido

```
❌ 404 Not Found
  ↓
Gerar novo trace: curl http://localhost:3000/health
  ↓
Copiar TraceID do log: tail example-*.log
  ↓
Remover hífens
  ↓
Colar em Grafana Explore → Jaeger
  ↓
✅ Ver trace!
```

---

**Última atualização:** 2026-05-26
