#!/usr/bin/env bash

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
source ${SCRIPT_DIR}/utils.sh

function k8s_install_intel_gpu_helm() {
  # See https://github.com/intel/intel-device-plugins-for-kubernetes/blob/main/INSTALL.md for details
  helm repo add jetstack https://charts.jetstack.io # for cert-manager
  helm repo add nfd https://kubernetes-sigs.github.io/node-feature-discovery/charts # for NFD
  helm repo add intel https://intel.github.io/helm-charts/ # for device-plugin-operator and plugins
  helm repo update

  # Install cert-manager
  helm install --wait \
    cert-manager jetstack/cert-manager \
    --namespace cert-manager --create-namespace \
    --version v1.15.2 \
    --set installCRDs=true \
    --set global.leaderElection.namespace=cert-manager

  # Install NFD
  helm install --wait \
    nfd nfd/node-feature-discovery \
    --namespace node-feature-discovery --create-namespace \
    --version 0.17.1

  # Install device plugin operator
  helm install --wait \
     dp-operator intel/intel-device-plugins-operator \
     --namespace inteldeviceplugins-system --create-namespace

  # Install gpu device plugin
  helm install --wait \
    gpu intel/intel-device-plugins-gpu \
     --namespace inteldeviceplugins-system --create-namespace \
     --set nodeFeatureRule=true
}

GPUDEV_PLUGIN_VER="0.32.0"

function k8s_install_intel_gpu() {
  # Start NFD - if your cluster doesn't have NFD installed yet
  kubectl apply -k "https://github.com/intel/intel-device-plugins-for-kubernetes/deployments/nfd?ref=v${GPUDEV_PLUGIN_VER}"

  # Create NodeFeatureRules for detecting GPUs on nodes  
  kubectl apply -k "https://github.com/intel/intel-device-plugins-for-kubernetes/deployments/nfd/overlays/node-feature-rules?ref=v${GPUDEV_PLUGIN_VER}"

  # Create GPU plugin daemonset
  kubectl create ns intel-gpu-plugin || true
  kubectl -n intel-gpu-plugin apply -k "https://github.com/intel/intel-device-plugins-for-kubernetes/deployments/gpu_plugin/overlays/nfd_labeled_nodes?ref=v${GPUDEV_PLUGIN_VER}"
}

function k8s_verify_intel_gpu() {
cat <<EOF | kubectl apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: intelgpu-demo-job
  labels:
    jobgroup: intelgpu-demo
spec:
  template:
    metadata:
      labels:
        jobgroup: intelgpu-demo
    spec:
      restartPolicy: Never
      containers:
        -
          name: intelgpu-demo-job-1
          image: lianhao/intel-opencl-icd:0.32.0
          imagePullPolicy: IfNotPresent
          command: [ "clinfo" ]
          resources:
            limits:
              gpu.intel.com/i915: 1
EOF

kubectl wait --for=condition=complete job/intelgpu-demo-job --timeout 90s
pod=$(kubectl get pod -l jobgroup=intelgpu-demo -oname)
devnum=$(kubectl logs $pod | grep 'Number of devices' | awk '{print $4}')
kubectl delete job/intelgpu-demo-job

set +e
if [ $devnum -eq 1 ]; then
    echo "Success: Found 1 GPU in pod"
else
    echo "Faiulre: Not found 1 GPU in pod"
fi
set -e
}

set -ex
k8s_install_intel_gpu
wait_for_all_pod_ready intel-gpu-plugin
k8s_verify_intel_gpu
set +ex
