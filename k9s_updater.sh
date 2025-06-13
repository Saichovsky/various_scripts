#!/bin/bash
# Installs or updates the k9s Kubernetes client tool on your host

set -eu

update_available() {
  # Extract version components using parameter expansion
  local version1=${1#v}
  local version2=${2#v}

  IFS='.' read -r major1 minor1 patch1 <<<"$version1"
  IFS='.' read -r major2 minor2 patch2 <<<"$version2"

  # Compare major versions
  if ((major1 < major2)); then
    return 0 # true
  elif ((major1 > major2)); then
    return 1 # false
  fi

  # Compare minor versions
  if ((minor1 < minor2)); then
    return 0 # true
  elif ((minor1 > minor2)); then
    return 1 # false
  fi

  # Compare patch versions
  if ((patch1 < patch2)); then
    return 0 # true
  elif ((patch1 > patch2)); then
    return 1 # false
  fi

  return 1 # false (versions are equal)
}

# Use this if k9s is not installed, otherwise get the current version
C_VER=0.0.1
BINFILE=/usr/local/bin/k9s
if command -v k9s >/dev/null; then
  C_VER=$(k9s version -s | awk '/^Version/ {print $NF}')
  BINFILE=$(command -v k9s)
fi

# Fetch the latest release version and platform
L_VER=$(curl -s https://api.github.com/repos/derailed/k9s/releases/latest | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p')
PLATFORM=$(uname -m | sed 's/x86_64/amd64/; s/aarch64/arm64/')

if update_available "$C_VER" "$L_VER"; then
  ARCHIVE="k9s_$(uname)_${PLATFORM}.tar.gz"
  cd /tmp
  [[ "$C_VER" == "0.0.1" ]] && UPDATE_MSG="" || UPDATE_MSG="the newer "
  echo "Downloading and installing ${UPDATE_MSG}k9s ${L_VER}..."
  curl -LJO --fail "https://github.com/derailed/k9s/releases/download/${L_VER}/${ARCHIVE}" &&
    tar xzf "$ARCHIVE" k9s && sudo install -o root -g root -m 0755 k9s "$BINFILE"
  rm -fr k9s*
  echo "Done."
else
  echo "You have the latest version of k9s [$C_VER]"
fi
