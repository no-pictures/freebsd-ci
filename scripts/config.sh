# Shared configuration of the FreeBSD test VM scripts.
# Every script in this directory sources this file.
# All settings can be overridden through the environment.

SCRIPTS_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "${SCRIPTS_DIR}/.." && pwd)"

FREEBSD_VERSION="${FREEBSD_VERSION:-14.3-RELEASE}"
IMAGES_CONF="${IMAGES_CONF:-${REPO_DIR}/images.conf}"

CACHE_DIR="${FREEBSD_CI_CACHE:-${HOME}/.cache/freebsd-ci}"
BASE_IMAGE="${CACHE_DIR}/FreeBSD-${FREEBSD_VERSION}-amd64-BASIC-CI.qcow2"
WORK_IMAGE="${CACHE_DIR}/work.qcow2"
WORK_IMAGE_SIZE="${WORK_IMAGE_SIZE:-40G}"

VM_MEMORY_MB="${VM_MEMORY_MB:-4096}"
VM_CPUS="${VM_CPUS:-$(nproc)}"
SSH_PORT="${SSH_PORT:-2222}"
SSH_KEY="${SSH_KEY:-${CACHE_DIR}/id_ed25519}"
PID_FILE="${CACHE_DIR}/qemu.pid"
SERIAL_SOCKET="${CACHE_DIR}/serial.sock"
SERIAL_LOG="${CACHE_DIR}/serial.log"
MONITOR_SOCKET="${CACHE_DIR}/mon.sock"
KNOWN_HOSTS="${CACHE_DIR}/known_hosts"

SSH_OPTS="-p ${SSH_PORT} -i ${SSH_KEY} \
    -o UserKnownHostsFile=${KNOWN_HOSTS} \
    -o StrictHostKeyChecking=accept-new \
    -o ConnectTimeout=15"
VM_SSH="ssh ${SSH_OPTS} root@127.0.0.1"

image_url() {
    awk -v v="${FREEBSD_VERSION}" \
        '$1 == v { print $2 }' "${IMAGES_CONF}"
}

image_sha256() {
    awk -v v="${FREEBSD_VERSION}" \
        '$1 == v { print $3 }' "${IMAGES_CONF}"
}

qemu_accel() {
    # KVM when the device is usable, TCG emulation otherwise
    if [ -w /dev/kvm ]; then
        echo "kvm -cpu host"
    else
        echo "tcg,thread=multi -cpu max"
    fi
}

start_qemu() {
    # the serial console stays interactive through the unix socket
    # and is mirrored into a logfile for headless debugging
    qemu-system-x86_64 \
        -machine pc -accel $(qemu_accel) \
        -smp "${VM_CPUS}" -m "${VM_MEMORY_MB}" \
        -display none -vga std \
        -monitor "unix:${MONITOR_SOCKET},server,nowait" \
        -chardev "socket,id=serial0,path=${SERIAL_SOCKET},server=on,wait=off,logfile=${SERIAL_LOG}" \
        -serial chardev:serial0 \
        -netdev "user,id=n0,hostfwd=tcp:127.0.0.1:${SSH_PORT}-:22" \
        -device virtio-net-pci,netdev=n0 \
        -drive "if=virtio,file=${WORK_IMAGE},format=qcow2" \
        -rtc base=utc \
        -daemonize -pidfile "${PID_FILE}"
}
