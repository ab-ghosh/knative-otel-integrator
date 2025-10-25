package main

import (
	"context"

	kubeclient "knative.dev/pkg/client/injection/kube/client"
	"knative.dev/pkg/configmap"
	"knative.dev/pkg/controller"
	"knative.dev/pkg/logging"

	labelerinformer "github.com/ab-ghosh/knative-controller/pkg/client/injection/informers/clusterops/v1alpha1/labeler"
	labelerreconciler "github.com/ab-ghosh/knative-controller/pkg/client/injection/reconciler/clusterops/v1alpha1/labeler"
	deploymentinformer "knative.dev/pkg/client/injection/kube/informers/apps/v1/deployment"
)

func NewController(ctx context.Context, watcher configmap.Watcher) *controller.Impl {
	logger := logging.FromContext(ctx)
	labelerInformer := labelerinformer.Get(ctx)
	deploymentInformer := deploymentinformer.Get(ctx)

	logger.Infof("Setting up event handlers: ")

	reconciler := &Reconciler{
		labelerInformer:    labelerInformer,
		deploymentInformer: deploymentInformer,
		kubeclient:         kubeclient.Get(ctx),
	}

	impl := labelerreconciler.NewImpl(ctx, reconciler, func(impl *controller.Impl) controller.Options {
		return controller.Options{
			SkipStatusUpdates: true,
		}
	})

	return impl
}
