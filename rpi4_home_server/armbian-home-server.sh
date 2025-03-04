#!/bin/bash

set -eu
RERUN=0

prechecks() {
  if [ "$(id -u)" -ne 0 ]; then
    echo "You need to run with sudo"
    exit 1
  fi

  if ! grep -Ewq 'ID=(debian|ubuntu)' /etc/os-release; then
    echo "This script is meant to be ran on Debian/Ubuntu based systems"
    exit 1
  fi

  if [ -f /run/.kube_setup ]; then
    echo "This script has already been executed on this system"
    exit 1
  fi
}

# Check conditions for script execution
prechecks

# Install Apt-fast
command -v apt-fast >/dev/null && RERUN=1 || {
  curl -s https://pastebin.com/raw/v2BtJJC0 | tr -d '\r' >/usr/local/bin/apt-fast &&
    chmod +x /usr/local/bin/apt-fast
}

# Install k9s
[[ "$RERUN" == "1" ]] || {
  curl -s https://pastebin.com/raw/KsYgLfYw | tr -d '\r' >/usr/local/bin/update_k9s &&
    chmod +x /usr/local/bin/update_k9s
}
update_k9s

# Fix broken systemd service
[[ "$RERUN" == "1" ]] || {
  sed -i 's|^ExecStart=/lib/systemd/systemd-networkd-wait-online|ExecStart=/bin/sh -c '\''/lib/systemd/systemd-networkd-wait-online --any'\''|' \
    /lib/systemd/system/systemd-networkd-wait-online.service && systemctl daemon-reload
}

# Rename host
[[ "$RERUN" == "1" ]] || {
  OLD_HOSTNAME=$(hostname)
  NEW_HOSTNAME="home-server"
  hostnamectl set-hostname "$NEW_HOSTNAME"
  sed -i "s/$OLD_HOSTNAME/$NEW_HOSTNAME/g" /etc/hosts
}

# Upgrade system
apt-get update && apt-fast upgrade -y && apt autoremove -y

# Install required tools and packages
yes | apt-fast install -y ca-certificates apt-transport-https gnupg git jq fzf
test -d /etc/apt/keyrings || install -m 0755 -d /etc/apt/keyrings
[[ -f /etc/apt/keyrings/docker.asc ]] || {
  curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc
}

KUBEVERSION=$(curl -s https://api.github.com/repos/kubernetes/kubernetes/releases/latest | jq -r '.tag_name | gsub("\\.[0-9]+$"; "")')
curl -fsSL "https://pkgs.k8s.io/core:/stable:/${KUBEVERSION}/deb/Release.key" | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
cat <<EOF >/etc/apt/sources.list.d/docker.list
deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable
EOF
chmod 644 /etc/apt/keyrings/kubernetes-apt-keyring.gpg
cat <<EOF >/etc/apt/sources.list.d/kubernetes.list
deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/${KUBEVERSION}/deb/ /
EOF
chmod 644 /etc/apt/sources.list.d/{docker,kubernetes}.list
apt-get update && apt-fast install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin kubectl

# Install kubectx and kubens
RELEASE_STRING="$(uname | tr 'A-Z' 'a-z')-$(dpkg --print-architecture)"
curl -s 'https://api.github.com/repos/ahmetb/kubectx/releases/latest' |
  jq -r --arg rel "${RELEASE_STRING/-/_}" '.assets[].browser_download_url | select(contains($rel))' |
  aria2c --allow-overwrite=true -i-
find . -maxdepth 1 -type f -name "kube*.tar.gz" -exec tar xvzf {} --exclude=LICENSE -C /usr/local/bin/ \; &&
  rm -fr kube*.tar.gz

# Install helm
echo "Installing helm..."
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Install and set up kind
echo "Installing kind..."
KIND_LATEST=$(curl -s 'https://api.github.com/repos/kubernetes-sigs/kind/releases/latest' | jq -r '.tag_name')
KIND_LOCAL=/usr/local/bin/kind
curl -Lo "${KIND_LOCAL}" "https://kind.sigs.k8s.io/dl/${KIND_LATEST}/kind-${RELEASE_STRING}"
chmod +x "${KIND_LOCAL}"

# Set up kind cluster
echo "Setting up kind cluster..."
cat <<EOF | kind create cluster --config=-
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: home-cluster
nodes:
- role: control-plane
- role: worker
- role: worker
EOF

# Use helm to install home assistant and pi-hole
# helm repo add home-assistant https://amcgeek.github.io/home-assistant-helm
# helm repo add pi-hole https://pi-hole.github.io/
# helm install home-assistant home-assistant/home-assistant
# helm install pi-hole pi-hole/pi-hole
