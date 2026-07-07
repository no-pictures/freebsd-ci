#!/bin/sh
# Run a POSIX shell script inside the guest over SSH.
#
# The script comes from the arguments, or from stdin when no argument
# is given.
# Unless -n is passed, the current directory is synchronized to
# /root/work first and the script starts there.
# tar carries the files because FreeBSD base ships no rsync, and the
# script is piped into sh because root's login shell is csh.
#
# Additional sync exclude patterns come from the space-separated
# FREEBSD_CI_SYNC_EXCLUDE environment variable.
#
# usage: run.sh [-n] [script]
#        run.sh [-n] < script-file
set -e
. "$(dirname "$0")/config.sh"

SYNC=yes
if [ "${1:-}" = "-n" ]; then
    SYNC=no
    shift
fi

if [ "$#" -gt 0 ]; then
    GUEST_SCRIPT="$*"
else
    GUEST_SCRIPT="$(cat)"
fi

if [ "${SYNC}" = "yes" ]; then
    set -- --exclude=.git
    for pattern in ${FREEBSD_CI_SYNC_EXCLUDE:-}; do
        set -- "$@" "--exclude=${pattern}"
    done
    tar "$@" -czf - . | ${VM_SSH} \
        'rm -rf /root/work && mkdir -p /root/work && tar -xzf - -C /root/work'
fi

{
    echo "set -e"
    echo "cd /root/work 2>/dev/null || cd /root"
    printf '%s\n' "${GUEST_SCRIPT}"
} | ${VM_SSH} sh -s
