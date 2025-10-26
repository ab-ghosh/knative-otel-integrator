package main

import (
	"context"

	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/metric"
	kubeclient "knative.dev/pkg/client/injection/kube/client"
	"knative.dev/pkg/configmap"
	"knative.dev/pkg/controller"
	"knative.dev/pkg/logging"

	labelerinformer "github.com/ab-ghosh/knative-otel-integrator/pkg/client/injection/informers/clusterops/v1alpha1/labeler"
	labelerreconciler "github.com/ab-ghosh/knative-otel-integrator/pkg/client/injection/reconciler/clusterops/v1alpha1/labeler"
	deploymentinformer "knative.dev/pkg/client/injection/kube/informers/apps/v1/deployment"
)

func NewController(ctx context.Context, watcher configmap.Watcher) *controller.Impl {
	logger := logging.FromContext(ctx)
	labelerInformer := labelerinformer.Get(ctx)
	deploymentInformer := deploymentinformer.Get(ctx)

	logger.Infof("Setting up event handlers: ")

	// Initialize custom metrics
	meter := otel.Meter("labeler-controller")
	crReconcileCounter, err := meter.Int64Counter(
		"labeler.cr.reconcile.count",
		metric.WithDescription("Total number of Labeler CR reconciliations (create/update)"),
		metric.WithUnit("{reconciliations}"),
	)
	if err != nil {
		logger.Warnw("Failed to create custom metric", "error", err)
	}

	reconciler := &Reconciler{
		labelerInformer:    labelerInformer,
		deploymentInformer: deploymentInformer,
		kubeclient:         kubeclient.Get(ctx),
		crReconcileCounter: crReconcileCounter,
	}

	impl := labelerreconciler.NewImpl(ctx, reconciler, func(impl *controller.Impl) controller.Options {
		return controller.Options{
			SkipStatusUpdates: true,
		}
	})

	// Set up event handlers for Labeler resources
	labelerInformer.Informer().AddEventHandler(controller.HandleAll(impl.Enqueue))
	deploymentInformer.Informer().AddEventHandler(controller.HandleAll(impl.Enqueue))

	return impl
}
