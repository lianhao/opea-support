#!/bin/bash


MODEL_HOST_PATH=${MODEL_HOST_PATH:-/home/sdp/.cache/huggingface/hub}
MODEL_HOST_PATH_CANONICAL=$(readlink -f ${MODEL_HOST_PATH})

KIND_CLUSTER_CONFIG="${KIND_CLUSTER_CONFIG:-/home/sdp/workspace/cluster-config.yaml}"
KIND_CLUSTER_CONFIG_TPL="${KIND_CLUSTER_CONFIG}.template"

# Get the current week number
week_number=$(date +%V)

# Check if the week number is even
if (( week_number % 2 == 0 )); then
  # Your command goes here
  echo "Restarting because it's an even-numbered week."
  kind delete cluster --name mycluster
  docker volume prune -f

  cp -f "${KIND_CLUSTER_CONFIG}" "${KIND_CLUSTER_CONFIG}.old"
  cp -f "${KIND_CLUSTER_CONFIG_TPL}" "${KIND_CLUSTER_CONFIG}"
  sed -i "s#MODEL_HOST_PATH_CANONICAL#${MODEL_HOST_PATH_CANONICAL}#" "${KIND_CLUSTER_CONFIG}"
  
  kind create cluster --name mycluster --config "${KIND_CLUSTER_CONFIG}"
  kubectl cluster-info --context kind-mycluster
else
  echo "Skipping this week."
fi
