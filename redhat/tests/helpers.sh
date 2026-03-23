#!/bin/bash
#
# Copyright (c) 2026 Red Hat, Inc.
#
# SPDX-License-Identifier: Apache-2.0
#
# OpenShift-specific helpers for running kata-containers upstream tests.

set -o errexit
set -o nounset
set -o pipefail

# Namespace used for running the tests.
TEST_NAMESPACE="${TEST_NAMESPACE:-kata-upstream-tests}"

# RuntimeClassName used by sandboxed-containers on OpenShift.
RUNTIMECLASS="${RUNTIMECLASS:-kata}"

setup_test_namespace() {
	if ! kubectl get namespace "${TEST_NAMESPACE}" &>/dev/null; then
		kubectl create namespace "${TEST_NAMESPACE}"
	fi

	# Grant privileged SCC to the default service account in the test namespace
	# so that kata pods can run without being blocked by OpenShift security policies.
	oc adm policy add-scc-to-user privileged \
		"system:serviceaccount:${TEST_NAMESPACE}:default" 2>/dev/null || true
}

cleanup_test_namespace() {
	kubectl delete namespace "${TEST_NAMESPACE}" --ignore-not-found --wait=false
}
