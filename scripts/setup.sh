#!/bin/sh
# Bring a FreeBSD VM up in one step: download and verify the image,
# create the work overlay, boot and provision SSH access.
set -e
SCRIPTS_DIR="$(cd "$(dirname "$0")" && pwd)"

sh "${SCRIPTS_DIR}/fetch-image.sh"
sh "${SCRIPTS_DIR}/provision.sh"
