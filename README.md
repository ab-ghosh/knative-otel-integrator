# Knative Labeler Controller

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
- Go 1.25+ (for development)

## Installation

### 1. Install the CRD

```bash
kubectl apply -f config/crd/clusterops.io_labelers.yaml
```

Verify the CRD is installed:
```bash
kubectl get crd labelers.clusterops.io
```

### 2. Create Namespace

```bash
kubectl create namespace labeler
```

### 3. Install RBAC Resources

```bash
kubectl apply -f config/100-serviceaccount.yaml -n labeler
kubectl apply -f config/200-role.yaml
kubectl apply -f config/201-rolebinding.yaml
```

### 4. Deploy the Controller

Using `ko`:
```bash
ko resolve -f config/controller.yaml | kubectl apply -n labeler -f -
```

Or build and push manually:
```bash
docker build -t your-registry/labeler-controller:latest .
docker push your-registry/labeler-controller:latest
kubectl apply -f config/controller.yaml -n labeler
```

Verify the controller is running:
```bash
kubectl get pods -n labeler
```

Expected output:
```
NAME                                READY   STATUS    RESTARTS   AGE
label-controller-xxxxx-yyyyy        1/1     Running   0          30s
```

## Usage

### Create a Labeler Custom Resource

Create a `Labeler` CR to specify which labels to apply:

```yaml
apiVersion: clusterops.io/v1alpha1
kind: Labeler
metadata:
  name: example-labeler
  namespace: labeler
spec:
  customLabels:
    environment: "production"
    team: "platform"
    managed-by: "labeler-controller"
```

Apply it:
```bash
kubectl apply -f config/cr.yaml -n labeler
```

### Verify Labels are Applied

Check that your Deployments now have the custom labels:

```bash
kubectl get deployment -n labeler -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.metadata.labels}{"\n"}{end}'
```

Example output:
```
label-controller    {"clusterops.io/release":"devel","environment":"production","managed-by":"labeler-controller","team":"platform"}
```

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
ko publish github.com/ab-ghosh/knative-controller/cmd/labeler
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
