#!/usr/bin/env bash

# enable unofficial bash strict mode
set -o errexit
set -o nounset
set -o pipefail
IFS=$'\n\t'

readonly cluster_name="postgres-operator-e2e-tests"
readonly kubeconfig_path="/tmp/kind-config-${cluster_name}"
readonly spilo_image="coredgeio/postgres-spilo:3.0-p1"
readonly e2e_test_runner_image="registry.opensource.zalan.do/acid/postgres-operator-e2e-tests-runner:0.4"

export GOPATH=${GOPATH-~/go}
export PATH=${GOPATH}/bin:$PATH

echo "Clustername: ${cluster_name}"
echo "Kubeconfig path: ${kubeconfig_path}"

function pull_images(){
  echo "pulling image"
  local operator_tag="$1"
  if [[ -z $(coredgeio/postgres-operator:${operator_tag}) ]]
  then
    docker pull coredgeio/postgres-operator:${operator_tag}
  fi
  operator_image="coredgeio/postgres-operator:${operator_tag}"
  echo "pulling image done!"
}

function start_kind(){
  echo "Starting kind for e2e tests"
  # avoid interference with previous test runs
  if [[ $(kind get clusters | grep "^${cluster_name}*") != "" ]]
  then
    kind delete cluster --name ${cluster_name}
  fi
  echo "export and create cluster"
  export KUBECONFIG="${kubeconfig_path}"
  kind create cluster --name ${cluster_name} --config e2e/kind-cluster-postgres-operator-e2e-tests.yaml  
  echo "export and create cluster done!"
  echo "pulling spilo image"
  docker pull "${spilo_image}"
  echo "done pulling spilo image"
  echo "kind load"
  kind load docker-image "${spilo_image}" --name ${cluster_name}
  echo "kind load done"
}

function load_operator_image() {
  echo "Loading operator image"
  export KUBECONFIG="${kubeconfig_path}"
  kind load docker-image "${operator_image}" --name ${cluster_name}
}

function set_kind_api_server_ip(){
  echo "Setting up kind API server ip"
  # use the actual kubeconfig to connect to the 'kind' API server
  # but update the IP address of the API server to the one from the Docker 'bridge' network
  readonly local kind_api_server_port=6443 # well-known in the 'kind' codebase
  readonly local kind_api_server=$(docker inspect --format "{{ .NetworkSettings.Networks.kind.IPAddress }}:${kind_api_server_port}" "${cluster_name}"-control-plane)
  sed -i "s/server.*$/server: https:\/\/$kind_api_server/g" "${kubeconfig_path}"
}

function generate_certificate(){
  openssl req -x509 -nodes -newkey rsa:2048 -keyout tls/tls.key -out tls/tls.crt -subj "/CN=acid.zalan.do"
}

function run_tests(){
  echo "Running tests... image: ${e2e_test_runner_image}"
  # tests modify files in ./manifests, so we mount a copy of this directory done by the e2e Makefile

  docker run --rm --network=host -e "TERM=xterm-256color" \
  --mount type=bind,source="$(readlink -f ${kubeconfig_path})",target=/root/.kube/config \
  --mount type=bind,source="$(readlink -f manifests)",target=/manifests \
  --mount type=bind,source="$(readlink -f tls)",target=/tls \
  --mount type=bind,source="$(readlink -f tests)",target=/tests \
  --mount type=bind,source="$(readlink -f exec.sh)",target=/exec.sh \
  --mount type=bind,source="$(readlink -f scripts)",target=/scripts \
  -e OPERATOR_IMAGE="${operator_image}" "${e2e_test_runner_image}" ${E2E_TEST_CASE-} $@
}

function cleanup(){
  echo "Executing cleanup"
  unset KUBECONFIG
  kind delete cluster --name ${cluster_name}
  rm -rf ${kubeconfig_path}
}

function main(){
  echo "Entering main function..."
  [[ -z ${NOCLEANUP-} ]] && trap "cleanup" QUIT TERM EXIT
  operator_tag="$1"
  pull_images
  [[ ! -f ${kubeconfig_path} ]] && start_kind
  load_operator_image
  set_kind_api_server_ip
  generate_certificate

  shift
  run_tests $@
  exit 0
}

"$1" $@

