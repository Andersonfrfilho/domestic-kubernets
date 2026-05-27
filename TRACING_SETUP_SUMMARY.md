# 🎯 Tracing Setup Complete - Summary

## ✅ What Was Configured

### 1. **OpenTelemetry Integration**
- ✅ All 5 services calling `initTracing()`
  - api (`domestic-backend-api`)
  - bff (`domestic-backend-bff`)
  - worker (`domestic-backend-worker`)
  - cron (`domestic-backend-cron`)
  - example (`fullstack-monorepo/packages/backend/example`)

- ✅ Sending traces to Jaeger via OTLP HTTP (port 4318)

### 2. **Grafana Dashboards**
- ✅ **Traces Dashboard** (uid: `traces-simple`)
  - Recent traces from each service
  - Service health monitoring
  - Span rate & error rate
  - Latency percentiles

### 3. **Data Correlation**
- ✅ **Logs** (Loki) ← sync → **Traces** (Jaeger)
- ✅ Click log → see trace
- ✅ Click trace → see logs

### 4. **Documentation**
- ✅ Quick Start Guide
- ✅ Jaeger Explorer Guide
- ✅ Loki Explorer Guide
- ✅ Complete Tracing Guide
- ✅ Testing Script

---

## 🚀 Next Steps

### Step 1: Deploy (if not already)

```bash
# Deploy new dashboard
kubectl apply -f domestic-kubernets/observability/grafana/grafana-dashboard-traces-simple.configmap.yaml

# Update Grafana deployment
kubectl apply -f domestic-kubernets/observability/grafana/grafana.deployment.yaml

# Wait for rollout
sleep 30
```

### Step 2: Verify

```bash
# Check Jaeger has data
curl http://localhost:16686/api/services

# Expected output:
# {"data":["api","bff","example","worker","cron"]}

# If empty: kubectl logs deployment/api -n domestic | grep "OpenTelemetry initialized"
```

### Step 3: Generate a Trace

```bash
# Test request
curl http://localhost:3000/tracing/order/test-$(date +%s)

# Check logs
tail fullstack-monorepo/packages/backend/example/logs/example-*.log | head -1

# Copy the requestId (first field in brackets)
```

### Step 4: Visualize

**Option A: Grafana Dashboard**
```
http://grafana.domestic.local/d/traces-simple
→ See all recent traces
```

**Option B: Jaeger Explore**
```
http://grafana.domestic.local/explore
→ Data source: Jaeger
→ Query type: Trace ID
→ Paste traceId
→ Shift + Enter
```

**Option C: Loki Explorer**
```
http://grafana.domestic.local/explore
→ Data source: Loki
→ Query: {job="domestic"} | json | trace_id="<paste-id>"
→ Shift + Enter
```

---

## 📊 Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                        Your Application                      │
├─────────────────────────────────────────────────────────────┤
│  api (3000) │ bff (3001) │ worker (3002) │ cron (3003)      │
│          + example (3000 dev)                                │
│          All calling: initTracing()                          │
└────────────────┬────────────────────────────────────────────┘
                 │
         OpenTelemetry SDK
         (NodeSDK + OTLPTraceExporter)
                 │
                 ├──→ OTLP Endpoint (port 4318)
                 │
    ┌────────────v────────────────────┐
    │    Jaeger All-in-One            │
    │  (Collector + Storage + UI)      │
    │         (port 16686)             │
    └────────────┬─────────────────────┘
                 │
    ┌────────────v─────────────────┐
    │      Prometheus Metrics       │
    │  (for span rate, latency)     │
    └────────────┬─────────────────┘
                 │
    ┌────────────v─────────────────┐
    │         Loki Logs             │
    │   (structured log storage)    │
    └────────────┬─────────────────┘
                 │
    ┌────────────v──────────────────────────────┐
    │          Grafana (port 3000)              │
    ├───────────────────────────────────────────┤
    │ Dashboard: Traces (uid: traces-simple)    │
    │ Explore: Jaeger (trace search)            │
    │ Explore: Loki (log search)                │
    │ Explore: Prometheus (metrics)             │
    └───────────────────────────────────────────┘
```

---

## 📚 Documentation Quick Links

| Document | Purpose | Read Time |
|----------|---------|-----------|
| [TRACES_QUICKSTART.md](docs/TRACES_QUICKSTART.md) | Get running in 5 min | 5 min |
| [JAEGER_EXPLORE_GUIDE.md](docs/JAEGER_EXPLORE_GUIDE.md) | Debug specific traces | 15 min |
| [LOKI_EXPLORE_GUIDE.md](docs/LOKI_EXPLORE_GUIDE.md) | Search & filter logs | 15 min |
| [TRACING_GUIDE.md](docs/TRACING_GUIDE.md) | Complete reference | 30 min |
| [TRACING_INDEX.md](docs/TRACING_INDEX.md) | Navigation & index | 10 min |

---

## 🎯 Common Tasks

### "I want to debug a slow request"

```bash
# 1. Make the request
curl http://localhost:3000/users?page=1

# 2. Copy traceId from logs
tail fullstack-monorepo/packages/backend/example/logs/example-*.log | grep -o '\[.*\]' | head -1

# 3. Open Grafana Explore
http://grafana.domestic.local/explore
→ Jaeger → Trace ID → Paste → Shift+Enter

# 4. See timeline showing which operation is slow
```

### "I want to see all logs for a request"

```bash
# 1. Get traceId from logs
# [a1b2c3d4-...]...

# 2. Open Grafana Explore
http://grafana.domestic.local/explore
→ Loki → {job="domestic"} | json | trace_id="a1b2c3d4"
→ Shift+Enter

# 3. See all logs in chronological order
```

### "I want to monitor service health"

```bash
# 1. Open Grafana Dashboard
http://grafana.domestic.local/d/traces-simple

# 2. See real-time metrics:
# - Service Health (how many services report)
# - Span Rate (traces per second)
# - Error Rate (% errors)
# - Latency P95 (95th percentile latency)
```

### "I want to find all errors in the last hour"

```bash
# 1. Open Grafana Explore → Loki
# 2. Query: {job="domestic"} | json | level="ERROR"
# 3. Shift+Enter

# 4. Click on any error to see the full trace context
```

---

## ✨ Key Features

✅ **Distributed Tracing**
- Trace requests across all services
- See service dependencies
- Identify bottlenecks

✅ **Correlation**
- Logs linked to traces
- Single source of truth for debugging
- Click between views seamlessly

✅ **Real-time Monitoring**
- Live dashboard of service health
- Error rates & latency
- Span throughput

✅ **Deep Debugging**
- Timeline visualization
- Service dependencies
- Span details & timings

---

## 🔧 Configuration

### Default Settings

| Setting | Value | Notes |
|---------|-------|-------|
| OTLP Endpoint | `http://jaeger:4318` | HTTP, not gRPC |
| Trace Sampler | `parentbased_always_on` | 100% sampling (all traces) |
| ID Format | `short-hash` | Like git short hash: `a1b2c3d4` |
| Log Retention | 72 hours | In Jaeger storage |
| Service Name | From package.json | Auto-detected |

### Customize (via env vars)

```bash
# Change endpoint (for different Jaeger)
export OTEL_EXPORTER_OTLP_ENDPOINT=http://my-jaeger:4318

# Change sampler to 10% sampling
export OTEL_TRACES_SAMPLER=parentbased_traceidratio
export OTEL_TRACES_SAMPLER_ARG=0.1

# Change ID format to full UUID
export OTEL_ID_FORMAT=full-hash
```

---

## ✅ Verification Checklist

- [ ] All 5 services show in Jaeger UI
  ```bash
  curl http://localhost:16686/api/services
  ```

- [ ] Grafana dashboard loads
  ```
  http://grafana.domestic.local/d/traces-simple
  ```

- [ ] Can see recent traces
  - API panel shows traces
  - Example panel shows traces

- [ ] Trace search works in Explore
  - Jaeger Explore → paste traceId → see timeline

- [ ] Log correlation works
  - Loki Explore → search by traceId → see logs

- [ ] Metrics display
  - Service Health shows 5 services
  - Span Rate > 0
  - Error Rate visible

---

## 🐛 Quick Troubleshooting

| Issue | Check | Fix |
|-------|-------|-----|
| No traces in Jaeger | `curl http://localhost:16686/api/services` | Make a request: `curl http://localhost:3000/health` |
| Empty dashboard | Wait 30 sec after deploy | Reload Grafana page |
| TraceID not found | Format: 12 or 32 hex chars | Copy full ID without spaces |
| Logs not showing | Check Loki is running | `kubectl get pods -n domestic \| grep loki` |
| Wrong timestamp | Set browser timezone | Grafana → Settings → Timezone |

---

## 📞 Support

### If something breaks

1. **Check logs**
   ```bash
   kubectl logs deployment/api -n domestic | grep -i "otel\|tracing\|jaeger"
   ```

2. **Check connectivity**
   ```bash
   kubectl exec -it deployment/api -n domestic -- curl http://jaeger:16686/api/services
   ```

3. **Restart services**
   ```bash
   kubectl rollout restart deployment/api -n domestic
   ```

4. **Check storage**
   ```bash
   kubectl exec -it jaeger-0 -n domestic -- ls /jaeger/data
   ```

---

## 🎓 Learn More

- [OpenTelemetry.io](https://opentelemetry.io/)
- [Jaeger Documentation](https://www.jaegertracing.io/docs/)
- [Grafana Explore](https://grafana.com/docs/grafana/latest/explore/)
- [Loki Query Language](https://grafana.com/docs/loki/latest/logql/)

---

## 📝 Files Created/Modified

### New Files
```
docs/
├── TRACING_INDEX.md              (navigation)
├── TRACES_QUICKSTART.md          (5-min setup)
├── JAEGER_EXPLORE_GUIDE.md       (trace search)
├── LOKI_EXPLORE_GUIDE.md         (log search)
├── TRACING_GUIDE.md              (complete reference)
└── (this file)

scripts/
└── trace-test.sh                 (interactive testing)

observability/grafana/
└── grafana-dashboard-traces-simple.configmap.yaml
```

### Modified Files
```
fullstack-monorepo/packages/backend/example/
├── src/main.ts                   (import instrumentation)
└── src/instrumentation.ts        (new: initTracing)

observability/grafana/
└── grafana.deployment.yaml       (added dashboard volume)
```

---

**✅ Tracing is now fully configured and ready to use!**

Start debugging: → [TRACES_QUICKSTART.md](docs/TRACES_QUICKSTART.md)

**Last updated:** 2026-05-26
