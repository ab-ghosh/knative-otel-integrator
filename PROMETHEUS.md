# Prometheus Integration - Production Setup

This guide explains how to integrate your Knative controller metrics with Prometheus using **Prometheus Operator**.

## 📋 Prerequisites

- Prometheus Operator installed in your cluster
- `kubectl` access to your cluster

### Verify Prometheus Operator

```bash
# Check if Prometheus Operator is installed
kubectl get crd servicemonitors.monitoring.coreos.com

# Expected output:
# NAME                                    CREATED AT
# servicemonitors.monitoring.coreos.com   2024-01-XX...
```

If you don't see this, follow the installation steps below.

---

## 🛠️ Install Prometheus Operator

### 🧭 Option 1: Install via Helm (Recommended)

**Step 1: Add the Helm repository**

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
```

**Step 2: Create a namespace for monitoring**

```bash
kubectl create namespace monitoring
```

**Step 3: Install kube-prometheus-stack**

This chart includes:
- Prometheus Operator
- Prometheus
- Alertmanager
- Grafana
- Default alerting + recording rules

```bash
helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack -n monitoring
```

💡 You can also specify a values file:

```bash
helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack -n monitoring -f values.yaml
```

**Step 4: Verify installation**

```bash
kubectl get pods -n monitoring
```

You should see pods like:
```
NAME                                                     READY   STATUS
alertmanager-kube-prometheus-stack-alertmanager-0        2/2     Running
kube-prometheus-stack-grafana-xxx                        3/3     Running
kube-prometheus-stack-kube-state-metrics-xxx             1/1     Running
kube-prometheus-stack-operator-xxx                       1/1     Running
kube-prometheus-stack-prometheus-node-exporter-xxx       1/1     Running
prometheus-kube-prometheus-stack-prometheus-0            2/2     Running
```

**Step 5: Wait for Prometheus to be ready**

```bash
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=prometheus -n monitoring --timeout=300s
```

---

## 🚀 Setup (3 Steps)

### Step 1: Deploy Your Controller with Metrics

```bash
# Deploy everything including metrics configuration
ko apply -Rf config/ -n labeler
```

This deploys:
- Controller with metrics port (9090)
- `config-observability` ConfigMap
- `label-controller-metrics` Service
- **`servicemonitor.yaml`** ← Tells Prometheus to scrape

### Step 2: Verify ServiceMonitor

```bash
# Check ServiceMonitor was created
kubectl get servicemonitor -n labeler

# Expected output:
# NAME                 AGE
# labeler-controller   30s

# View details
kubectl describe servicemonitor labeler-controller -n labeler
```

### Step 3: Verify Prometheus is Scraping

```bash
# Port-forward to Prometheus UI
kubectl port-forward -n monitoring svc/prometheus-operated 9090:9090

# Open in browser
open http://localhost:9090

# Go to: Status → Targets
# Look for: labeler/labeler-controller
# Status should be: UP (green)
```

---

## 📊 Using the Metrics

### Access Prometheus

```bash
# Port-forward to Prometheus
kubectl port-forward -n monitoring svc/prometheus-operated 9090:9090

# Open UI
open http://localhost:9090
```

### Try These Queries

Go to **Graph** tab and enter:

**Current queue depth:**
```promql
kn_workqueue_depth{name="main.Reconciler"}
```

**Items processed per second (5min average):**
```promql
rate(kn_workqueue_adds_total{name="main.Reconciler"}[5m])
```

**95th percentile processing time:**
```promql
histogram_quantile(0.95, 
  rate(kn_workqueue_process_duration_seconds_bucket{name="main.Reconciler"}[5m])
)
```

**Memory usage (MB):**
```promql
go_memory_used_bytes / 1024 / 1024
```

**Active goroutines:**
```promql
go_goroutine_count
```

**K8s API requests by method:**
```promql
sum by (http_request_method) (
  rate(kn_k8s_client_http_response_status_code_total[5m])
)
```

---

## 🎨 Grafana Dashboard (Optional)

### Add Prometheus Data Source

1. Go to: **Configuration → Data Sources → Add data source**
2. Select: **Prometheus**
3. URL: `http://prometheus-operated.monitoring.svc.cluster.local:9090`
4. Click: **Save & Test**

### Create Dashboard Panels

**Panel 1: Queue Depth (Graph)**
```promql
kn_workqueue_depth{name="main.Reconciler"}
```

**Panel 2: Processing Rate (Graph)**
```promql
rate(kn_workqueue_adds_total{name="main.Reconciler"}[5m])
```

**Panel 3: Processing Duration p95 (Graph)**
```promql
histogram_quantile(0.95, 
  rate(kn_workqueue_process_duration_seconds_bucket{name="main.Reconciler"}[5m])
)
```

**Panel 4: Memory Usage (Graph)**
```promql
go_memory_used_bytes / 1024 / 1024
```

**Panel 5: Goroutines (Stat)**
```promql
go_goroutine_count
```

---

## ⚠️ Troubleshooting

### ServiceMonitor not discovered by Prometheus

**Problem**: Metrics queries return no data even though the ServiceMonitor exists.

**Cause**: Prometheus uses a label selector to discover ServiceMonitors. If your ServiceMonitor doesn't have the required label, Prometheus will ignore it.

**Solution**: Add the `release: kube-prometheus-stack` label to your ServiceMonitor:

```yaml
metadata:
  name: labeler-controller
  namespace: labeler
  labels:
    app: label-controller
    release: kube-prometheus-stack  # ← Required!
```

**Verify the required label:**

```bash
# Check what label selector Prometheus is using
kubectl get prometheus -n monitoring -o jsonpath='{.items[0].spec.serviceMonitorSelector}'

# Common selectors:
# {"matchLabels":{"release":"kube-prometheus-stack"}}
```

**After adding the label:**

```bash
# Apply the updated ServiceMonitor
kubectl apply -f config/servicemonitor.yaml

# Wait 30 seconds for Prometheus to reload
sleep 30

# Verify Prometheus discovered it
kubectl logs -n monitoring prometheus-kube-prometheus-stack-prometheus-0 -c prometheus | grep labeler
```

### ServiceMonitor not found

```bash
# Check if CRD exists
kubectl get crd servicemonitors.monitoring.coreos.com

# If missing, install Prometheus Operator:
# https://github.com/prometheus-operator/prometheus-operator#quickstart
```

### Target shows DOWN in Prometheus

```bash
# 1. Check if Service exists
kubectl get svc label-controller-metrics -n labeler

# 2. Check if pod is running
kubectl get pods -n labeler -l app=label-controller

# 3. Test metrics endpoint directly
kubectl port-forward -n labeler svc/label-controller-metrics 9090:9090
curl http://localhost:9090/metrics

# 4. Check ServiceMonitor matches Service
kubectl get svc label-controller-metrics -n labeler -o yaml | grep -A5 labels
kubectl get servicemonitor labeler-controller -n labeler -o yaml | grep -A5 selector
```

### No metrics appearing

```bash
# 1. Verify config-observability is correct
kubectl get cm config-observability -n labeler -o yaml

# Should have:
#   metrics-protocol: prometheus
#   metrics-endpoint: ":9090"

# 2. Check controller logs
kubectl logs -n labeler -l app=label-controller | grep -i observability

# 3. Restart controller if needed
kubectl rollout restart deployment/label-controller -n labeler
```

### Wrong namespace for Prometheus

If your Prometheus is in a different namespace:

```bash
# Find Prometheus namespace
kubectl get prometheus --all-namespaces

# Update port-forward command
kubectl port-forward -n YOUR_PROMETHEUS_NAMESPACE svc/prometheus-operated 9090:9090
```

---

## 🔧 Configuration

### ServiceMonitor Configuration

The `config/servicemonitor.yaml` file:

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: labeler-controller
  namespace: labeler
  labels:
    app: label-controller
    release: kube-prometheus-stack  # Required for Prometheus discovery!
spec:
  selector:
    matchLabels:
      app: label-controller  # Must match Service labels
  endpoints:
  - port: metrics            # Must match Service port name
    interval: 30s            # Scrape every 30 seconds
    path: /metrics           # Metrics endpoint path
    scheme: http             # Use HTTP (not HTTPS)
```

**Important**: The `release: kube-prometheus-stack` label is required for Prometheus to discover this ServiceMonitor. Without it, your metrics won't be scraped.

### Change Scrape Interval

Edit `config/servicemonitor.yaml`:

```yaml
spec:
  endpoints:
  - port: metrics
    interval: 15s  # Change from 30s to 15s
```

Then apply:
```bash
kubectl apply -f config/servicemonitor.yaml
```

### Add Custom Labels

Edit `config/servicemonitor.yaml`:

```yaml
spec:
  endpoints:
  - port: metrics
    interval: 30s
    relabelings:
    - targetLabel: environment
      replacement: production
    - targetLabel: team
      replacement: platform
```

---

## 📈 Monitoring Best Practices

### Set Up Alerts

Create a PrometheusRule for alerts:

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: labeler-alerts
  namespace: labeler
spec:
  groups:
  - name: labeler
    interval: 30s
    rules:
    - alert: HighQueueDepth
      expr: kn_workqueue_depth{name="main.Reconciler"} > 100
      for: 5m
      labels:
        severity: warning
      annotations:
        summary: "High work queue depth"
        description: "Queue depth is {{ $value }} items"
    
    - alert: HighProcessingLatency
      expr: |
        histogram_quantile(0.95, 
          rate(kn_workqueue_process_duration_seconds_bucket[5m])
        ) > 1
      for: 10m
      labels:
        severity: warning
      annotations:
        summary: "High processing latency"
        description: "95th percentile is {{ $value }}s"
```

Apply:
```bash
kubectl apply -f alerts.yaml
```

### Create Dashboards

Import or create Grafana dashboards with:
- Queue depth over time
- Processing rate trends
- Latency percentiles (p50, p95, p99)
- Memory usage trends
- K8s API call rates

---

## 📚 Available Metrics

### Workqueue Metrics (7 metrics)

| Metric | Type | Description |
|--------|------|-------------|
| `kn.workqueue.depth` | Gauge | Current queue depth |
| `kn.workqueue.adds` | Counter | Total items added |
| `kn.workqueue.queue.duration` | Histogram | Time waiting in queue |
| `kn.workqueue.process.duration` | Histogram | Processing time |
| `kn.workqueue.unfinished_work` | Gauge | Unfinished work duration |
| `kn.workqueue.longest_running_processor` | Gauge | Longest running item |
| `kn.workqueue.retries` | Counter | Retry count |

### Client-Go Metrics (2 metrics)

| Metric | Type | Description |
|--------|------|-------------|
| `kn.k8s.client.request.duration` | Histogram | K8s API request latency |
| `kn.k8s.client.request.count` | Counter | K8s API request count |

### Go Runtime Metrics (10+ metrics)

| Metric | Description |
|--------|-------------|
| `go.memory.used` | Memory used |
| `go.goroutine.count` | Goroutine count |
| `go.memory.allocated` | Heap allocations |
| And more... |

---

## ✅ Verification Checklist

- [ ] Prometheus Operator installed
- [ ] ServiceMonitor created (`kubectl get servicemonitor -n labeler`)
- [ ] Target shows UP in Prometheus UI
- [ ] Queries return data
- [ ] Grafana dashboard created (optional)
- [ ] Alerts configured (optional)

---

## 🎉 Done!

Your metrics are now being scraped by Prometheus!

**Next steps:**
1. Create Grafana dashboards
2. Set up alerting rules
3. Monitor your controller in production

**Need help?** Check the troubleshooting section above.

