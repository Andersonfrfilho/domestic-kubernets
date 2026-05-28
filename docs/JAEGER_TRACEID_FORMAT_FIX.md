# 🔧 Jaeger TraceID Format - Fix "400 Bad Request"

## ❌ O Erro

```
request failed: 400 Bad Request
```

**Ao tentar buscar:**
```
c19f3886-5014-4778-a1e9-025ef700e450  (UUID com hífens)
```

---

## ✅ A Causa

O Jaeger está configurado com **`short-hash` format** (padrão):
```
12 caracteres hex: a1b2c3d4e5f6
```

Mas você está passando um **UUID com hífens**:
```
c19f3886-5014-4778-a1e9-025ef700e450  (36 caracteres com hífens)
```

---

## 🔧 Soluções

### Opção 1: Remover os Hífens (Recomendado)

**TraceID com hífens:**
```
c19f3886-5014-4778-a1e9-025ef700e450
```

**Converter para sem hífens:**
```
c19f38865014477a1e9025ef700e450
```

**No Grafana Explore:**
1. Apague os hífens manualmente
2. Cole: `c19f38865014477a1e9025ef700e450`
3. Pressione: **Shift + Enter**

---

### Opção 2: Usar Apenas os Primeiros 12 Caracteres

Se o TraceID for muito longo, use apenas o **primeiro segmento**:

**TraceID completo:**
```
c19f3886-5014-4778-a1e9-025ef700e450
```

**Primeiros 12 hex sem hífens:**
```
c19f38865014
```

**No Grafana:**
- Cole: `c19f38865014`
- Pressione: **Shift + Enter**

---

### Opção 3: Mudar Configuração do OTEL_ID_FORMAT (Kubernetes)

Se quiser que o sistema gere TraceIDs com hífens:

**Editar ConfigMap do Jaeger:**

```bash
kubectl edit configmap api-config -n domestic
```

**Procurar por OTEL_ID_FORMAT e mudar:**

```yaml
OTEL_ID_FORMAT: uuid-with-hyphens  # Muda de short-hash
```

**Depois, reiniciar os serviços:**

```bash
kubectl rollout restart deployment/api -n domestic
kubectl rollout restart deployment/bff -n domestic
kubectl rollout restart deployment/worker -n domestic
kubectl rollout restart deployment/cron -n domestic
```

**Novo comportamento:**
- ✅ TraceID gerado: `c19f3886-5014-4778-a1e9-025ef700e450`
- ✅ Pode colar direto com hífens
- ✅ Compatível com Jaeger UI

---

## 🎯 Recomendação

**Use a Opção 1** (remover hífens) porque:
- ✅ Sem mudanças no código
- ✅ Sem restart de serviços
- ✅ Mais rápido
- ⚠️ Um pouco menos legível

**Só use Opção 3** se quiser:
- ✅ TraceIDs com hífens em todos os logs
- ✅ Compatibilidade com ferramentas externas
- ⚠️ Requer restart de serviços

---

## 📋 Explicação dos Formatos

| Formato | Exemplo | Tamanho | Jaeger UI | Grafana |
|---------|---------|---------|-----------|---------|
| `short-hash` | `a1b2c3d4e5f6` | 12 chars | ✅ | Precisa sem hífens |
| `full-hash` | `a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4` | 32 chars | ✅ | Precisa sem hífens |
| `uuid-no-hyphens` | `c19f38865014477a1e9025ef700e450` | 32 chars | ✅ | ✅ Funciona direto |
| `uuid-with-hyphens` | `c19f3886-5014-4778-a1e9-025ef700e450` | 36 chars | ✅ | ✅ Funciona direto |

---

## 🔍 Identificar Qual Formato Você Tem

### Método 1: Verificar os Logs

```bash
# Ver um log recente
tail fullstack-monorepo/packages/backend/example/logs/example-*.log | head -1

# Procurar pelo primeiro [...]
# [a1b2c3d4][...] → short-hash (12 chars, sem hífens)
# [c19f38865014477a1e9025ef700e450][...] → full-hash (32 chars, sem hífens)
# [c19f3886-5014-4778-a1e9-025ef700e450][...] → uuid-with-hyphens (36 chars, com hífens)
```

### Método 2: Verificar Configuração

```bash
# Ver qual é o OTEL_ID_FORMAT configurado
kubectl get configmap api-config -n domestic -o yaml | grep OTEL_ID_FORMAT

# Se não estiver setado, padrão é: short-hash
```

---

## 🎯 Passo a Passo para Corrigir

### Se você tem: `c19f3886-5014-4778-a1e9-025ef700e450`

**Passo 1:** Remove os hífens
```
c19f38865014477a1e9025ef700e450
```

**Passo 2:** Abra Grafana Explore
```
http://grafana.domestic.local/explore
```

**Passo 3:** Configure
```
Data source: Jaeger
Query type: Trace ID
```

**Passo 4:** Cole o TraceID SEM hífens
```
c19f38865014477a1e9025ef700e450
```

**Passo 5:** Pressione
```
Shift + Enter
```

**Passo 6:** Veja o trace!

---

## ⚠️ Outras Causas do "400 Bad Request"

### 1. TraceID não existe

```bash
# Fazer uma requisição nova para criar um trace
curl http://localhost:3000/health

# Esperar alguns segundos
# Tentar com o novo traceId
```

### 2. TraceID com espaços extras

```
ERRADO:  c19f38865014477a1e9025ef700e450  (com espaço)
CORRETO: c19f38865014477a1e9025ef700e450 (sem espaço)
```

**Solução:** Copiar-colar com cuidado, sem seleção de mais nada

### 3. Datasource Jaeger não está conectado

```bash
# Verificar se Jaeger está acessível
curl http://localhost:16686/api/services

# Se falhar: verificar se Jaeger pod está rodando
kubectl get pods -n domestic | grep jaeger
```

### 4. TraceID inválido (caracteres errados)

```
VÁLIDO:   a1b2c3d4e5f6 (apenas 0-9, a-f)
INVÁLIDO: xyz12345     (caracteres não-hex)
```

---

## 🧪 Teste Rápido

### Teste 1: Gerar um novo TraceID

```bash
# Fazer requisição
curl http://localhost:3000/tracing/order/test-123

# Copiar TraceID do log
tail fullstack-monorepo/packages/backend/example/logs/example-*.log | head -1

# Copiar o primeiro campo [xxx]
# Remover os hífens manualmente se houver
# Colar no Grafana Explore
```

### Teste 2: Verificar via Jaeger UI Diretamente

```
http://jaeger.domestic.local
→ Service: example
→ Ver traces recentes
→ Clicar em um
→ Copiar TraceID
→ Tentar no Grafana
```

---

## 💡 Dica Profissional

**Crie um script para converter TraceIDs:**

```bash
#!/bin/bash
# remove_hyphens.sh
traceId=$1
echo "${traceId//-/}"
```

**Uso:**
```bash
./remove_hyphens.sh "c19f3886-5014-4778-a1e9-025ef700e450"
# Output: c19f38865014477a1e9025ef700e450
```

---

## ✅ Verificação Final

Se conseguir fazer isso sem erro:

1. ✅ Abrir Grafana Explore
2. ✅ Jaeger datasource
3. ✅ Colar TraceID (sem hífens)
4. ✅ Shift + Enter
5. ✅ Ver a timeline

**Então está funcionando!** 🎉

---

## 📞 Se Continuar com Erro

1. **Verificar logs do Grafana:**
   ```bash
   kubectl logs deployment/grafana -n domestic | grep -i error
   ```

2. **Verificar logs do Jaeger:**
   ```bash
   kubectl logs deployment/jaeger -n domestic | grep -i error
   ```

3. **Testar conectividade:**
   ```bash
   curl http://localhost:16686/api/services
   ```

4. **Reiniciar Grafana:**
   ```bash
   kubectl rollout restart deployment/grafana -n domestic
   ```

---

**Última atualização:** 2026-05-26
