function wait_for_all_pod_ready() {
  ns=$1
  timeout=${2:-30s}
  echo "Wait for all pods in namespace $ns to be ready ..."
  for pod in `kubectl -n $ns get pod -oname`;
  do
    kubectl -n $ns wait --for=condition=Ready --timeout $timeout $pod
  done
}
