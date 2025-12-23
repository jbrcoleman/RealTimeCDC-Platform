# Monitoring Stack

This directory contains Kubernetes manifests for the Prometheus and Grafana monitoring stack.

## Directory Structure

```
monitoring/
├── prometheus-stack-values.yaml       # Helm values for kube-prometheus-stack
├── cloudwatch-exporter-values.yaml    # Helm values for CloudWatch exporter
├── servicemonitors/                   # ServiceMonitor resources
│   ├── kafka.yaml                     # Kafka metrics collection
│   ├── kafka-connect.yaml             # Kafka Connect/Debezium metrics
│   ├── flink.yaml                     # Flink metrics collection
│   ├── consumers.yaml                 # Consumer app metrics
│   ├── argocd.yaml                    # ArgoCD metrics
│   └── kustomization.yaml             # Kustomize config
├── alerts/                            # Alert rules
│   └── cdc-platform-alerts.yaml       # All alert rules
└── dashboards/                        # Custom dashboards (add here)
```

## Components

### 1. Prometheus Stack (kube-prometheus-stack)
Deploys:
- Prometheus Operator
- Prometheus server with 100Gi storage
- Grafana with 10Gi storage
- Alertmanager with 10Gi storage
- Node Exporter (on all nodes)
- Kube State Metrics

### 2. CloudWatch Exporter
Collects metrics from AWS services:
- RDS (connections, CPU, storage, latency)
- DynamoDB (capacity, throttling, latency)
- S3 (bucket size, object count)
- EBS (volume metrics)

### 3. ServiceMonitors
Auto-discovery of metrics endpoints:
- **Kafka**: Broker metrics, topic metrics, consumer lag
- **Kafka Connect**: Connector status, task metrics, throughput
- **Flink**: Job metrics, checkpoint metrics, backpressure
- **Consumers**: Application metrics, processing metrics
- **ArgoCD**: Application health, sync status

### 4. Alert Rules
Pre-configured alerts for:
- Kafka broker failures, consumer lag, under-replicated partitions
- Debezium connector failures, high lag, task restarts
- Flink job failures, checkpoint issues, backpressure
- Consumer application failures, high lag, error rates
- RDS connection limits, CPU, storage
- Kubernetes pod crashes, node issues, PVC capacity

## Deployment

### Option 1: Automated (Recommended)
```bash
./scripts/deploy-monitoring.sh
```

### Option 2: Via Terraform
```bash
cd terraform-apps
terraform apply -target=helm_release.kube_prometheus_stack
terraform apply -target=helm_release.cloudwatch_exporter
cd ..
kubectl apply -k k8s/monitoring/servicemonitors/
kubectl apply -f k8s/monitoring/alerts/
```

### Option 3: Via ArgoCD (GitOps)
```bash
kubectl apply -f argocd/apps/monitoring.yaml
```

## Access

### Grafana
- **URL**: https://grafana.democloud.click
- **Username**: admin
- **Password**: Get with:
  ```bash
  kubectl get secret -n monitoring kube-prometheus-stack-grafana \
    -o jsonpath='{.data.admin-password}' | base64 -d
  ```

### Prometheus
- **URL**: https://prometheus.democloud.click
- **Port Forward**:
  ```bash
  kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090
  ```

### Alertmanager
- **Port Forward**:
  ```bash
  kubectl port-forward -n monitoring svc/kube-prometheus-stack-alertmanager 9093:9093
  ```

## Pre-Built Dashboards

After deployment, these dashboards are available in Grafana:

1. **Kubernetes Cluster** - Overall cluster health
2. **Node Exporter** - Detailed node metrics
3. **Kafka Overview** - Kafka cluster metrics
4. **Strimzi Kafka** - Strimzi-specific metrics
5. **Flink** - Flink job metrics

## Custom Dashboards

To add custom dashboards:

1. **Via Grafana UI**:
   - Create dashboard in Grafana
   - Export JSON
   - Save to `k8s/monitoring/dashboards/`
   - Create ConfigMap
   - Label with `grafana_dashboard: "1"`

2. **Via ConfigMap**:
   ```bash
   kubectl create configmap my-dashboard \
     --from-file=dashboard.json \
     -n monitoring
   kubectl label configmap my-dashboard grafana_dashboard=1 -n monitoring
   ```

## Alert Configuration

### Update Alert Rules
Edit and apply:
```bash
vim k8s/monitoring/alerts/cdc-platform-alerts.yaml
kubectl apply -f k8s/monitoring/alerts/cdc-platform-alerts.yaml
```

### Configure Slack Notifications
1. Get Slack webhook URL
2. Update `prometheus-stack-values.yaml`:
   ```yaml
   alertmanager:
     config:
       global:
         slack_api_url: 'YOUR_WEBHOOK_URL'
   ```
3. Reapply via Terraform

### Test Alerts
```bash
# View active alerts in Prometheus
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090
# Open http://localhost:9090/alerts

# View Alertmanager
kubectl port-forward -n monitoring svc/kube-prometheus-stack-alertmanager 9093:9093
# Open http://localhost:9093
```

## Metrics Endpoints

Components expose metrics on these ports:

| Component | Port | Path |
|-----------|------|------|
| Kafka Brokers | 9404 | /metrics |
| Kafka Connect | 9404 | /metrics |
| Flink JobManager | 9249 | /metrics |
| Flink TaskManager | 9249 | /metrics |
| Consumer Apps | 8080 | /metrics |
| ArgoCD | 8083 | /metrics |

## Verification

### Check All Components
```bash
# Pods
kubectl get pods -n monitoring

# ServiceMonitors
kubectl get servicemonitor -A

# PrometheusRules
kubectl get prometheusrule -n monitoring

# Prometheus targets (should all be UP)
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090
# Open http://localhost:9090/targets
```

### Query Metrics
```bash
# Port forward Prometheus
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090

# Test queries
curl 'http://localhost:9090/api/v1/query?query=up'
curl 'http://localhost:9090/api/v1/query?query=kafka_server_replicamanager_leadercount'
```

## Troubleshooting

### Prometheus Not Scraping

1. **Check ServiceMonitor**:
   ```bash
   kubectl get servicemonitor <name> -n <namespace> -o yaml
   ```

2. **Check Service exists**:
   ```bash
   kubectl get svc -n <namespace>
   ```

3. **Test metrics endpoint**:
   ```bash
   kubectl port-forward -n <namespace> <pod> <port>:<port>
   curl http://localhost:<port>/metrics
   ```

### Grafana Not Showing Data

1. **Test Prometheus connection**:
   - Grafana UI → Configuration → Data Sources → Prometheus → Test

2. **Check Prometheus has data**:
   ```bash
   kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090
   curl 'http://localhost:9090/api/v1/query?query=up'
   ```

### High Memory Usage

1. **Check cardinality**:
   - Prometheus UI → Status → TSDB Status

2. **Reduce retention**:
   - Edit `prometheus-stack-values.yaml`
   - Set `retention: 7d` (instead of 15d)
   - Reapply via Terraform

3. **Add recording rules** for frequently queried metrics

## Performance Tips

1. **Adjust scrape intervals** for less critical metrics (60s instead of 30s)
2. **Use recording rules** for complex queries used in dashboards
3. **Enable remote write** for long-term storage (Thanos/Cortex)
4. **Monitor Prometheus memory** and adjust retention/storage accordingly

## Resources

- **Full Documentation**: `/MONITORING_PLAN.md`
- **Quick Start**: `/MONITORING_QUICKSTART.md`
- **Prometheus Docs**: https://prometheus.io/docs/
- **Grafana Docs**: https://grafana.com/docs/
- **kube-prometheus-stack**: https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack
