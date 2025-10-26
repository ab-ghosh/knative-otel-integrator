# Knative OpenTelemetry (OTEL) Controller

A Kubernetes operator built with Knative's controller framework that automatically applies custom labels to Deployments based on Custom Resource definitions.

## Overview

The Labeler Controller watches for `Labeler` custom resources and automatically applies specified labels to all Deployments in the same namespace. This is useful for:

- Automated label management across multiple deployments
- Enforcing organizational labeling standards
- Dynamic label updates without manual intervention
- Centralized label configuration

## Architecture

This project follows the standard Kubernetes Operator pattern with three main components:

### 1. Custom Resource Definition (CRD)
Defines the `Labeler` resource type and its schema.

### 2. Controller
A Knative-based controller that:
- Watches for `Labeler` custom resources
- Lists all Deployments in the Labeler's namespace
- Applies/updates labels on those Deployments
- Reconciles on CR create, update, delete, and periodic resync

### 3. Custom Resources (CR)
Instances of `Labeler` that specify which labels to apply.

```
┌─────────────────────────────────────────────────────┐
│  User creates Labeler CR                            │
│  ↓                                                   │
│  Controller detects CR                              │
│  ↓                                                   │
│  Lists Deployments in namespace                     │
│  ↓                                                   │
│  Patches each Deployment with custom labels         │
└─────────────────────────────────────────────────────┘
```

## Prerequisites

- Kubernetes cluster (v1.25+)
- `kubectl` configured to access your cluster
- [ko](https://github.com/ko-build/ko) for building and deploying Go applications
- [Helm 3](https://helm.sh/docs/intro/install/) (for Prometheus setup)
- Go 1.25+ (for development)

## Complete Installation Guide

This guide covers the complete setup from scratch, including Prometheus monitoring.

> **💡 Quick Install:** Use the automated installation script:
> ```bash
> # Install without Prometheus
> ./install.sh
> 
> # Install with Prometheus monitoring
> ./install.sh --with-prometheus
> 
> # Skip Prometheus checks entirely
> ./install.sh --skip-prometheus
> ```

### Step 1: Install Prometheus Operator (Optional but Recommended)

The controller exposes Prometheus metrics for production monitoring. Install Prometheus Operator first to enable metrics collection.

#### Add Helm Repository

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
```

#### Create Monitoring Namespace

```bash
kubectl create namespace monitoring
```

#### Install kube-prometheus-stack

This includes Prometheus Operator, Prometheus, Alertmanager, and Grafana:

```bash
helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack -n monitoring
```

#### Verify Prometheus Installation

```bash
kubectl get pods -n monitoring
```

Wait for all pods to be ready (this may take 1-2 minutes):

```bash
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=prometheus -n monitoring --timeout=300s
```

#### Verify ServiceMonitor CRD

```bash
kubectl get crd servicemonitors.monitoring.coreos.com
```

Expected output:
```
NAME                                    CREATED AT
servicemonitors.monitoring.coreos.com   2025-01-XX...
```

> **Note:** If you don't want metrics/monitoring, you can skip this step and continue to Step 2.

---

### Step 2: Install the Labeler CRD

```bash
kubectl apply -f config/crd/clusterops.io_labelers.yaml
```

Verify the CRD is installed:
```bash
kubectl get crd labelers.clusterops.io
```

Expected output:
```
NAME                      CREATED AT
labelers.clusterops.io    2025-10-26T...
```

---

### Step 3: Create Labeler Namespace

```bash
kubectl create namespace labeler
```

---

### Step 4: Deploy the Controller

Deploy RBAC, Controller, Metrics Service, ServiceMonitor, and Example CR:

```bash
ko apply -Rf config/ -- -n labeler
```

This deploys:
- ✅ ServiceAccount (`clusterops`)
- ✅ Role and RoleBinding (permissions for Deployments and Labelers)
- ✅ Controller Deployment (with metrics enabled on port 9090)
- ✅ Config-observability ConfigMap (Prometheus configuration)
- ✅ Metrics Service (`label-controller-metrics`)
- ✅ ServiceMonitor (tells Prometheus where to scrape)
- ✅ Example Labeler CR

---

### Step 5: Verify Installation

#### Check Controller is Running

```bash
kubectl get pods -n labeler
```

Expected output:
```
NAME                                READY   STATUS    RESTARTS   AGE
label-controller-xxxxx-yyyyy        1/1     Running   0          30s
```

#### Check Labeler CR

```bash
kubectl get labeler -n labeler
```

Expected output:
```
NAME                  AGE
example-labeler       30s
```

#### Check Metrics Service

```bash
kubectl get svc label-controller-metrics -n labeler
```

Expected output:
```
NAME                        TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)    AGE
label-controller-metrics    ClusterIP   10.96.xxx.xxx   <none>        9090/TCP   30s
```

#### Check ServiceMonitor (if Prometheus is installed)

```bash
kubectl get servicemonitor -n labeler
```

Expected output:
```
NAME                 AGE
labeler-controller   30s
```

---

### Step 6: Verify Prometheus Integration (Optional)

If you installed Prometheus in Step 1, verify it's scraping metrics:

#### Port-forward to Prometheus UI

```bash
kubectl port-forward -n monitoring svc/prometheus-operated 9090:9090
```

#### Open Prometheus UI

```bash
open http://localhost:9090
```

Or visit: http://localhost:9090

#### Check Targets

1. Go to: **Status → Targets**
2. Look for: `labeler/labeler-controller`
3. Status should be: **UP** (green)

#### Test Metrics Query

Go to **Graph** tab and run:

```promql
kn_workqueue_depth{name="main.Reconciler"}
```

You should see metrics data returned.

> **Troubleshooting:** If target shows DOWN or no data, see the [Prometheus Metrics](#prometheus-metrics) section below.

---

### Step 7: Verify Labels are Applied

Check that your Deployments now have the custom labels:

```bash
kubectl get deployment -n labeler -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.metadata.labels}{"\n"}{end}'
```

Example output:
```
label-controller    {"clusterops.io/release":"devel","environment":"production","managed-by":"labeler-controller","team":"platform"}
```

---

## ✅ Installation Complete!

Your Knative Labeler Controller is now fully installed and running with metrics enabled.

**What's been set up:**
- ✅ Labeler CRD installed
- ✅ Controller running and reconciling
- ✅ Example labels applied to Deployments
- ✅ Prometheus metrics exposed (if Prometheus installed)
- ✅ Automatic monitoring configured

---

## Usage

### Update Labels

Edit your Labeler CR to change or add labels:

```yaml
spec:
  customLabels:
    environment: "staging"     # Changed
    team: "platform"
    version: "v2.0"            # Added
```

Apply the changes:
```bash
kubectl apply -f config/cr.yaml -n labeler
```

The controller will automatically detect the change and update all Deployment labels.

### View Controller Logs

```bash
kubectl logs -n labeler -l app=label-controller -f
```

Example log output:
```json
{"severity":"INFO","message":"Reconciling Labeler : example-labeler"}
{"severity":"INFO","message":"Found 1 deployments in namespace labeler"}
{"severity":"INFO","message":"Reconcile succeeded","duration":"10.97ms"}
```

## Configuration

### Labeler Spec

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `customLabels` | `map[string]string` | Yes | Key-value pairs of labels to apply to Deployments |

Example:
```yaml
spec:
  customLabels:
    environment: "production"
    team: "devops"
    cost-center: "engineering"
    app-version: "2.0"
```

### Controller Configuration

The controller supports Knative's standard configuration via ConfigMaps:

**Logging Configuration:**
```bash
kubectl apply -f config/config-logging.yaml -n labeler
```

Adjust log levels (debug, info, warn, error) in `config/config-logging.yaml`.

## How It Works

### Reconciliation Triggers

The controller reconciles (applies labels) when:

1. **Labeler CR is created** - Initial label application
2. **Labeler CR is updated** - Labels are re-applied with new values
3. **Labeler CR is deleted** - (Future: cleanup logic)
4. **Controller restarts** - Resyncs all existing CRs
5. **Periodic resync** - Every 10 hours (default)

### Label Merging

The controller **merges** labels rather than replacing them:
- Existing labels on Deployments are preserved
- Only specified labels in the Labeler CR are added/updated
- No labels are removed

Example:
```yaml
# Deployment has: {"app": "nginx", "version": "1.0"}
# Labeler adds: {"team": "devops", "env": "prod"}
# Result: {"app": "nginx", "version": "1.0", "team": "devops", "env": "prod"}
```

## Development

### Prerequisites

- Go 1.25+
- Docker or compatible container runtime
- Access to a Kubernetes cluster (kind, minikube, etc.)

### Project Structure

```
.
├── cmd/
│   └── labeler/
│       ├── main.go          # Entry point
│       ├── controller.go    # Controller setup
│       └── reconciler.go    # Reconciliation logic
├── pkg/
│   ├── apis/
│   │   └── clusterops/
│   │       └── v1alpha1/
│   │           ├── doc.go        # Package documentation
│   │           ├── types.go      # API types (Labeler, LabelerSpec)
│   │           ├── register.go   # Scheme registration
│   │           └── zz_generated.deepcopy.go  # Auto-generated
│   └── client/               # Auto-generated clientsets, listers, informers
├── config/
│   ├── crd/                  # CRD definitions
│   ├── 100-serviceaccount.yaml
│   ├── 200-role.yaml
│   ├── 201-rolebinding.yaml
│   ├── controller.yaml       # Controller Deployment
│   ├── config-logging.yaml
│   └── cr.yaml              # Example Custom Resource
├── hack/
│   ├── update-codegen.sh    # Code generation script
│   └── tools.go             # Tool dependencies
├── vendor/                   # Vendored dependencies
├── go.mod
└── README.md
```

### Building

```bash
# Build locally
go build -o bin/labeler ./cmd/labeler

# Build and push container image with ko
ko publish github.com/ab-ghosh/knative-otel-integrator/cmd/labeler
```

### Code Generation

After modifying API types in `pkg/apis/clusterops/v1alpha1/types.go`, regenerate code:

```bash
# Regenerate deepcopy, clientset, listers, informers, and injection code
./hack/update-codegen.sh

# Regenerate CRDs
GOFLAGS=-mod=mod controller-gen crd paths=./pkg/apis/... output:crd:artifacts:config=config/crd
```

### Local Development

1. **Create a local cluster:**
   ```bash
   kind create cluster
   ```

2. **Install CRD and RBAC:**
   ```bash
   kubectl apply -f config/crd/
   kubectl create namespace labeler
   kubectl apply -f config/100-serviceaccount.yaml -n labeler
   kubectl apply -f config/200-role.yaml
   kubectl apply -f config/201-rolebinding.yaml
   ```

3. **Deploy controller:**
   ```bash
   ko apply -f config/controller.yaml -n labeler
   ```

4. **Test with example CR:**
   ```bash
   kubectl apply -f config/cr.yaml -n labeler
   ```

5. **Watch logs:**
   ```bash
   kubectl logs -n labeler -l app=label-controller -f
   ```

### Running Tests

```bash
# Run unit tests
go test ./...

# Run with coverage
go test -cover ./...
```

## Troubleshooting

### Installation Issues

**Prometheus Operator not found:**
```bash
# Verify Prometheus Operator is installed
kubectl get crd servicemonitors.monitoring.coreos.com

# If missing, install using Step 1 above
```

**ServiceMonitor not discovered by Prometheus:**

Check if Prometheus is using a label selector:
```bash
kubectl get prometheus -n monitoring -o jsonpath='{.items[0].spec.serviceMonitorSelector}'
```

If it returns `{"matchLabels":{"release":"kube-prometheus-stack"}}`, ensure your ServiceMonitor has the correct label (already included in `config/servicemonitor.yaml`).

---

### Controller not reconciling

**Check if controller is running:**
```bash
kubectl get pods -n labeler -l app=label-controller
```

**View controller logs:**
```bash
kubectl logs -n labeler -l app=label-controller --tail=50
```

### Labels not applied

**Verify Labeler CR exists:**
```bash
kubectl get labeler -n labeler
kubectl describe labeler example-labeler -n labeler
```

**Check RBAC permissions:**
```bash
kubectl auth can-i list deployments --as=system:serviceaccount:labeler:clusterops -n labeler
kubectl auth can-i patch deployments --as=system:serviceaccount:labeler:clusterops -n labeler
```

**Trigger manual reconciliation:**
```bash
kubectl annotate labeler example-labeler reconcile=trigger -n labeler --overwrite
```

### Controller pod fails to start

**Check service account exists:**
```bash
kubectl get sa clusterops -n labeler
```

**View pod events:**
```bash
kubectl describe pod -n labeler -l app=label-controller
```

---

## Prometheus Metrics

The controller exposes Prometheus metrics on port 9090 for production monitoring.

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

**Direct pod access:**
```bash
# Get pod name
POD_NAME=$(kubectl get pod -n labeler -l app=label-controller -o jsonpath='{.items[0].metadata.name}')

# Access metrics directly from pod
kubectl port-forward -n labeler $POD_NAME 9090:9090
curl http://localhost:9090/metrics
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

---

### Available Metrics

#### Workqueue Metrics

| Metric | Type | Description |
|--------|------|-------------|
| `kn_workqueue_depth` | Gauge | Current queue depth |
| `kn_workqueue_adds_total` | Counter | Total items added |
| `kn_workqueue_queue_duration_seconds` | Histogram | Time waiting in queue |
| `kn_workqueue_process_duration_seconds` | Histogram | Processing time |
| `kn_workqueue_unfinished_work_seconds` | Gauge | Unfinished work duration |
| `kn_workqueue_longest_running_processor_seconds` | Gauge | Longest running item |
| `kn_workqueue_retries_total` | Counter | Retry count |

#### Kubernetes Client Metrics

| Metric | Type | Description |
|--------|------|-------------|
| `kn_k8s_client_http_request_duration_seconds` | Histogram | K8s API request latency |
| `kn_k8s_client_http_response_status_code_total` | Counter | K8s API request count by status |

#### Go Runtime Metrics

| Metric | Description |
|--------|-------------|
| `go_memory_used_bytes` | Memory used |
| `go_goroutine_count` | Goroutine count |
| `go_memory_allocated_bytes` | Heap allocations |
| And more standard Go runtime metrics... |

### Query Examples

Access Prometheus UI:
```bash
kubectl port-forward -n monitoring svc/prometheus-operated 9090:9090
open http://localhost:9090
```

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

### Grafana Dashboard (Optional)

If you installed kube-prometheus-stack, Grafana is available:

```bash
# Port-forward to Grafana
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80

# Open Grafana (default credentials: admin/prom-operator)
open http://localhost:3000
```

**Add Dashboard Panels:**

1. **Queue Depth (Graph):**
   ```promql
   kn_workqueue_depth{name="main.Reconciler"}
   ```

2. **Processing Rate (Graph):**
   ```promql
   rate(kn_workqueue_adds_total{name="main.Reconciler"}[5m])
   ```

3. **Processing Duration p95 (Graph):**
   ```promql
   histogram_quantile(0.95, 
     rate(kn_workqueue_process_duration_seconds_bucket{name="main.Reconciler"}[5m])
   )
   ```

4. **Memory Usage (Graph):**
   ```promql
   go_memory_used_bytes / 1024 / 1024
   ```

### Alerting Rules (Optional)

Create alerts for production monitoring:

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: labeler-alerts
  namespace: labeler
  labels:
    release: kube-prometheus-stack
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

### Troubleshooting Metrics

**Metrics endpoint not accessible:**
```bash
# Test metrics endpoint directly
kubectl port-forward -n labeler svc/label-controller-metrics 9090:9090
curl http://localhost:9090/metrics
```

**Target shows DOWN in Prometheus:**
```bash
# Check Service exists
kubectl get svc label-controller-metrics -n labeler

# Check pod is running
kubectl get pods -n labeler -l app=label-controller

# Check ServiceMonitor matches Service labels
kubectl get svc label-controller-metrics -n labeler -o yaml | grep -A5 labels
kubectl get servicemonitor labeler-controller -n labeler -o yaml | grep -A5 selector
```

**No metrics appearing:**
```bash
# Verify config-observability is correct
kubectl get cm config-observability -n labeler -o yaml

# Should have:
#   metrics-protocol: prometheus
#   metrics-endpoint: ":9090"

# Check controller logs
kubectl logs -n labeler -l app=label-controller | grep -i observability

# Restart controller if needed
kubectl rollout restart deployment/label-controller -n labeler
```

---

## Examples

### Example 1: Environment Labels

```yaml
apiVersion: clusterops.io/v1alpha1
kind: Labeler
metadata:
  name: env-labeler
  namespace: production
spec:
  customLabels:
    environment: "production"
    tier: "frontend"
    region: "us-west-2"
```

### Example 2: Team Ownership

```yaml
apiVersion: clusterops.io/v1alpha1
kind: Labeler
metadata:
  name: team-labeler
  namespace: platform-team
spec:
  customLabels:
    team: "platform"
    owner: "john.doe@company.com"
    cost-center: "engineering-123"
```

### Example 3: Compliance Labels

```yaml
apiVersion: clusterops.io/v1alpha1
kind: Labeler
metadata:
  name: compliance-labeler
  namespace: secure-apps
spec:
  customLabels:
    compliance: "pci-dss"
    data-classification: "confidential"
    backup-required: "true"
```

## Comparison with Other Solutions

### vs Manual `kubectl label`
- ✅ Automated - no manual intervention needed
- ✅ Declarative - specify desired state
- ✅ Namespace-wide - applies to all deployments
- ✅ Self-healing - reapplies on drift

### vs Admission Webhooks
- ✅ Post-creation modification supported
- ✅ Doesn't require webhook infrastructure
- ✅ Can update existing resources
- ❌ Not preventive (webhook would reject at creation)

### vs Kyverno/OPA
- ✅ Simpler - focused use case
- ✅ Lighter weight
- ❌ Less flexible - only label management

## Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests
5. Submit a pull request

## License

Licensed under the Apache License, Version 2.0. See LICENSE file for details.

## Credits

Built with:
- [Knative](https://knative.dev/) - Controller framework
- [controller-gen](https://github.com/kubernetes-sigs/controller-tools) - CRD generation
- [ko](https://github.com/ko-build/ko) - Container image building

## Contact

For questions or issues, please open a GitHub issue.
