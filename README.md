# FreeBSD CI

Reusable GitHub Actions for testing on FreeBSD.
Boot a real FreeBSD VM on a stock Linux runner, get root SSH access within minutes, and run your test commands inside the guest — without maintaining custom VM images.

The tooling builds on the official BASIC-CI images that FreeBSD release engineering publishes for every release.
These images boot with a serial console, DHCP and growfs, and their sshd accepts root with an empty password on the first boot, which makes them provisionable over plain SSH.
Provisioning installs a per-run SSH key and closes the empty-password access in the same breath; the forwarded SSH port only ever binds to 127.0.0.1.

Each action is a composite action under [`.github/actions/`](.github/actions/).
A repository consumes one with `uses: <owner>/freebsd-ci/.github/actions/<name>@<ref>`.
During bring-up, pin `@main`; once the interface is stable we cut a `v1` tag plus a moving major tag, and consumers pin `@v1`.

## Actions

### `setup-vm`

Installs QEMU on the runner, downloads the BASIC-CI image for the requested release, verifies it against a checksum pinned in [`images.conf`](images.conf), boots the VM and provisions key-based root SSH.
The image archive is cached between runs with `actions/cache`.

```yaml
- uses: <owner>/freebsd-ci/.github/actions/setup-vm@main
  with:
    version: 14.4-RELEASE      # any release listed in images.conf
    memory-mb: "4096"
    cpus: "2"
    disk-size: 40G             # the guest grows its root on first boot
    ssh-port: "2222"
```

### `run`

Runs a POSIX shell script inside the guest over SSH, by default after synchronizing the workspace to `/root/work`.
The script is piped into `sh -s` on the guest, because root's login shell on FreeBSD is csh and command strings passed as SSH arguments would be parsed by it.

```yaml
- uses: <owner>/freebsd-ci/.github/actions/run@main
  with:
    run: |
      freebsd-version
      make test
```

## Plain script usage

The same scripts work outside GitHub Actions on any Linux host with QEMU, for local development or other CI systems.

```sh
export FREEBSD_VERSION=14.4-RELEASE
sh scripts/fetch-image.sh    # download, verify, unpack, create overlay
sh scripts/provision.sh      # first boot, install the SSH key
sh scripts/vm.sh ssh freebsd-version
sh scripts/vm.sh down
```

State lives in `~/.cache/freebsd-ci` and is disposable; deleting `work.qcow2` and re-running the fetch and provision scripts recreates the guest from the verified image.
One cache directory holds one work image, so parallel VMs of different releases on the same host need a distinct `FREEBSD_CI_CACHE` and `SSH_PORT` per release.

## Supported releases

`images.conf` maps a release to its download URL and the SHA256 of the image archive.
Supported releases download from download.freebsd.org, end-of-life releases from the FreeBSD archive server.
The archive server only speaks plain HTTP, which is one of the reasons every image is verified against a pinned checksum.
Adding a release is a one-line change carrying the URL and checksum.

## Performance expectations

The scripts use KVM whenever /dev/kvm is usable and fall back to TCG software emulation otherwise.
GitHub runners provide KVM after the udev rule that the setup-vm action applies, and a full VM job runs in a few minutes there.
Under the TCG fallback, boots take a few minutes and compute-heavy suites run several times slower than native, which still suits functional testing of FreeBSD-specific interfaces such as jails, ZFS and rctl.
The first boot always adds one automatic reboot after growing the root filesystem.

## Debugging

The serial console is mirrored into `~/.cache/freebsd-ci/serial.log`, which the provisioning script prints when SSH never comes up.
`scripts/vm.sh console` attaches to the live serial console through a unix socket, which requires socat.
The QEMU monitor socket answers a screendump command with a screenshot of the VGA display, for the rare case that even the serial console stays quiet:

```sh
printf 'screendump /tmp/screen.png -f png\n' \
    | socat - UNIX-CONNECT:${HOME}/.cache/freebsd-ci/mon.sock
```
