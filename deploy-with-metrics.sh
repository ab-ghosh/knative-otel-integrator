#!/bin/bash
# deploy-with-metrics.sh - Deploy the controller with metrics enabled

set -e

echo "🚀 Deploying Knative Controller with OpenTelemetry Metrics"
echo "==========================================================="
echo ""

# Create namespace if it doesn't exist
echo "📦 Creating namespace..."
kubectl create namespace labeler --dry-run=client -o yaml | kubectl apply -f -
echo "✅ Namespace ready"
echo ""

# Deploy everything
echo "🔧 Deploying controller and configuration..."
ko apply -Rf config/ -n labeler
echo "✅ Deployment complete"
echo ""

# Wait for pod to be ready
echo "⏳ Waiting for pod to be ready..."
kubectl wait --for=condition=ready pod -l app=label-controller -n labeler --timeout=60s
echo "✅ Pod is ready"
echo ""

# Get pod name
POD_NAME=$(kubectl get pod -n labeler -l app=label-controller -o jsonpath='{.items[0].metadata.name}')
echo "📊 Pod name: $POD_NAME"
echo ""

# Show logs
echo "📝 Controller logs (last 20 lines):"
echo "-----------------------------------"
kubectl logs -n labeler "$POD_NAME" --tail=20
echo ""

# Check if metrics endpoint is responding
echo "🔍 Checking metrics endpoint..."
kubectl port-forward -n labeler "$POD_NAME" 9090:9090 &
PF_PID=$!
sleep 3

if curl -f -s http://localhost:9090/metrics > /dev/null; then
    echo "✅ Metrics endpoint is responding!"
    echo ""
    
    echo "📈 Sample metrics:"
    echo "-----------------------------------"
    curl -s http://localhost:9090/metrics | grep -E "^(kn_workqueue|go_)" | head -15
    echo ""
    
    echo "✅ SUCCESS! Metrics are being exported."
else
    echo "❌ Metrics endpoint not responding"
fi

# Cleanup port-forward
kill $PF_PID 2>/dev/null || true

echo ""
echo "==========================================================="
echo "🎉 Deployment Complete!"
echo ""
echo "📍 To access metrics:"
echo "   kubectl port-forward -n labeler svc/label-controller-metrics 9090:9090"
echo "   curl http://localhost:9090/metrics"
echo ""
echo "📍 To view all workqueue metrics:"
echo "   curl http://localhost:9090/metrics | grep kn_workqueue"
echo ""
echo "📍 To view controller logs:"
echo "   kubectl logs -n labeler -l app=label-controller -f"
echo "==========================================================="

