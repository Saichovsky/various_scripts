#!/bin/sh
# Installs or updates the k9s Kubernetes client tool on your host

set -eu

update_available() {
  version1=${1#v}
  version2=${2#v}

  IFS=.
  set -- $version1
  major1=$1
  minor1=$2
  patch1=$3

  set -- $version2
  major2=$1
  minor2=$2
  patch2=$3

  if [ "$major1" -lt "$major2" ]; then
    return 0
  elif [ "$major1" -gt "$major2" ]; then
    return 1
  fi

  if [ "$minor1" -lt "$minor2" ]; then
    return 0
  elif [ "$minor1" -gt "$minor2" ]; then
    return 1
  fi

  if [ "$patch1" -lt "$patch2" ]; then
    return 0
  elif [ "$patch1" -gt "$patch2" ]; then
    return 1
  fi

  return 1
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
  if [ "$C_VER" = "0.0.1" ]; then
    UPDATE_MSG=""
  else
    UPDATE_MSG="the newer "
  fi
  echo "Downloading and installing ${UPDATE_MSG}k9s ${L_VER}..."
  curl -LJO --fail "https://github.com/derailed/k9s/releases/download/${L_VER}/${ARCHIVE}" &&
    tar xzf "$ARCHIVE" k9s && sudo install -o root -g root -m 0755 k9s "$BINFILE"
  rm -fr k9s*
  echo "Done."
else
  echo "You have the latest version of k9s [$C_VER]"
fi
