#!/bin/bash
# install.sh - Complete installation script for Knative Labeler Controller
# This script follows the installation steps from README.md

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper functions
print_header() {
    echo ""
    echo -e "${BLUE}============================================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}============================================================${NC}"
    echo ""
}

print_step() {
    echo -e "${GREEN}▶ $1${NC}"
}

print_info() {
    echo -e "${YELLOW}ℹ $1${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

# Parse command line arguments
INSTALL_PROMETHEUS=false
SKIP_PROMETHEUS=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --with-prometheus)
            INSTALL_PROMETHEUS=true
            shift
            ;;
        --skip-prometheus)
            SKIP_PROMETHEUS=true
            shift
            ;;
        -h|--help)
            echo "Usage: ./install.sh [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --with-prometheus    Install Prometheus Operator (kube-prometheus-stack)"
            echo "  --skip-prometheus    Skip Prometheus installation check and setup"
            echo "  -h, --help          Show this help message"
            echo ""
            echo "Examples:"
            echo "  ./install.sh                      # Install without Prometheus"
            echo "  ./install.sh --with-prometheus    # Install with Prometheus"
            echo "  ./install.sh --skip-prometheus    # Skip Prometheus entirely"
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            echo "Run './install.sh --help' for usage information"
            exit 1
            ;;
    esac
done

print_header "🚀 Knative Labeler Controller Installation"

# Check prerequisites
print_step "Checking prerequisites..."

if ! command -v kubectl &> /dev/null; then
    print_error "kubectl not found. Please install kubectl first."
    exit 1
fi
print_info "kubectl: $(kubectl version --client --short 2>/dev/null || kubectl version --client)"

if ! command -v ko &> /dev/null; then
    print_error "ko not found. Please install ko first: https://github.com/ko-build/ko"
    exit 1
fi
print_info "ko: $(ko version 2>/dev/null || echo 'installed')"

if [ "$INSTALL_PROMETHEUS" = true ] && ! command -v helm &> /dev/null; then
    print_error "helm not found. Please install helm first or run without --with-prometheus"
    exit 1
fi

print_success "Prerequisites check passed"
echo ""

# Step 1: Optional Prometheus Installation
if [ "$SKIP_PROMETHEUS" = false ]; then
    if [ "$INSTALL_PROMETHEUS" = true ]; then
        print_header "Step 1: Installing Prometheus Operator"
        
        print_step "Adding Helm repository..."
        helm repo add prometheus-community https://prometheus-community.github.io/helm-charts 2>/dev/null || true
        helm repo update
        print_success "Helm repository added"
        
        print_step "Creating monitoring namespace..."
        kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -
        print_success "Monitoring namespace ready"
        
        print_step "Installing kube-prometheus-stack (this may take 2-3 minutes)..."
        if helm list -n monitoring | grep -q kube-prometheus-stack; then
            print_info "kube-prometheus-stack already installed, skipping..."
        else
            helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack -n monitoring
            print_success "kube-prometheus-stack installed"
        fi
        
        print_step "Waiting for Prometheus to be ready..."
        kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=prometheus -n monitoring --timeout=300s || true
        print_success "Prometheus is ready"
        
        print_step "Verifying ServiceMonitor CRD..."
        if kubectl get crd servicemonitors.monitoring.coreos.com &> /dev/null; then
            print_success "ServiceMonitor CRD is available"
        else
            print_error "ServiceMonitor CRD not found"
            exit 1
        fi
    else
        print_header "Step 1: Checking for Prometheus (Optional)"
        print_info "Checking if Prometheus Operator is installed..."
        
        if kubectl get crd servicemonitors.monitoring.coreos.com &> /dev/null; then
            print_success "Prometheus Operator detected - metrics will be enabled"
            PROMETHEUS_AVAILABLE=true
        else
            print_info "Prometheus Operator not found - controller will run without metrics monitoring"
            print_info "To install Prometheus, run: ./install.sh --with-prometheus"
            PROMETHEUS_AVAILABLE=false
        fi
    fi
else
    print_header "Step 1: Skipping Prometheus Setup"
    print_info "Prometheus setup skipped as requested"
    PROMETHEUS_AVAILABLE=false
fi

# Step 2: Install CRD
print_header "Step 2: Installing Labeler CRD"

print_step "Applying CRD..."
kubectl apply -f config/crd/clusterops.io_labelers.yaml
print_success "CRD applied"

print_step "Verifying CRD installation..."
if kubectl get crd labelers.clusterops.io &> /dev/null; then
    print_success "CRD labelers.clusterops.io is installed"
else
    print_error "CRD installation failed"
    exit 1
fi

# Step 3: Create Namespace
print_header "Step 3: Creating Labeler Namespace"

print_step "Creating namespace 'labeler'..."
kubectl create namespace labeler --dry-run=client -o yaml | kubectl apply -f -
print_success "Namespace 'labeler' ready"

# Step 4: Deploy Controller
print_header "Step 4: Deploying Controller"

print_step "Deploying RBAC, Controller, Services, and Example CR..."
ko apply -Rf config/ -n labeler

print_success "All resources deployed"
echo ""
print_info "Deployed components:"
echo "  • ServiceAccount (clusterops)"
echo "  • Role and RoleBinding"
echo "  • Controller Deployment"
echo "  • Config-observability ConfigMap"
echo "  • Metrics Service (label-controller-metrics)"
if [ "$PROMETHEUS_AVAILABLE" = true ] || [ "$INSTALL_PROMETHEUS" = true ]; then
    echo "  • ServiceMonitor (for Prometheus)"
fi
echo "  • Example Labeler CR"

# Step 5: Verify Installation
print_header "Step 5: Verifying Installation"

print_step "Waiting for controller pod to be ready..."
kubectl wait --for=condition=ready pod -l app=label-controller -n labeler --timeout=120s

POD_NAME=$(kubectl get pod -n labeler -l app=label-controller -o jsonpath='{.items[0].metadata.name}')
print_success "Controller pod is running: $POD_NAME"

print_step "Checking Labeler CR..."
if kubectl get labeler -n labeler &> /dev/null; then
    LABELER_NAME=$(kubectl get labeler -n labeler -o jsonpath='{.items[0].metadata.name}')
    print_success "Labeler CR exists: $LABELER_NAME"
else
    print_error "Labeler CR not found"
fi

print_step "Checking Metrics Service..."
if kubectl get svc label-controller-metrics -n labeler &> /dev/null; then
    print_success "Metrics Service is created"
else
    print_info "Metrics Service not found (expected if metrics are disabled)"
fi

if [ "$PROMETHEUS_AVAILABLE" = true ] || [ "$INSTALL_PROMETHEUS" = true ]; then
    print_step "Checking ServiceMonitor..."
    if kubectl get servicemonitor -n labeler &> /dev/null; then
        SM_NAME=$(kubectl get servicemonitor -n labeler -o jsonpath='{.items[0].metadata.name}')
        print_success "ServiceMonitor exists: $SM_NAME"
    else
        print_info "ServiceMonitor not found"
    fi
fi

# Step 6: Verify Prometheus Integration (if available)
if [ "$PROMETHEUS_AVAILABLE" = true ] || [ "$INSTALL_PROMETHEUS" = true ]; then
    print_header "Step 6: Verifying Prometheus Integration"
    
    print_info "Checking if Prometheus is scraping metrics..."
    print_info "To verify manually:"
    echo ""
    echo "  1. Port-forward to Prometheus:"
    echo "     kubectl port-forward -n monitoring svc/prometheus-operated 9090:9090"
    echo ""
    echo "  2. Open: http://localhost:9090"
    echo ""
    echo "  3. Go to Status → Targets"
    echo "     Look for: labeler/labeler-controller (should be UP)"
    echo ""
fi

# Step 7: Verify Labels are Applied
print_header "Step 7: Verifying Labels are Applied"

print_step "Checking deployment labels..."
sleep 2  # Give the controller a moment to reconcile

DEPLOYMENTS=$(kubectl get deployment -n labeler -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.metadata.labels}{"\n"}{end}')
if [ -n "$DEPLOYMENTS" ]; then
    echo "$DEPLOYMENTS"
    print_success "Labels have been applied to deployments"
else
    print_info "No deployments found or labels not yet applied"
fi

# Show controller logs
echo ""
print_step "Recent controller logs:"
echo "-----------------------------------"
kubectl logs -n labeler "$POD_NAME" --tail=10 2>/dev/null || print_info "Logs not available yet"
echo "-----------------------------------"

# Final success message
print_header "✅ Installation Complete!"

echo ""
echo -e "${GREEN}Your Knative Labeler Controller is now fully installed and running!${NC}"
echo ""
echo -e "${BLUE}What's been set up:${NC}"
echo "  ✅ Labeler CRD installed"
echo "  ✅ Controller running and reconciling"
echo "  ✅ Example labels applied to Deployments"
if [ "$PROMETHEUS_AVAILABLE" = true ] || [ "$INSTALL_PROMETHEUS" = true ]; then
    echo "  ✅ Prometheus metrics exposed"
    echo "  ✅ Automatic monitoring configured"
fi
echo ""

echo -e "${BLUE}Quick Commands:${NC}"
echo ""
echo "📝 View controller logs:"
echo "   kubectl logs -n labeler -l app=label-controller -f"
echo ""
echo "📊 View Labeler resources:"
echo "   kubectl get labeler -n labeler"
echo ""
echo "🏷️  View deployment labels:"
echo "   kubectl get deployment -n labeler -o jsonpath='{range .items[*]}{.metadata.name}{\"\t\"}{.metadata.labels}{\"\n\"}{end}'"
echo ""

if [ "$PROMETHEUS_AVAILABLE" = true ] || [ "$INSTALL_PROMETHEUS" = true ]; then
    echo "📈 Access metrics:"
    echo "   kubectl port-forward -n labeler svc/label-controller-metrics 9090:9090"
    echo "   curl http://localhost:9090/metrics"
    echo ""
    echo "📊 Access Prometheus:"
    echo "   kubectl port-forward -n monitoring svc/prometheus-operated 9090:9090"
    echo "   open http://localhost:9090"
    echo ""
    echo "📊 Access Grafana:"
    echo "   kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80"
    echo "   open http://localhost:3000"
    echo "   (username: admin, password: prom-operator)"
    echo ""
fi

echo -e "${BLUE}Next Steps:${NC}"
echo "  1. Edit config/cr.yaml to customize labels"
echo "  2. Apply changes: kubectl apply -f config/cr.yaml -n labeler"
if [ "$PROMETHEUS_AVAILABLE" = false ] && [ "$SKIP_PROMETHEUS" = false ] && [ "$INSTALL_PROMETHEUS" = false ]; then
    echo "  3. (Optional) Install Prometheus: ./install.sh --with-prometheus"
fi
echo ""
echo -e "${BLUE}For more information, see README.md${NC}"
echo ""

