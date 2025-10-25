#!/usr/bin/env bash

# Copyright 2020 The Knative Authors
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -o errexit
set -o nounset
set -o pipefail

source $(dirname $0)/../vendor/knative.dev/hack/codegen-library.sh
source "${CODEGEN_PKG}/kube_codegen.sh"

# If we run with -mod=vendor here, then generate-groups.sh looks for vendor files in the wrong place.
export GOFLAGS=-mod=mod

echo "=== Update Codegen for $MODULE_NAME"

# Compute _example hash for all configmaps.
group "Generating checksums for configmap _example keys"

#${REPO_ROOT_DIR}/hack/update-checksums.sh

group "Kubernetes Codegen"

kube::codegen::gen_helpers \
  --boilerplate "${REPO_ROOT_DIR}/hack/custom-boilerplate.go.txt" \
  "${REPO_ROOT_DIR}/pkg/apis"

kube::codegen::gen_client \
  --boilerplate "${REPO_ROOT_DIR}/hack/custom-boilerplate.go.txt" \
  --output-dir "${REPO_ROOT_DIR}/pkg/client" \
  --output-pkg "$MODULE_NAME/pkg/client" \
  --with-watch \
  "${REPO_ROOT_DIR}/pkg/apis"

group "Knative Codegen"

# Knative Injection
${KNATIVE_CODEGEN_PKG}/hack/generate-knative.sh "injection" \
  $MODULE_NAME/pkg/client $MODULE_NAME/pkg/apis \
  "clusterops:v1alpha1" \
  --go-header-file ${REPO_ROOT_DIR}/hack/custom-boilerplate.go.txt
