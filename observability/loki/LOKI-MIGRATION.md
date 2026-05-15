# Migração: Deployment → StatefulSet com PVC

## Problema
O Deployment original usa `emptyDir: {}`, o que significa:
- **Logs são perdidos ao reiniciar Loki**
- **Logs de falhas de startup não estão disponíveis após o ambiente cair**
- Impossível fazer debugging de inicializações falhadas

## Solução
Usar **StatefulSet com PersistentVolumeClaim (PVC)** para persistir logs em disco.

## Como Migrar

### 1. Fazer backup dos logs atuais (se necessário)
```bash
kubectl logs -n domestic deployment/loki > loki-logs-backup.txt
```

### 2. Deletar o Deployment antigo
```bash
kubectl delete deployment loki -n domestic
```

### 3. Aplicar o novo StatefulSet
```bash
kubectl apply -f loki.statefulset.yaml
```

### 4. Verificar criação do PVC e pod
```bash
kubectl get pvc -n domestic
kubectl get statefulset -n domestic
kubectl get pods -n domestic -l app=loki
```

## Benefícios
✅ Logs persistem entre restarts
✅ Disponíveis após falhas de inicialização
✅ Melhor debugging de problemas
✅ Histórico completo no Grafana

## Armazenamento
- **PVC Size**: 10Gi (ajustável)
- **StorageClass**: `local-path` (padrão minikube/k3s)
- Para produção, considere aumentar para 50Gi+ e usar storage class com replicação

## Monitoramento
```bash
# Ver uso do PVC
kubectl exec -it loki-0 -n domestic -- df -h /loki

# Aumentar tamanho (editar PVC)
kubectl patch pvc loki-data -n domestic -p '{"spec":{"resources":{"requests":{"storage":"20Gi"}}}}'
```

## Rollback (se necessário)
```bash
kubectl delete statefulset loki -n domestic
kubectl apply -f loki.deployment.yaml
```
