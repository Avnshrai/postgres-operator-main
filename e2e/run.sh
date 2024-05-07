#!/usr/bin/env bash

# enable unofficial bash strict mode
set -o errexit
set -o nounset
set -o pipefail
IFS=$'\n\t'

readonly cluster_name="postgres-operator-e2e-tests"
readonly kubeconfig_path="/tmp/kind-config-${cluster_name}"
# Update the Spilo image tag to use a dynamic tag passed via arguments
readonly spilo_image="coredgeio/postgres-spilo:${1}"
# Use the specific e2e test runner image as requested
readonly e2e_test_runner_image="registry.opensource.zalan.do/acid/postgres-operator-e2e-tests-runner:0.4"

export GOPATH=${GOPATH-~/go}
export PATH=${GOPATH}/bin:$PATH

echo "Clustername: ${cluster_name}"
echo "Kubeconfig path: ${kubeconfig_path}"

function pull_images() {
  operator_tag="${2}"  # Assuming the operator tag is passed as the second argument
  echo "Using operator image tag: ${operator_tag}"
  operator_image="coredgeio/postgres-operator:${operator_tag}"
  docker pull "${operator_image}"  # Pull the specified operator image
  docker pull "${spilo_image}"     # Pull the specified Spilo image
}

function start_kind() {
  echo "Starting kind for e2e tests"
  # avoid interference with previous test runs
  if [[ $(kind get clusters | grep "^${cluster_name}*") != "" ]]
  then
    kind delete cluster --name ${cluster_name}
  fi

  export KUBECONFIG="${kubeconfig_path}"
  kind create cluster --name ${cluster_name} --config e2e/kind-cluster-postgres-operator-e2e-tests.yaml
  kind load docker-image "${spilo_image}" --name ${cluster_name}
  kind load docker-image "${operator_image}" --name ${cluster_name}
}

function load_operator_image() {
  echo "Loading operator image to the kind cluster"
  export KUBECONFIG="${kubeconfig_path}"
  kind load docker-image "${operator_image}" --name ${cluster_name}
}

function main() {
  echo "Entering main function..."
  [[ -z ${NOCLEANUP-} ]] && trap "cleanup" QUIT TERM EXIT
  pull_images "$@"  # Pass all command-line arguments to the pull_images function
  [[ ! -f ${kubeconfig_path} ]] && start_kind
  load_operator_image
  set_kind_api_server_ip
  generate_certificate

  shift 2  # Shift by two to consume both the spilo and operator image tags
  run_tests $@
  exit 0
}

# Call the main function with all command-line arguments
main "$@"
