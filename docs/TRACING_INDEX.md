# 📚 Tracing Documentation Index

Guia completo de tracing distribuído no projeto Domestic. Escolha o documento que melhor se adequa ao seu caso de uso.

---

## 🚀 Quick Start (5 minutos)

**Para quem quer começar AGORA:**

📄 **[TRACES_QUICKSTART.md](TRACES_QUICKSTART.md)**
- Deploy do dashboard em 3 passos
- Visualizar traces imediatamente
- Troubleshooting básico

**Leia este primeiro!**

---

## 🔍 Usando o Jaeger Explorer

**Para buscar e visualizar traces específicos:**

📄 **[JAEGER_EXPLORE_GUIDE.md](JAEGER_EXPLORE_GUIDE.md)**

### Contém:
- ✅ Como abrir o Explore no Grafana
- ✅ Como colar um TraceID e ver o trace
- ✅ Como obter TraceIDs de logs/responses
- ✅ Como interpretar a visualização
- ✅ Casos de uso práticos (latência, erros, fluxos)
- ✅ Troubleshooting específico

**Use quando:** Quiser debugar uma requisição específica

---

## 📊 Grafana Dashboards de Tracing

**Para monitoramento em tempo real:**

📄 **[TRACES_QUICKSTART.md](TRACES_QUICKSTART.md)** → Seção "Deploy"

### Painéis disponíveis:
```
Traces - Search by TraceID (uid: traces-simple)
├── Recent Traces (API)
├── Recent Traces (Example)
├── Service Health
├── Span Rate
├── Error Rate
└── Latency P95
```

**Use quando:** Quiser ver a saúde dos serviços em tempo real

---

## 📋 Explorando Logs (Loki)

**Para buscar logs e correlacionar com traces:**

📄 **[LOKI_EXPLORE_GUIDE.md](LOKI_EXPLORE_GUIDE.md)**

### Contém:
- ✅ Como abrir o Explore no Grafana com Loki
- ✅ Como buscar logs por TraceID
- ✅ Sintaxe de queries do Loki
- ✅ Extração e filtragem de dados
- ✅ Correlação automática logs ↔ traces
- ✅ Casos de uso práticos
- ✅ Troubleshooting

**Use quando:** Quiser visualizar logs de uma requisição específica

---

## 🎓 Documentação Completa

**Para entender tudo em profundidade:**

📄 **[TRACING_GUIDE.md](TRACING_GUIDE.md)**

### Contém:
- ✅ Visão geral da arquitetura de tracing
- ✅ Fluxo de dados (OpenTelemetry → Jaeger → Grafana)
- ✅ Acessar Jaeger UI
- ✅ Acessar Grafana
- ✅ Formatos de TraceID
- ✅ Visualizando traces
- ✅ Monitorando em produção
- ✅ Configuração de amostragem (sampling)
- ✅ Armazenamento de dados
- ✅ Troubleshooting detalhado

**Use quando:** Quiser entender toda a stack

---

## 🔧 Scripts e Ferramentas

### trace-test.sh

**Script interativo para testar tracing:**

```bash
./domestic-kubernets/scripts/trace-test.sh
```

**Menu:**
```
1) Testar Example App (/tracing/order/*)
2) Testar API Health (/health)
3) Testar BFF (/bff/health)
4) Testar Correlação Logs ↔ Traces
5) Abrir Jaeger UI
6) Abrir Grafana Dashboard
```

---

## 🗺️ Mapa de Navegação

### "Quero..."

#### ...começar agora em 5 minutos
→ [TRACES_QUICKSTART.md](TRACES_QUICKSTART.md)

#### ...debugar uma requisição lenta
→ [JAEGER_EXPLORE_GUIDE.md](JAEGER_EXPLORE_GUIDE.md) → Caso 1 (Timeline visual)
→ [LOKI_EXPLORE_GUIDE.md](LOKI_EXPLORE_GUIDE.md) → Caso 1 (Logs detalhados)

#### ...investigar um erro
→ [JAEGER_EXPLORE_GUIDE.md](JAEGER_EXPLORE_GUIDE.md) → Caso 2 (Span de erro)
→ [LOKI_EXPLORE_GUIDE.md](LOKI_EXPLORE_GUIDE.md) → Caso 2 (Mensagens de erro)

#### ...entender fluxos entre serviços
→ [JAEGER_EXPLORE_GUIDE.md](JAEGER_EXPLORE_GUIDE.md) → Caso 3

#### ...monitorar performance em produção
→ [TRACING_GUIDE.md](TRACING_GUIDE.md) → Monitorando em Produção

#### ...configurar alertas
→ [TRACING_GUIDE.md](TRACING_GUIDE.md) → Métricas importantes

#### ...entender toda a arquitetura
→ [TRACING_GUIDE.md](TRACING_GUIDE.md) → Seção completa

---

## 📍 URLs Úteis

| Serviço | URL |
|---------|-----|
| **Grafana (Traces)** | http://grafana.domestic.local/d/traces-simple |
| **Grafana Explore** | http://grafana.domestic.local/explore |
| **Jaeger UI** | http://jaeger.domestic.local |
| **Prometheus** | http://prometheus.domestic.local:9090 |
| **Loki** | http://loki.domestic.local:3100 |

---

## 🎬 Workflow Típico

### 1. Deploy (primeira vez)
```bash
kubectl apply -f observability/grafana/grafana-dashboard-traces-simple.configmap.yaml
kubectl apply -f observability/grafana/grafana.deployment.yaml
```

### 2. Gerar um Trace
```bash
curl http://localhost:3000/tracing/order/test-123
```

### 3. Visualizar
```
→ Grafana: http://grafana.domestic.local/d/traces-simple
→ Jaeger: http://jaeger.domestic.local
```

### 4. Debugar
```
→ Copiar TraceID do log
→ Grafana Explore → Jaeger → Trace ID → Colar e executar
```

---

## 🔧 Common Issues & Fixes

### "request failed: 400 Bad Request" (TraceID)

📄 **[JAEGER_TRACEID_FORMAT_FIX.md](JAEGER_TRACEID_FORMAT_FIX.md)**

**Problema:** TraceID com hífens não funciona  
**Solução:** Remover os hífens antes de colar

**Exemplos:**
```
❌ c19f3886-5014-4778-a1e9-025ef700e450  (não funciona)
✅ c19f38865014477a1e9025ef700e450      (funciona)
```

---

## 🆘 Troubleshooting Rápido

### "Nenhum trace aparece"

1. Verificar se `initTracing()` foi chamado
   ```bash
   kubectl logs deployment/api -n domestic | grep "OpenTelemetry"
   ```

2. Verificar se Jaeger está recebendo dados
   ```bash
   curl http://localhost:16686/api/services
   ```

3. Fazer uma nova requisição
   ```bash
   curl http://localhost:3000/health
   ```

### "TraceID não encontrado"

1. Verificar formato (deve ter 12 ou 32 caracteres hex)
2. Verificar se não é muito antigo (retenção padrão: 72h)
3. Gerar um novo trace e copiar imediatamente

---

## 📋 Checklist de Setup

- [ ] Deploy do dashboard: `kubectl apply -f grafana-dashboard-traces-simple.configmap.yaml`
- [ ] Deploy do Grafana: `kubectl apply -f grafana.deployment.yaml`
- [ ] Aguardar 30 segundos
- [ ] Testar: `curl http://localhost:3000/health`
- [ ] Verificar Jaeger: `http://localhost:16686/api/services`
- [ ] Abrir Grafana Traces: `http://grafana.domestic.local/d/traces-simple`
- [ ] Copiar um TraceID e testar no Explore

---

## 📞 Contato & Suporte

Se encontrar problemas:

1. Consulte [JAEGER_EXPLORE_GUIDE.md](JAEGER_EXPLORE_GUIDE.md) → Troubleshooting
2. Consulte [TRACING_GUIDE.md](TRACING_GUIDE.md) → Troubleshooting
3. Execute `./trace-test.sh` para diagnóstico automático

---

## 📚 Recursos Externos

- [OpenTelemetry Documentation](https://opentelemetry.io/docs/)
- [Jaeger Official Docs](https://www.jaegertracing.io/docs/)
- [Grafana Tempo](https://grafana.com/docs/tempo/)
- [Grafana Explore](https://grafana.com/docs/grafana/latest/explore/)

---

**Última atualização:** 2026-05-26
