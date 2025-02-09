#!/bin/bash
set -eu

if [ "$(id -u)" -ne 0 ]; then
  echo "You need to run with sudo"
  exit 1
fi

if ! grep -Ewq 'ID=(debian|ubuntu)' /etc/os-release; then
  echo "This script is meant to be ran on Debian/Ubuntu based systems"
  exit 1
fi

apt-get update && apt-get install -y jq apt-transport-https curl

curl -s https://pastebin.com/raw/v2BtJJC0 | dos2unix >/usr/local/bin/apt-fast
chmod +x /usr/local/bin/apt-fast

# Set up containerd requirements
cat <<-EOF >/etc/modules-load.d/containerd.conf
overlay
br_netfilter
EOF
modprobe overlay && modprobe br_netfilter

# Setup required sysctl params, these persist across reboots.
echo "Setting up kernel params..."
cat <<-EOF | tee /etc/sysctl.d/99-kubernetes-cri.conf
net.bridge.bridge-nf-call-iptables  = 1
net.ipv4.ip_forward                 = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF
sysctl --system

# Fetch and install latest containerd version
echo "Installing containerd..."
PLATFORM=$(arch | sed 's/aarch64/arm64/; s/x86_64/amd64/')
CONTAINERD_VERSION=$(curl -s https://api.github.com/repos/containerd/containerd/releases/latest | jq -r '.tag_name')
CONTAINERD_VERSION=${CONTAINERD_VERSION#v}
curl -sJLO "https://github.com/containerd/containerd/releases/download/v${CONTAINERD_VERSION}/containerd-${CONTAINERD_VERSION}-linux-${PLATFORM}.tar.gz"
tar xvf "containerd-${CONTAINERD_VERSION}-linux-${PLATFORM}.tar.gz" -C /usr/local

# Configure containerd
mkdir -p /etc/containerd
cat <<-TOML | tee /etc/containerd/config.toml
version = 2
[plugins]
  [plugins."io.containerd.grpc.v1.cri"]
    [plugins."io.containerd.grpc.v1.cri".containerd]
      discard_unpacked_layers = true
      [plugins."io.containerd.grpc.v1.cri".containerd.runtimes]
        [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc]
          runtime_type = "io.containerd.runc.v2"
          [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc.options]
            SystemdCgroup = true
TOML

echo "Installing runc..."
RUNC_VERSION=$(curl -s https://api.github.com/repos/opencontainers/runc/releases/latest | jq -r '.tag_name')
curl -sJLO "https://github.com/opencontainers/runc/releases/download/${RUNC_VERSION}/runc.${PLATFORM}"
install -m 755 "runc.${PLATFORM}" /usr/local/sbin/runc

# Restart containerd
curl -sJLO https://raw.githubusercontent.com/containerd/containerd/main/containerd.service
mv containerd.service /usr/lib/systemd/system/
systemctl daemon-reload
systemctl enable --now containerd

ln -s /etc/apparmor.d/runc /etc/apparmor.d/disable/
apparmor_parser -R /etc/apparmor.d/runc

# Setup kubernetes components
echo "Installing k8s components..."
KUBEVERSION=$(curl -s https://api.github.com/repos/kubernetes/kubernetes/releases/latest | jq -r '.tag_name')
KUBEVERSION=${KUBEVERSION%.*}

cat <<EOF >/etc/modules-load.d/k8s.conf
br_netfilter
EOF

curl -fsSL "https://pkgs.k8s.io/core:/stable:/${KUBEVERSION}/deb/Release.key" |
  gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/${KUBEVERSION}/deb/ /" |
  tee /etc/apt/sources.list.d/kubernetes.list

apt-get update && apt-fast install -y kubelet kubeadm kubectl
apt-mark hold kubelet kubeadm kubectl

# Disable swap as kubelet doesn't like it
swapoff -a && sed -i '/swap/ s/^/#/' /etc/fstab

crictl config --set runtime-endpoint=unix:///run/containerd/containerd.sock

echo "Installing k9s..."
curl -s https://pastebin.com/raw/KsYgLfYw | dos2unix | bash
echo "done."

echo "Upgrading system packages..."
apt-fast upgrade -y
echo

echo "Next steps:"
echo "  - Run sudo kubeadm init on the control plane to initialize the cluster and generate the \$KUBECONFIG"
echo "  - Test the kubectl client after setting up \$KUBECONFIG to confirm API server connectivity"
echo "  - Once you confirm that kubectl is working OK, install a network add-on"
echo "  - use sudo kubeadm join ... to add worker nodes to the cluster, where you will have set up \$KUBECONFIG as well"
echo
echo "Good luck"
