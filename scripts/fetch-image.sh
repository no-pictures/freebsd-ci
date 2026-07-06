#!/bin/sh
# Download the FreeBSD BASIC-CI image, verify it against the pinned
# checksum and prepare the copy-on-write work image.
set -e
. "$(dirname "$0")/config.sh"

URL="$(image_url)"
SHA256="$(image_sha256)"
if [ -z "${URL}" ] || [ -z "${SHA256}" ]; then
    echo "No image known for ${FREEBSD_VERSION} in ${IMAGES_CONF}." >&2
    exit 1
fi
ARCHIVE="${CACHE_DIR}/$(basename "${URL}")"
RAW_IMAGE="${ARCHIVE%.xz}"

mkdir -p "${CACHE_DIR}"

if [ ! -f "${ARCHIVE}" ]; then
    echo "Downloading ${URL}"
    curl -sS --retry 3 -C - -o "${ARCHIVE}" "${URL}"
fi

echo "${SHA256}  ${ARCHIVE}" | sha256sum -c -

if [ ! -f "${BASE_IMAGE}" ]; then
    echo "Unpacking and converting $(basename "${ARCHIVE}")"
    unxz -kf "${ARCHIVE}"
    qemu-img convert -f raw -O qcow2 "${RAW_IMAGE}" "${BASE_IMAGE}"
    rm "${RAW_IMAGE}"
fi

if [ ! -f "${WORK_IMAGE}" ]; then
    qemu-img create -q -f qcow2 -F qcow2 \
        -b "${BASE_IMAGE}" "${WORK_IMAGE}" "${WORK_IMAGE_SIZE}"
    echo "Created ${WORK_IMAGE} (${WORK_IMAGE_SIZE})"
fi

echo "Image ready: ${WORK_IMAGE}"
