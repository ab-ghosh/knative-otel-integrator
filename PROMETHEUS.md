# Prometheus Integration - Advanced Reference

> **📖 For complete installation instructions, see the main [README.md](README.md)**

This document provides advanced configuration options and troubleshooting details for Prometheus integration.

## Quick Reference

The controller exposes Prometheus metrics on port 9090. If you've followed the installation guide in the README, your metrics are already being scraped by Prometheus.

### How to View Available Metrics

To see all metrics that your controller is currently exposing:

```bash
# Port-forward to the metrics service
kubectl port-forward -n labeler svc/label-controller-metrics 9090:9090

# In another terminal, view all metrics
curl http://localhost:9090/metrics

# Filter for specific metric types
curl http://localhost:9090/metrics | grep kn_workqueue
curl http://localhost:9090/metrics | grep kn_k8s_client
curl http://localhost:9090/metrics | grep go_
```

**Example output:**
```
# HELP kn_workqueue_depth Current depth of workqueue
# TYPE kn_workqueue_depth gauge
kn_workqueue_depth{name="main.Reconciler"} 0

# HELP kn_workqueue_adds_total Total number of adds handled by workqueue
# TYPE kn_workqueue_adds_total counter
kn_workqueue_adds_total{name="main.Reconciler"} 15
```

### Access Prometheus

```bash
kubectl port-forward -n monitoring svc/prometheus-operated 9090:9090
open http://localhost:9090
```

### Verify Scraping

1. Go to: **Status → Targets**
2. Look for: `labeler/labeler-controller`
3. Status should be: **UP** (green)

---

## Advanced Configuration

### ServiceMonitor Configuration

The `config/servicemonitor.yaml` file tells Prometheus where to scrape metrics:

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

### Add Custom Labels to Metrics

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

## Troubleshooting

### ServiceMonitor not discovered by Prometheus

**Problem**: Metrics queries return no data even though the ServiceMonitor exists.

**Solution**: Ensure your ServiceMonitor has the correct label. Check what label Prometheus expects:

```bash
kubectl get prometheus -n monitoring -o jsonpath='{.items[0].spec.serviceMonitorSelector}'
```

If it returns `{"matchLabels":{"release":"kube-prometheus-stack"}}`, ensure your ServiceMonitor has `release: kube-prometheus-stack` label (already included in `config/servicemonitor.yaml`).

### Target shows DOWN in Prometheus

```bash
# 1. Check if Service exists
kubectl get svc label-controller-metrics -n labeler

# 2. Check if pod is running
kubectl get pods -n labeler -l app=label-controller

# 3. Test metrics endpoint directly
kubectl port-forward -n labeler svc/label-controller-metrics 9090:9090
curl http://localhost:9090/metrics

# 4. Check ServiceMonitor matches Service labels
kubectl get svc label-controller-metrics -n labeler -o yaml | grep -A5 labels
kubectl get servicemonitor labeler-controller -n labeler -o yaml | grep -A5 selector
```

### No metrics appearing in Prometheus

```bash
# Verify config-observability ConfigMap
kubectl get cm config-observability -n labeler -o yaml

# Should contain:
#   metrics-protocol: prometheus
#   metrics-endpoint: ":9090"

# Check controller logs
kubectl logs -n labeler -l app=label-controller | grep -i observability

# Restart controller if needed
kubectl rollout restart deployment/label-controller -n labeler
```

### Different Prometheus namespace

If your Prometheus is in a different namespace:

```bash
# Find Prometheus namespace
kubectl get prometheus --all-namespaces

# Update port-forward commands accordingly
kubectl port-forward -n YOUR_NAMESPACE svc/prometheus-operated 9090:9090
```

---

## Prometheus Query Examples

Access Prometheus UI:
```bash
kubectl port-forward -n monitoring svc/prometheus-operated 9090:9090
open http://localhost:9090
```

### Workqueue Queries

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

**Queue duration p99:**
```promql
histogram_quantile(0.99, 
  rate(kn_workqueue_queue_duration_seconds_bucket{name="main.Reconciler"}[5m])
)
```

**Total retries:**
```promql
kn_workqueue_retries_total{name="main.Reconciler"}
```

### Go Runtime Queries

**Memory usage (MB):**
```promql
go_memory_used_bytes / 1024 / 1024
```

**Active goroutines:**
```promql
go_goroutine_count
```

**Heap allocations:**
```promql
go_memory_allocated_bytes
```

### Kubernetes Client Queries

**K8s API requests by method:**
```promql
sum by (http_request_method) (
  rate(kn_k8s_client_http_response_status_code_total[5m])
)
```

**K8s API latency p95:**
```promql
histogram_quantile(0.95,
  rate(kn_k8s_client_http_request_duration_seconds_bucket[5m])
)
```

**K8s API errors:**
```promql
sum(rate(kn_k8s_client_http_response_status_code_total{code=~"5.."}[5m]))
```

---

## Grafana Dashboard Setup

If you installed kube-prometheus-stack, Grafana is available:

```bash
# Get Grafana admin password
kubectl get secret -n monitoring kube-prometheus-stack-grafana -o jsonpath="{.data.admin-password}" | base64 --decode ; echo

# Port-forward to Grafana
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80

# Open Grafana (username: admin, password from above command)
open http://localhost:3000
```

### Add Prometheus Data Source

1. Go to: **Configuration → Data Sources → Add data source**
2. Select: **Prometheus**
3. URL: `http://prometheus-operated.monitoring.svc.cluster.local:9090`
4. Click: **Save & Test**

### Dashboard Panel Examples

**Panel 1: Queue Depth (Time Series)**
```promql
kn_workqueue_depth{name="main.Reconciler"}
```

**Panel 2: Processing Rate (Time Series)**
```promql
rate(kn_workqueue_adds_total{name="main.Reconciler"}[5m])
```

**Panel 3: Processing Latency Percentiles (Time Series)**
```promql
# p50
histogram_quantile(0.50, rate(kn_workqueue_process_duration_seconds_bucket{name="main.Reconciler"}[5m]))
# p95
histogram_quantile(0.95, rate(kn_workqueue_process_duration_seconds_bucket{name="main.Reconciler"}[5m]))
# p99
histogram_quantile(0.99, rate(kn_workqueue_process_duration_seconds_bucket{name="main.Reconciler"}[5m]))
```

**Panel 4: Memory Usage (Time Series)**
```promql
go_memory_used_bytes / 1024 / 1024
```

**Panel 5: Goroutines (Stat/Gauge)**
```promql
go_goroutine_count
```

**Panel 6: K8s API Request Rate (Time Series)**
```promql
sum by (http_request_method) (
  rate(kn_k8s_client_http_response_status_code_total[5m])
)
```

---

## Alerting Configuration

### Create PrometheusRule

Create alerts for production monitoring:

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: labeler-alerts
  namespace: labeler
  labels:
    app: label-controller
    release: kube-prometheus-stack  # Required for discovery
spec:
  groups:
  - name: labeler-controller
    interval: 30s
    rules:
    # Alert when queue depth is high
    - alert: LabelerHighQueueDepth
      expr: kn_workqueue_depth{name="main.Reconciler"} > 100
      for: 5m
      labels:
        severity: warning
        component: labeler-controller
      annotations:
        summary: "Labeler controller queue depth is high"
        description: "Queue depth is {{ $value }} items (threshold: 100)"
    
    # Alert when processing latency is high
    - alert: LabelerHighProcessingLatency
      expr: |
        histogram_quantile(0.95, 
          rate(kn_workqueue_process_duration_seconds_bucket{name="main.Reconciler"}[5m])
        ) > 1
      for: 10m
      labels:
        severity: warning
        component: labeler-controller
      annotations:
        summary: "Labeler controller processing latency is high"
        description: "95th percentile processing time is {{ $value }}s (threshold: 1s)"
    
    # Alert when controller has high retry rate
    - alert: LabelerHighRetryRate
      expr: rate(kn_workqueue_retries_total{name="main.Reconciler"}[5m]) > 0.1
      for: 5m
      labels:
        severity: warning
        component: labeler-controller
      annotations:
        summary: "Labeler controller has high retry rate"
        description: "Retry rate is {{ $value }} retries/sec (threshold: 0.1/sec)"
    
    # Alert when memory usage is high
    - alert: LabelerHighMemoryUsage
      expr: go_memory_used_bytes / 1024 / 1024 > 512
      for: 10m
      labels:
        severity: warning
        component: labeler-controller
      annotations:
        summary: "Labeler controller memory usage is high"
        description: "Memory usage is {{ $value }}MB (threshold: 512MB)"
```

Apply:
```bash
kubectl apply -f labeler-alerts.yaml
```

Verify alerts are loaded:
```bash
kubectl get prometheusrule -n labeler
```

---

## Available Metrics Reference

### Workqueue Metrics (7 metrics)

| Metric | Type | Labels | Description |
|--------|------|--------|-------------|
| `kn_workqueue_depth` | Gauge | `name` | Current number of items in the work queue |
| `kn_workqueue_adds_total` | Counter | `name` | Total number of items added to the queue |
| `kn_workqueue_queue_duration_seconds` | Histogram | `name` | Time items spend waiting in queue before processing |
| `kn_workqueue_process_duration_seconds` | Histogram | `name` | Time spent processing items |
| `kn_workqueue_unfinished_work_seconds` | Gauge | `name` | How long unfinished work has been in progress |
| `kn_workqueue_longest_running_processor_seconds` | Gauge | `name` | Duration of the longest running processor |
| `kn_workqueue_retries_total` | Counter | `name` | Total number of retries |

### Kubernetes Client Metrics (2 metrics)

| Metric | Type | Labels | Description |
|--------|------|--------|-------------|
| `kn_k8s_client_http_request_duration_seconds` | Histogram | `host`, `http_request_method` | K8s API request latency |
| `kn_k8s_client_http_response_status_code_total` | Counter | `host`, `http_request_method`, `code` | K8s API request count by status code |

### Go Runtime Metrics (10+ metrics)

| Metric | Description |
|--------|-------------|
| `go_memory_used_bytes` | Total memory used |
| `go_goroutine_count` | Number of active goroutines |
| `go_memory_allocated_bytes` | Total bytes allocated on the heap |
| `go_gc_duration_seconds` | GC pause duration |
| `go_threads` | Number of OS threads |
| And more standard Go runtime metrics... |

---

## Best Practices

### 1. Set Up Alerts

Always configure alerts for:
- High queue depth (indicates controller is falling behind)
- High processing latency (indicates performance issues)
- High retry rate (indicates reconciliation failures)
- High memory usage (indicates potential memory leaks)

### 2. Create Dashboards

Build Grafana dashboards to visualize:
- Queue depth trends over time
- Processing rate and latency
- Memory and CPU usage
- K8s API call patterns

### 3. Monitor Resource Usage

Track Go runtime metrics:
- Memory usage trends
- Goroutine count (should be stable)
- GC frequency and duration

### 4. Set Appropriate Scrape Intervals

Balance between data granularity and storage:
- 15-30s for production environments
- 5-10s for debugging/troubleshooting
- 1m for long-term storage

### 5. Configure Recording Rules

Pre-compute expensive queries:

```yaml
spec:
  groups:
  - name: labeler-recording-rules
    interval: 30s
    rules:
    - record: labeler:queue_processing_rate:5m
      expr: rate(kn_workqueue_adds_total{name="main.Reconciler"}[5m])
    
    - record: labeler:processing_latency:p95:5m
      expr: |
        histogram_quantile(0.95,
          rate(kn_workqueue_process_duration_seconds_bucket{name="main.Reconciler"}[5m])
        )
```

---

## Additional Resources

- [Prometheus Operator Documentation](https://prometheus-operator.dev/)
- [Prometheus Query Language (PromQL)](https://prometheus.io/docs/prometheus/latest/querying/basics/)
- [Grafana Dashboards](https://grafana.com/docs/grafana/latest/dashboards/)
- [Knative Metrics](https://knative.dev/docs/serving/observability/metrics/)

---

## Need Help?

For installation issues, see the main [README.md](README.md).

For advanced troubleshooting, check the sections above or open an issue on GitHub.

