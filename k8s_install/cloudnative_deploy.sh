#!/usr/bin/env bash

# You may change the component version if necessary
ARCH="amd64"

CONTAINERD_VER="2.0.2"
RUNC_VER="1.2.5"
CNI_VER="1.6.2"
NERDCTL_VER="2.0.3"
BUILDKIT_VER="0.19.0"

CRICTL_VER="1.31.0"
HELM_VER="3.17.1"
K8S_VER="1.32.2"
CALICO_VER="3.29.2"

# K8S config
POD_CIDR="10.244.0.0/16"
# the NIC_CIDR is help to determine which NIC to be used by K8s CNI
# default is to use the NIC where default route is bind
NIC_CIDR=${NIC_CIDR}
# k8s api server bind address
# default is to use the NIC where default route is bind
APISERVER_ADDR=${APISERVER_ADDR}

function _get_os_distro() {
if [ -f /etc/os-release ]; then
  source /etc/os-release
  if [[ "$ID" == "ubuntu" ]]; then
    echo "ubuntu"
  if [[ "$ID" == "debian" ]]; then
    echo "ubuntu"
  elif [[ "$ID" == "rhel" ]]; then
    echo "rhel"
  elif [[ "$ID" == "fedora" ]]; then
    echo "rhel"
  else
    echo "other"
  fi
elif [ -f /etc/redhat-release ]; then
  echo "rhel"
elif [ -f /etc/lsb-release ]; then
  source /etc/lsb-release
  if [[ "$DISTRIB_ID" == "Ubuntu" ]]; then
    echo "ubuntu"
  else
      echo "other"
  fi
else
  echo "unknown"
fi
}

function _install_pkg() {
  if [[ $OS == "ubuntu" ]]; then
    sudo apt-get -y install $@
  elif [[ $OS == "rhel" ]]; then
    sudo dnf -y install $@
  else
    echo "Unsupported OS $OS"
    exit 1
  fi
}
function _clean_os_docker_ubuntu() {
  for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; 
  do 
    sudo apt-get -y remove $pkg; 
  done
}

function _clean_os_docker_rhel() {
  sudo dnf -y remove docker docker-client docker-client-latest docker-common docker-latest docker-latest-logrotate docker-logrotate docker-engine podman runc
}

function _install_docker_ubuntu() {
  echo "#Add Docker's official GPG key ......"
  sudo apt-get update
  sudo apt-get -y install ca-certificates curl
  sudo install -m 0755 -d /etc/apt/keyrings
  sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  sudo chmod a+r /etc/apt/keyrings/docker.asc

  echo "#Add the repository to Apt sources ......"
  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
    $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | \
    sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
  sudo apt-get update
  
  echo "#Install docker engine ......"
  sudo apt-get -y install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  sudo systemctl restart docker
}

function _install_docker_rhel() {
  echo "#Install docker engine ......"
  sudo dnf -y install dnf-plugins-core
  sudo dnf -y config-manager --add-repo https://download.docker.com/linux/rhel/docker-ce.repo
  sudo systemctl enable --now docker
  sudo systemctl start docker
}

function install_docker() {
  _clean_os_docker_${OS}
  _install_docker_${OS}
  # manage docker as non-root
  sudo groupadd docker
  sudo usermod -aG docker $USER
  sudo systemctl restart docker
}

function _uninstall_docker_ubuntu() {
  sudo apt-get -y purge docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin docker-ce-rootless-extras
  sudo rm -rf /var/lib/docker
  sudo rm -rf /var/lib/containerd
  sudo rm /etc/apt/sources.list.d/docker.list
  sudo rm /etc/apt/keyrings/docker.asc
}

function _uninstall_docker_rhel() {
  sudo dnf -y remove docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin docker-ce-rootless-extras
  sudo rm -rf /var/lib/docker
  sudo rm -rf /var/lib/containerd
}

function uninstall_docker() {
  _uninstall_docker_${OS}
}

function _install_k8s_cri() {
echo "# Disable swap ......"
sudo swapoff -a
sudo sed -i "s/^[^#]\(.*swap\)/#\1/g" /etc/fstab
echo "# load kernel module for containerd ......"
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF
sudo modprobe overlay
sudo modprobe br_netfilter
echo "# Enable IPv4 packet forwarding ......"
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.ipv4.ip_forward = 1
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF
sudo sysctl --system

echo "# Install Runc ......"
wget https://github.com/opencontainers/runc/releases/download/v${RUNC_VER}/runc.${ARCH}
sudo install -m 755 runc.${ARCH} /usr/local/sbin/runc
rm -f runc.${ARCH}

echo "#Install CNI ......"
sudo mkdir -p /opt/cni/bin
wget -c https://github.com/containernetworking/plugins/releases/download/v${CNI_VER}/cni-plugins-linux-${ARCH}-v${CNI_VER}.tgz -qO - | sudo tar xvz -C /opt/cni/bin

echo "#Install Containerd ......"
wget -c https://github.com/containerd/containerd/releases/download/v${CONTAINERD_VER}/containerd-${CONTAINERD_VER}-linux-${ARCH}.tar.gz -qO - | sudo tar xvz -C /usr/local
sudo mkdir -p /usr/local/lib/systemd/system/containerd.service.d
sudo -E wget https://raw.githubusercontent.com/containerd/containerd/main/containerd.service -qO /usr/local/lib/systemd/system/containerd.service
cat <<EOF | sudo tee /usr/local/lib/systemd/system/containerd.service.d/http-proxy.conf
[Service]
Environment="HTTP_PROXY=${http_proxy}"
Environment="HTTPS_PROXY=${https_proxy}"
Environment="NO_PROXY=10.96.0.1,10.96.0.0/12,10.0.0.0/8,svc,svc.cluster.local,${no_proxy}"
EOF
sudo mkdir -p /etc/containerd
sudo rm -f /etc/containerd/config.toml
containerd config default | sudo tee /etc/containerd/config.toml
sudo sed -i "s/SystemdCgroup = false/SystemdCgroup = true/g" /etc/containerd/config.toml
if ! grep 'SystemdCgroup = true' /etc/containerd/config.toml
then
  containerd_config_ver=$(cat /etc/containerd/config.toml | grep version | awk '{print $3'})
  if [[ ${containerd_config_ver} -eq 3 ]]; then
     sudo sed -i "/plugins.'io.containerd.cri.v1.runtime'.containerd.runtimes.runc.options.*/a SystemdCgroup = true" /etc/containerd/config.toml
  else
     sudo sed -i '/plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc.options.*/a SystemdCgroup = true' /etc/containerd/config.toml
  fi
fi

sudo systemctl daemon-reload
sudo systemctl enable --now containerd
sudo systemctl restart containerd

echo "#Install nerdctl ......"
wget -c https://github.com/containerd/nerdctl/releases/download/v${NERDCTL_VER}/nerdctl-${NERDCTL_VER}-linux-${ARCH}.tar.gz -qO - | sudo tar xvz -C /usr/local/bin

#You may skip buildkit installation if you don't need to build container images.
echo "#Install buildkit ......"
wget -c https://github.com/moby/buildkit/releases/download/v${BUILDKIT_VER}/buildkit-v${BUILDKIT_VER}.linux-${ARCH}.tar.gz -qO - | sudo tar xvz -C /usr/local
sudo mkdir -p /etc/buildkit
cat <<EOF | sudo tee /etc/buildkit/buildkitd.toml
[worker.oci]
  enabled = false
[worker.containerd]
  enabled = true
  # namespace should be "k8s.io" for Kubernetes (including Rancher Desktop)
  namespace = "k8s.io"
EOF
sudo mkdir -p /usr/local/lib/systemd/system/buildkit.service.d
cat <<EOF | sudo tee /usr/local/lib/systemd/system/buildkit.service.d/http-proxy.conf
[Service]
Environment="HTTP_PROXY=${http_proxy}"
Environment="HTTPS_PROXY=${https_proxy}"
Environment="NO_PROXY=10.96.0.1,10.96.0.0/12,10.0.0.0/8,svc,svc.cluster.local,${no_proxy}"
EOF
sudo -E wget https://raw.githubusercontent.com/moby/buildkit/v${BUILDKIT_VER}/examples/systemd/system/buildkit.service -qO /usr/local/lib/systemd/system/buildkit.service
sudo -E wget https://raw.githubusercontent.com/moby/buildkit/v${BUILDKIT_VER}/examples/systemd/system/buildkit.socket -qO /usr/local/lib/systemd/system/buildkit.socket
sudo systemctl daemon-reload
sudo systemctl enable --now buildkit
sudo systemctl restart buildkit
}

function _install_k8s_comp () {
  echo "# Install crictl ......"
  wget -c "https://github.com/kubernetes-sigs/cri-tools/releases/download/v${CRICTL_VER}/crictl-v${CRICTL_VER}-linux-${ARCH}.tar.gz" -qO - | sudo tar xvz -C /usr/local/bin

  echo "# Install kubeadm, kubelet ......"
  pushd /usr/local/bin
  sudo -E curl -L --remote-name-all https://dl.k8s.io/release/v${K8S_VER}/bin/linux/${ARCH}/{kubeadm,kubelet}
  sudo chmod +x {kubeadm,kubelet}
  popd
  RELEASE_VERSION="v0.16.2"
  curl -sSL "https://raw.githubusercontent.com/kubernetes/release/${RELEASE_VERSION}/cmd/krel/templates/latest/kubelet/kubelet.service" | sed "s:/usr/bin:/usr/local/bin:g" | sudo tee /usr/local/lib/systemd/system/kubelet.service
  sudo mkdir -p /usr/local/lib/systemd/system/kubelet.service.d
  curl -sSL "https://raw.githubusercontent.com/kubernetes/release/${RELEASE_VERSION}/cmd/krel/templates/latest/kubeadm/10-kubeadm.conf" | sed "s:/usr/bin:/usr/local/bin:g" | sudo tee /usr/local/lib/systemd/system/kubelet.service.d/10-kubeadm.conf
  sudo systemctl enable --now kubelet

  echo "#Install kubectl ......"
  curl -LO https://dl.k8s.io/release/v${K8S_VER}/bin/linux/${ARCH}/kubectl
  sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
  rm -f kubectl

  echo "#Install helm ......"
  wget -c "https://get.helm.sh/helm-v${HELM_VER}-linux-${ARCH}.tar.gz" -qO - | tar xvz -C /tmp
  sudo mv /tmp/linux-${ARCH}/helm /usr/local/bin/helm
}

function _find_k8s_pod_network () {
  if [ "x${NIC_CIDR}" == "x" ]; then
    interface=$(ip route | awk '/default/ { print $5 }')
    NIC_CIDR=$(ip addr show "$interface" | awk '/inet / { print $2 }')
    if [ "x${APISERVER_ADDR}" == "x" ]; then
      APISERVER_ADDR=$(echo ${NIC_CIDR} | cut -d'/' -f1)
    fi
  fi
  if [ "x${APISERVER_ADDR}" == "x" ]; then
    interface=$(ip route | awk '/default/ { print $5 }')
    APISERVER_ADDR=$(ip addr show "$interface" | awk '/inet / { print $2 }' | cut -d'/' -f1)
  fi
}

function _install_cni_calico() {
  echo "#Install Calico CNI ......"
  kubectl create -f "https://raw.githubusercontent.com/projectcalico/calico/v${CALICO_VER}/manifests/tigera-operator.yaml"
cat <<EOF | kubectl create -f -
# This section includes base Calico installation configuration.
# For more information, see: https://docs.tigera.io/calico/latest/reference/installation/api#operator.tigera.io/v1.Installation
apiVersion: operator.tigera.io/v1
kind: Installation
metadata:
  name: default
spec:
  # Configures Calico networking.
  calicoNetwork:
    ipPools:
    - name: default-ipv4-ippool
      blockSize: 26
      cidr: ${POD_CIDR}
      encapsulation: VXLANCrossSubnet
      natOutgoing: Enabled
      nodeSelector: all()
    nodeAddressAutodetectionV4:
      cidrs: ["${NIC_CIDR}"]
---
# This section configures the Calico API server.
# For more information, see: https://docs.tigera.io/calico/latest/reference/installation/api#operator.tigera.io/v1.APIServer
apiVersion: operator.tigera.io/v1
kind: APIServer
metadata:
  name: default
spec: {}
EOF
}

function _setup_k8s_master() {
  echo "# Initialize k8s master node ......"
  _find_k8s_pod_network
  sudo -E kubeadm init --pod-network-cidr "${POD_CIDR}" --apiserver-advertise-address ${APISERVER_ADDR} --token abcdef.0123456789abcdef --token-ttl 0

  echo "# copy kubeconfig to user home directory ......"
  mkdir -p $HOME/.kube
  sudo cp -f /etc/kubernetes/admin.conf $HOME/.kube/config
  sudo chown $(id -u):$(id -g) $HOME/.kube/config

  echo "# install kubectl completion ......"
  _install_pkg bash-completion
  kubectl completion bash | sudo tee /etc/bash_completion.d/kubectl > /dev/null
  sudo chmod a+r /etc/bash_completion.d/kubectl

  echo "# instal CNI plugin ......"
  _install_cni_calico
  echo "Sleep 10s for waiting for CNI ready"
  sleep 10
  kubectl get node -owide
  
  # save kubeadm join command
  echo "K8s master node is ready"
  echo "To join more K8s worker node, please run 'APISERVER_ADDR=${APISERVER_ADDR} $0 -a install_k8s_worker' on your worker nodes if necessary."
  echo "If you only has one K8s node, please run $0 -a k8s_master_untaint on your master node."
}

function install_k8s_master() {
  _install_k8s_cri
  _install_k8s_comp
  _setup_k8s_master
}

function install_k8s_worker() {
  if [ "x${APISERVER_ADDR}" == "x" ]; then
     echo "Error: Missing APISERVER_ADDR env viriable. Please specify it."
     exit 1
  else
    _install_k8s_cri
    _install_k8s_comp
    echo "# Join k8s worker node to master node ......"
    sudo -E kubeadm join ${APISERVER_ADDR}:6443 --token abcdef.0123456789abcdef --discovery-token-unsafe-skip-ca-verification
  fi
}

function k8s_reset() {
  sudo kubeadm reset
  echo "Please manually reset iptables/ipvs if necessary"
}

function k8s_master_untaint() {
  kubectl taint nodes --all node-role.kubernetes.io/control-plane-
  kubectl label nodes --all node.kubernetes.io/exclude-from-external-load-balancers-
}

OS=$(_get_os_distro)
case $OS in
  unknown)
    echo "Unknown Linux"
    exit 1
    ;;
  other)
    echo "Unsupported linux distribution"
    exit 1
    ;;
esac

function usage() {
    echo "Usage: $0 [ -a | --action ] <action> [ options ]"
    echo "Available actions:"
    echo "    install_docker: install latest docker engine community version"
    echo "    uninstall_docker: uninstall docker"
    echo "    install_k8s_master: install K8s master node, must run on k8s master node"
    echo "    install_k8s_worker: install K8s worker node, must run on k8s worker node"
    echo "    k8s_reset: reset k8s node, must run on k8s woker node first, then run on k8s mster node"
    echo "    k8s_master_untaint: untaint mater node for pod scheduling, must run on k8s m8s master node"
    echo "Available options:"
    echo "    -d --debug: turn on debug"
    echo "    -h --help: show usage"
}

options=$(getopt -o "a:dh" -l "action:,debug,help" -- "$@")
if [ $? -ne 0 ]; then
  echo "Error parsing options"
  usage
  exit 1
fi

eval set -- "$options"
while true; do
  case "$1" in
    -a|--action)
      action=$2
      shift 2
      ;;
    -d|--debug)
      debug=True
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      break
      ;;
    *)
      echo "Invalid option $1"
      usage
      exit 1
      ;;
  esac
done

if [ -z $action ]; then usage; exit 1; fi

if [[ $debug == "True" ]]; then set -x; fi
set -e
$action
set +ex
