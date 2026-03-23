#!/bin/bash
#
# Copyright (c) 2026 Red Hat, Inc.
#
# SPDX-License-Identifier: Apache-2.0
#
# Wrapper script for running kata-containers upstream integration tests
# on an OpenShift cluster with sandboxed-containers installed.
#
# Environment variables:
#   TESTS_SKIP_FILE  - path to YAML file listing tests to skip (default: skip.yaml next to this script)
#   TESTS_FILTER     - optional regex to select which tests to run (e.g. "k8s-exec|k8s-env")
#   KATA_HYPERVISOR  - hypervisor to use (default: qemu)
#   KUBECONFIG       - path to kubeconfig (default: ~/.kube/config)

set -o errexit
set -o nounset
set -o pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../../" && pwd)"
kubernetes_dir="${repo_root}/tests/integration/kubernetes"

source "${repo_root}/tests/common.bash"
source "${script_dir}/helpers.sh"

TESTS_SKIP_FILE="${TESTS_SKIP_FILE:-${script_dir}/skip.yaml}"
TESTS_FILTER="${TESTS_FILTER:-}"
KATA_HYPERVISOR="${KATA_HYPERVISOR:-qemu}"
K8S_TEST_FAIL_FAST="${K8S_TEST_FAIL_FAST:-no}"

# Parse the skip list YAML and return an array of test names (without .bats extension).
get_skip_list() {
	local skip_file="$1"

	if [ ! -f "${skip_file}" ]; then
		return
	fi

	# Extract test names from the skip list using yq.
	yq '.skip[].name' "${skip_file}" 2>/dev/null || true
}

# Build the list of .bats test files to run.
build_test_list() {
	local -a skip_names=()
	local skip_entry

	while IFS= read -r skip_entry; do
		[ -n "${skip_entry}" ] && skip_names+=("${skip_entry}")
	done < <(get_skip_list "${TESTS_SKIP_FILE}")

	local -a test_files=()
	for bats_file in "${kubernetes_dir}"/k8s-*.bats; do
		local test_name
		test_name="$(basename "${bats_file}" .bats)"

		# Check skip list
		local skipped=false
		for skip in "${skip_names[@]:-}"; do
			if [ "${test_name}" = "${skip}" ]; then
				skipped=true
				break
			fi
		done
		${skipped} && continue

		# Apply optional regex filter
		if [ -n "${TESTS_FILTER}" ]; then
			if ! echo "${test_name}" | grep -qE "${TESTS_FILTER}"; then
				continue
			fi
		fi

		test_files+=("$(basename "${bats_file}")")
	done

	echo "${test_files[@]}"
}

cleanup() {
	info "Cleaning up..."
	pushd "${kubernetes_dir}" > /dev/null
	kubectl delete --all pods --ignore-not-found 2>/dev/null || true
	rm -rf "${kubernetes_dir}/runtimeclass_workloads_work"
	popd > /dev/null
	cleanup_test_namespace
}

main() {
	ensure_yq

	setup_test_namespace
	trap cleanup EXIT

	local -a test_list
	read -ra test_list <<< "$(build_test_list)"

	if [ ${#test_list[@]} -eq 0 ]; then
		die "No tests to run. Check TESTS_SKIP_FILE and TESTS_FILTER settings."
	fi

	info "Will run ${#test_list[@]} test(s): ${test_list[*]}"

	# Run upstream setup to prepare workload fixtures (runtimeclass_workloads_work/).
	pushd "${kubernetes_dir}" > /dev/null
	bash setup.sh
	popd > /dev/null

	local report_dir="${kubernetes_dir}/reports/$(date +'%F-%T')"
	mkdir -p "${report_dir}"

	pushd "${kubernetes_dir}" > /dev/null

	local -a tests_fail=()
	for test_entry in "${test_list[@]}"; do
		test_entry="$(echo "${test_entry}" | tr -d '[:space:][:cntrl:]')"
		info "Executing ${test_entry}"

		local out_file="${report_dir}/${test_entry}.out"
		if ! bats --timing --show-output-of-passing-tests "${test_entry}" | tee "${out_file}"; then
			tests_fail+=("${test_entry}")
			mv "${out_file}" "$(dirname "${out_file}")/not_ok-$(basename "${out_file}")"
			[ "${K8S_TEST_FAIL_FAST}" = "yes" ] && break
		else
			mv "${out_file}" "$(dirname "${out_file}")/ok-$(basename "${out_file}")"
		fi
	done

	popd > /dev/null

	# Print summary
	echo ""
	echo "=== Test Summary ==="
	echo "  Total:  ${#test_list[@]}"
	echo "  Failed: ${#tests_fail[@]}"
	echo "  Passed: $(( ${#test_list[@]} - ${#tests_fail[@]} ))"

	if [ ${#tests_fail[@]} -ne 0 ]; then
		echo ""
		echo "Failed tests:"
		for f in "${tests_fail[@]}"; do
			echo "  - ${f}"
		done
		die "Tests FAILED from suites: ${tests_fail[*]}"
	fi

	info "All tests PASSED"
}

main "$@"
