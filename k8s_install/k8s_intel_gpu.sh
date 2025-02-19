#!/usr/bin/env bash

function k8s_install_intel_gpu() {
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

set -ex
k8s_install_intel_gpu
set +ex
