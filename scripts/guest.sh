#!/bin/sh
# Common guest preparation verbs, each idempotent and runnable in any
# order once the VM is provisioned.
#
# usage: guest.sh pkg-repo <latest|quarterly>
#        guest.sh pkg-install <package> [package ...]
#        guest.sh kld <module> [module ...]
#        guest.sh tunable <name=value> [name=value ...]
#        guest.sh fdescfs
#        guest.sh zpool <name> <size>
#        guest.sh mirror-pkg-cache <host-directory>
set -e
. "$(dirname "$0")/config.sh"

# root's login shell on FreeBSD is csh, so every command sequence is
# piped into a POSIX shell on the guest
guest_sh() {
    ${VM_SSH} sh -s
}

wait_for_ssh() {
    i=0
    while [ "$i" -lt 120 ]; do
        if ${VM_SSH} -o ConnectTimeout=5 -o BatchMode=yes true \
                2>/dev/null; then
            return 0
        fi
        i=$((i + 1))
        sleep 5
    done
    echo "Guest did not come back within 10 minutes." >&2
    return 1
}

VERB="${1:-}"
[ $# -gt 0 ] && shift

case "${VERB}" in
    pkg-repo)
        BRANCH="${1:?usage: guest.sh pkg-repo <latest|quarterly>}"
        guest_sh <<GUEST
set -e
mkdir -p /usr/local/etc/pkg/repos
cat > /usr/local/etc/pkg/repos/FreeBSD.conf <<'REPO'
FreeBSD: { url: "pkg+https://pkg.FreeBSD.org/\${ABI}/${BRANCH}" }
REPO
GUEST
        ;;
    pkg-install)
        [ $# -gt 0 ] || { echo "no packages given" >&2; exit 1; }
        printf 'set -e\nenv ASSUME_ALWAYS_YES=yes pkg bootstrap -f > /dev/null\npkg update -f > /dev/null\npkg install -y %s\n' "$*" \
            | guest_sh
        ;;
    kld)
        [ $# -gt 0 ] || { echo "no modules given" >&2; exit 1; }
        for module in "$@"; do
            printf 'kldload %s 2>/dev/null || true\ngrep -q "^%s_load=" /boot/loader.conf 2>/dev/null || printf "%s_load=\\"YES\\"\\n" >> /boot/loader.conf\n' \
                "${module}" "${module}" "${module}" | guest_sh
        done
        ;;
    tunable)
        [ $# -gt 0 ] || { echo "no tunables given" >&2; exit 1; }
        NEED_REBOOT=no
        for pair in "$@"; do
            name="${pair%%=*}"
            value="${pair#*=}"
            printf 'grep -q "^%s=" /boot/loader.conf 2>/dev/null || echo "%s=%s" >> /boot/loader.conf\n' \
                "${name}" "${name}" "${value}" | guest_sh
            current="$(${VM_SSH} "sysctl -n ${name}" 2>/dev/null || true)"
            if [ "${current}" != "${value}" ]; then
                NEED_REBOOT=yes
            fi
        done
        if [ "${NEED_REBOOT}" = "yes" ]; then
            echo "Rebooting the guest to apply boot-time tunables."
            ${VM_SSH} 'shutdown -r now' 2>/dev/null || true
            sleep 30
            wait_for_ssh
        fi
        ;;
    fdescfs)
        guest_sh <<'GUEST'
set -e
grep -q fdescfs /etc/fstab || echo "fdesc /dev/fd fdescfs rw 0 0" >> /etc/fstab
mount | grep -q "/dev/fd" || mount -t fdescfs null /dev/fd
GUEST
        ;;
    zpool)
        NAME="${1:?usage: guest.sh zpool <name> <size>}"
        SIZE="${2:?usage: guest.sh zpool <name> <size>}"
        guest_sh <<GUEST
set -e
kldload zfs 2>/dev/null || true
sysrc -q zfs_enable=YES > /dev/null
if ! zpool list ${NAME} > /dev/null 2>&1; then
    mkdir -p /pools
    truncate -s ${SIZE} /pools/${NAME}.img
    zpool create -m /.${NAME} ${NAME} /pools/${NAME}.img
    zfs set compression=lz4 ${NAME}
fi
zpool list ${NAME}
GUEST
        # file-backed pools are not always reimported at boot
        guest_sh <<GUEST
set -e
touch /etc/rc.local
chmod +x /etc/rc.local
grep -q "zpool import -d /pools ${NAME}" /etc/rc.local || \
    echo "zpool list ${NAME} > /dev/null 2>&1 || zpool import -d /pools ${NAME}" >> /etc/rc.local
GUEST
        ;;
    mirror-pkg-cache)
        TARGET="${1:?usage: guest.sh mirror-pkg-cache <host-directory>}"
        mkdir -p "${TARGET}"
        # tar carries the files because the guest may not have rsync
        ${VM_SSH} 'tar -C /var/cache/pkg -czf - .' \
            | tar -xzf - -C "${TARGET}"
        ;;
    *)
        echo "usage: $0 {pkg-repo|pkg-install|kld|tunable|fdescfs|zpool|mirror-pkg-cache} ..." >&2
        exit 1
        ;;
esac
