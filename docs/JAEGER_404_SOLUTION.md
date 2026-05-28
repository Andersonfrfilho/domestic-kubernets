# 🔧 Jaeger 404 Solution - No Data Found

## ❌ O Erro

```
request failed: 404 Not Found
```

**O que significa:** Jaeger não tem dados para esse TraceID

---

## 🔍 Por Que Acontece?

### Motivo 1: **Jaeger Está Vazio** (Mais Provável)

- Nenhum serviço enviando traces
- Ou está em Kubernetes e você está testando em localhost

### Motivo 2: **OpenTelemetry Não Inicializa**

- `initTracing()` não sendo chamado
- `instrumentation.ts` não é importado

### Motivo 3: **Jaeger Não Está Acessível**

- Está em Kubernetes, não localhost
- Network problem

---

## ✅ Solução: Verificar Jaeger em Kubernetes

### Passo 1: Verificar Se Jaeger Existe

```bash
# Ver todos os pods
kubectl get pods -n domestic

# Esperado: jaeger pod rodando
# jaeger-0    1/1     Running   0          10d
```

### Passo 2: Acessar Jaeger em Kubernetes

```bash
# Fazer port-forward
kubectl port-forward deployment/jaeger 16686:16686 -n domestic
```

**Depois acesse:**
```
http://localhost:16686
```

### Passo 3: Verificar Se Há Serviços Reportando

```bash
# Query diretamente
curl http://localhost:16686/api/services

# Esperado:
# {"data":["api","bff","example","worker","cron"]}

# Se vazio [] = nenhum serviço está enviando dados
```

---

## 🚀 Se Jaeger Está Vazio

### Opção 1: Gerar um Novo Trace (Recomendado)

```bash
# 1. Port forward do serviço (ex: API)
kubectl port-forward deployment/api 3000:3000 -n domestic

# 2. Em outro terminal, fazer uma requisição
curl http://localhost:3000/health

# 3. Aguardar 2-3 segundos

# 4. Verificar em Jaeger
# http://localhost:16686
# → Service: api
# → Procurar novo trace
```

### Opção 2: Verificar Se OpenTelemetry Está Inicializando

```bash
# Ver logs do serviço
kubectl logs deployment/api -n domestic | grep -i "OpenTelemetry\|tracing"

# Esperado:
# [tracing] OpenTelemetry initialized — service=api idFormat=short-hash endpoint=http://jaeger:4318

# Se NÃO aparecer:
# 1. Verificar src/instrumentation.ts
# 2. Verificar import em src/main.ts
# 3. Rebuild & redeploy
```

### Opção 3: Forçar Restart dos Serviços

```bash
# Restart todos os serviços para inicializar tracing
kubectl rollout restart deployment/api -n domestic
kubectl rollout restart deployment/bff -n domestic
kubectl rollout restart deployment/worker -n domestic
kubectl rollout restart deployment/cron -n domestic

# Aguardar rollout
kubectl rollout status deployment/api -n domestic

# Depois fazer uma requisição
curl -H "Host: api.domestic.local" http://localhost:3000/health
```

---

## 📋 Checklist: Jaeger Tem Dados?

- [ ] Jaeger pod está rodando: `kubectl get pods -n domestic | grep jaeger`
- [ ] Port forward ativo: `kubectl port-forward deployment/jaeger 16686:16686`
- [ ] Jaeger UI acessível: `http://localhost:16686`
- [ ] Serviços na lista: `curl http://localhost:16686/api/services` retorna `["api","bff",...`
- [ ] Trace recente existe: `http://localhost:16686/?service=api` mostra traces
- [ ] TraceID não expirou: Menos de 72h atrás

Se TODOS passarem → Jaeger está pronto!

---

## 🎯 Solução Rápida (Se Estiver em Kubernetes)

### Terminal 1: Port Forward

```bash
kubectl port-forward deployment/jaeger 16686:16686 -n domestic &
```

### Terminal 2: Gerar Trace

```bash
# Port forward do API
kubectl port-forward deployment/api 3000:3000 -n domestic &

# Fazer requisição
curl http://localhost:3000/health
curl http://localhost:3000/tracing/order/test-$(date +%s)

# Aguardar 2 segundos
sleep 2
```

### Terminal 3: Verificar Jaeger

```bash
# Ver serviços
curl http://localhost:16686/api/services

# Copiar um TraceID
curl http://localhost:16686/api/traces?service=api | jq '.data[0].traceID' -r

# Testar no Grafana Explore
# Cole o TraceID (sem hífens)
```

---

## 📊 Cenários Comuns

### Cenário 1: "Jaeger UI vazio, nenhum serviço aparece"

**Diagnóstico:**
```bash
kubectl logs deployment/api -n domestic | grep "OpenTelemetry"
```

**Se NÃO aparecer:**
- initTracing() não está sendo chamado
- Reconstruir imagem
- Redeploy

**Se APARECER:**
- Services estão enviando, mas Jaeger storage está vazio
- Jaeger foi reiniciado e perdeu dados
- Esperar novos traces chegarem

### Cenário 2: "Jaeger tem serviços mas sem traces"

**Diagnóstico:**
```bash
# Ver logs de NENHUM span sendo recebido
kubectl logs deployment/jaeger -n domestic | grep -i "span\|drop\|invalid"
```

**Solução:**
- Forçar um novo trace: `curl http://localhost:3000/health`
- Aguardar 2-3 segundos
- Jaeger processa em batch

### Cenário 3: "TraceID existe em logs mas não em Jaeger"

**Diagnóstico:**
```bash
# Comparar
# Log: [82dc6004-3bb7-4614-8a81-e68553ed6253]
# Jaeger espera: 82dc60043bb74614a81e68553ed6253 (sem hífens)
```

**Solução:**
- Remover hífens do TraceID
- Ou mudar OTEL_ID_FORMAT para uuid-no-hyphens

---

## 🔗 Relacionado

- [WORKING_TRACEIDS.md](WORKING_TRACEIDS.md) - TraceIDs que funcionam
- [JAEGER_TRACEID_FORMAT_FIX.md](JAEGER_TRACEID_FORMAT_FIX.md) - Formato de TraceID
- [GENERATE_VALID_TRACEID.md](GENERATE_VALID_TRACEID.md) - Gerar novo TraceID

---

## 📞 Debug Completo

Se nada funcionar:

```bash
# 1. Verificar Jaeger exists
kubectl describe pod jaeger-0 -n domestic

# 2. Ver logs
kubectl logs deployment/jaeger -n domestic | tail -50

# 3. Testar conectividade
kubectl exec -it deployment/api -n domestic -- \
  curl http://jaeger:16686/api/services

# 4. Verificar storage
kubectl exec -it deployment/jaeger -n domestic -- \
  ls -la /jaeger/data

# 5. Reiniciar Jaeger
kubectl rollout restart deployment/jaeger -n domestic
```

---

**Próximo passo:** [WORKING_TRACEIDS.md](WORKING_TRACEIDS.md)
