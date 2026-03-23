# Kata Containers Upstream Tests on OpenShift

Scripts for running kata-containers upstream integration tests against an
OpenShift cluster with OpenShift Sandboxed Containers (OSC) installed.

## Prerequisites

- An OpenShift cluster with OSC installed and a `kata` RuntimeClass available
- `kubectl`, `oc`, `bats`, and `yq` on your PATH
- `KUBECONFIG` pointing to your cluster

## Usage

```bash
export KUBECONFIG=/path/to/kubeconfig
./redhat/tests/run-tests.sh
```

### Run a subset of tests

Use `TESTS_FILTER` with a regex to select specific tests:

```bash
TESTS_FILTER="k8s-exec|k8s-env|k8s-job" ./redhat/tests/run-tests.sh
```

### Stop on first failure

```bash
K8S_TEST_FAIL_FAST=yes ./redhat/tests/run-tests.sh
```

### Custom skip list

```bash
TESTS_SKIP_FILE=/path/to/my-skip.yaml ./redhat/tests/run-tests.sh
```

## Files

| File | Description |
|------|-------------|
| `run-tests.sh` | Main wrapper — discovers `.bats` tests, applies skip list and filter, runs them, reports results |
| `skip.yaml` | Tests to skip on OpenShift with reasons (missing node labels, CoCo dependencies, etc.) |
| `helpers.sh` | OpenShift-specific setup: test namespace creation and SCC configuration |

## Skip list

`skip.yaml` lists tests that cannot run on OpenShift. Common reasons:

- Requires `katacontainers.io/kata-runtime=true` node label (not set by OSC)
- Requires confidential computing hardware or KBS
- Assumes containerd or Debian-based hosts
- Behavior differences between upstream k8s and OpenShift (e.g. pause process name)

To enable a skipped test, remove its entry from `skip.yaml` and re-run.

## Environment variables

| Variable | Default | Description |
|----------|---------|-------------|
| `KUBECONFIG` | `~/.kube/config` | Path to kubeconfig |
| `TESTS_SKIP_FILE` | `skip.yaml` | Path to skip list |
| `TESTS_FILTER` | _(empty)_ | Regex to select tests by name |
| `KATA_HYPERVISOR` | `qemu` | Hypervisor for kata |
| `K8S_TEST_FAIL_FAST` | `no` | Stop on first failure when set to `yes` |
