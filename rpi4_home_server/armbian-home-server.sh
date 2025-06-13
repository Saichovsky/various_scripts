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

  if [[ -r /etc/armbian-release ]]; then
    eval "$(grep -w ^BOARD /etc/armbian-release)"
  else
    echo "Could not read required release file"
    exit 1
  fi
}

# Check conditions for script execution
prechecks

# Install Apt-fast
if command -v apt-fast >/dev/null; then
  RERUN=1
else
  curl -s https://raw.githubusercontent.com/Saichovsky/various_scripts/refs/heads/master/apt-fast \
    -o /usr/local/bin/apt-fast && chmod +x /usr/local/bin/apt-fast
fi

# Install k9s
[[ "$RERUN" == "1" ]] || {
  curl -s https://raw.githubusercontent.com/Saichovsky/various_scripts/refs/heads/master/k9s_updater.sh \
    -o /usr/local/bin/update_k9s && chmod +x /usr/local/bin/update_k9s
}
update_k9s

# Fix broken systemd service
[[ "$RERUN" == "1" ]] || {
  OVERRIDE_DIR="/etc/systemd/system/systemd-networkd-wait-online.service.d"
  OVERRIDE_FILE="$OVERRIDE_DIR/override.conf"

  mkdir -p "$OVERRIDE_DIR"
  cat >"$OVERRIDE_FILE" <<EOF
[Service]
ExecStart=
ExecStart=/lib/systemd/systemd-networkd-wait-online --any
EOF

  systemctl daemon-reload

  # Optionally, show status to confirm
  echo "Override created at $OVERRIDE_FILE"
}

# Rename host
[[ "$RERUN" == "1" ]] || {
  OLD_HOSTNAME=$(hostname)
  NEW_HOSTNAME="home-server-$BOARD"
  hostnamectl set-hostname "$NEW_HOSTNAME"
  sed -i "s/$OLD_HOSTNAME/$NEW_HOSTNAME/g" /etc/hosts
}

# Enable NTP client
[[ "$RERUN" == "1" ]] || sed -i 's/^#NTP=$/NTP=ke.pool.ntp.org/' /etc/systemd/timesyncd.conf

# Update /etc/issue with the host IP for ease of identification for SSH access
[ ! -f /usr/local/bin/update-issue.sh ] &&
  {
    curl -s https://raw.githubusercontent.com/Saichovsky/various_scripts/refs/heads/master/rpi4_home_server/armbian-update-issue.sh \
      -o /usr/local/bin/update-issue.sh && chmod 755 /usr/local/bin/update-issue.sh

    # Install update-issue script as a systemd service
    cat <<EOF >/etc/systemd/system/update-issue.service
[Unit]
Description=Update /etc/issue with host IP address
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/update-issue.sh

[Install]
WantedBy=multi-user.target
EOF

    systemctl enable update-issue && systemctl daemon-reload
  }

# Install required tools and packages
yes | apt-fast install -y ca-certificates apt-transport-https gnupg git jq yq fzf
test -d /etc/apt/keyrings || install -m 0755 -d /etc/apt/keyrings
[[ -f /etc/apt/keyrings/docker.asc ]] || {
  curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc
}

KUBEVERSION=$(curl -s https://api.github.com/repos/kubernetes/kubernetes/releases/latest | jq -r '.tag_name | gsub("\\.[0-9]+$"; "")')
curl -fsSL "https://pkgs.k8s.io/core:/stable:/${KUBEVERSION}/deb/Release.key" | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
cat <<EOF >/etc/apt/sources.list.d/docker.list
deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian \
  $(awk -F '=' '/^VERSION_CODENAME/ {print $2}' /etc/os-release) stable
EOF
chmod 644 /etc/apt/keyrings/kubernetes-apt-keyring.gpg
cat <<EOF >/etc/apt/sources.list.d/kubernetes.list
deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/${KUBEVERSION}/deb/ /
EOF
chmod 644 /etc/apt/sources.list.d/{docker,kubernetes}.list
apt-get update && apt-fast install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin kubectl

# Install kubectx and kubens
RELEASE_STRING="$(uname | tr '[:upper:]' '[:lower:]')_$(arch | sed 's/aarch64/arm64/')"
curl -s 'https://api.github.com/repos/ahmetb/kubectx/releases/latest' |
  jq -r --arg rel "${RELEASE_STRING}" '.assets[].browser_download_url | select(contains($rel))' |
  aria2c --allow-overwrite=true -i-
find . -maxdepth 1 -type f -name "kube*.tar.gz" -exec tar xvzf {} --exclude=LICENSE -C /usr/local/bin/ \; &&
  rm -fr kube*.tar.gz

# Install kubectl-ai
curl -sSL https://raw.githubusercontent.com/GoogleCloudPlatform/kubectl-ai/main/install.sh | bash

# Install helm
echo "Installing helm..."
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Install and set up kind
echo "Installing kind..."
RELEASE_STRING="$(uname | tr '[:upper:]' '[:lower:]')-$(dpkg --print-architecture)"
KIND_LATEST=$(curl -s 'https://api.github.com/repos/kubernetes-sigs/kind/releases/latest' | jq -r '.tag_name')
KIND_LOCAL=/usr/local/bin/kind
curl -Lo "${KIND_LOCAL}" "https://kind.sigs.k8s.io/dl/${KIND_LATEST}/kind-${RELEASE_STRING}"
chmod +x "${KIND_LOCAL}"

# Set up the kind cluster
echo "Setting up kind cluster..."
mkdir -p /data/kind-storage
cat <<EOF | kind create cluster --config=-
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: home-cluster
nodes:
- role: control-plane
  extraMounts:
  - hostPath: /data/kind-storage
    containerPath: /data
- role: worker
  extraMounts:
  - hostPath: /data/kind-storage
    containerPath: /data
- role: worker
  extraMounts:
  - hostPath: /data/kind-storage
    containerPath: /data
EOF

cat <<EOF | kubectl apply -f-
---
apiVersion: v1
kind: PersistentVolume
metadata:
  name: shared-pv
  labels:
    type: local
spec:
  accessModes:
    - ReadWriteMany
  capacity:
    storage: 3Gi
  storageClassName: shared-storage
  persistentVolumeReclaimPolicy: Retain
  hostPath:
    path: "/data/"
  nodeAffinity:
    required:
      nodeSelectorTerms:
      - matchExpressions:
        - key: node-role.kubernetes.io/control-plane
          operator: DoesNotExist
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: shared-pvc
spec:
  accessModes:
    - ReadWriteMany
  resources:
    requests:
      storage: 3Gi
  storageClassName: shared-storage
EOF
# Use helm to install home assistant and pi-hole
# helm repo add home-assistant https://amcgeek.github.io/home-assistant-helm
# helm repo add pi-hole https://pi-hole.github.io/
# helm install home-assistant home-assistant/home-assistant
# helm install pi-hole pi-hole/pi-hole

# Upgrade system
apt-get update && apt-fast upgrade -y && apt autoremove -y
