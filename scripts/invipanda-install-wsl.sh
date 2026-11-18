#!/usr/bin/env bash
# Installs a packaged InviPanda into /opt/invipanda inside a WSL2 distro.
# Run inside the distro as root:
#   bash invipanda-install-wsl.sh /mnt/c/path/to/invipanda-linux-x86_64.tar.gz
set -euo pipefail
TARBALL=${1:?usage: invipanda-install-wsl.sh <invipanda-linux-x86_64.tar.gz>}
mkdir -p /opt
rm -rf /opt/invipanda
tar -C /opt -xzf "$TARBALL"
/opt/invipanda/invipanda version
echo "installed: /opt/invipanda/invipanda"
