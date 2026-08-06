#!/usr/bin/bash

# The Rocky Linux Plus (RLC+) WSL out of box experience script.
#
# This command runs the first time the user opens an interactive shell if
# `cloud-init` is not enabled.
#
# A non-zero exit code indicates to WSL that setup failed.

set -ueo pipefail

DEFAULT_USER_ID=1000

if systemctl is-enabled cloud-init.service > /dev/null 2>&1; then
  echo 'cloud-init is enabled, skipping user account creation. Waiting for cloud-init to finish.'
  cloud-init status --wait > /dev/null 2>&1
  exit 0
fi

echo 'Please create a default user account. The username does not need to match your Windows username.'
echo 'For more information visit: https://aka.ms/wslusers'

if getent passwd $DEFAULT_USER_ID > /dev/null ; then
  echo 'User account already exists, skipping creation'
  exit 0
fi

# Prompt for the username
read -r -p 'Enter new UNIX username: ' username

# Create the user
/usr/sbin/useradd -m -G wheel --uid $DEFAULT_USER_ID "$username"

cat > /etc/sudoers.d/wsluser << EOF
# Ensure the WSL initial user can use sudo without a password.
#
# Since the user is in the wheel group, this file can be removed
# if you wish to require a password for sudo. Be sure to set a
# user password before doing so with 'sudo passwd $username'!
$username ALL=(ALL) NOPASSWD: ALL
EOF

echo 'Your user has been created, is included in the wheel group, and can use sudo without a password.'
echo "To set a password for your user, run 'sudo passwd $username'"
