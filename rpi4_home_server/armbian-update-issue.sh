#!/bin/sh
# This shell script updates /etc/issue with the host's IP address to make it
# easier to identify the machine for SSH Access. The location of this file
# is /usr/local/bin where the script is executed as a systemd oneshot service

ISSUE=/etc/issue
ISSUE_ORIG=/etc/issue.orig

# Back up the original /etc/issue file if not backed up
[ ! -f "$ISSUE_ORIG" ] && cp "$ISSUE" "$ISSUE_ORIG"

# Get the IP address of the host by using the default route
IP_ADDRESS=$(routel | awk '/^default/ {print $3}')

# Output original /etc/issue content, checking for version upgrades
extract_version() { grep -oP '(?<=Armbian )\S+ +\w+' "$1"; }
LATEST_VERSION="$(extract_version $ISSUE)"
OLD_VERSION="$(extract_version $ISSUE_ORIG)"

# Update backup file if versions differ
if [ "$OLD_VERSION" != "$LATEST_VERSION" ]; then
  sed -i "s/$OLD_VERSION/$LATEST_VERSION/" "$ISSUE_ORIG"
fi

# Write clear screen codes, then original issue content, then IP address
{
  # Clear screen and move cursor home
  printf '\e[2J\e[H'

  # Output original /etc/issue content
  cat "$ISSUE_ORIG"

  # Append IP address line
  printf "IP Address: \e[1;37m%s\e[0m\n\n" "$IP_ADDRESS"
} >"$ISSUE"
