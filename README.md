# rlcplus-wsl-images

Builds and hosts the official `.wsl` images for **RLC+ (Rocky Linux Plus, CIQ)**,
for submission to and ongoing maintenance in Microsoft's WSL distribution
manifest (`microsoft/WSL` → `distributions/DistributionInfo.json`).

This repo produces the `RLCPlus-9` and `RLCPlus-10` entries. The separate
community `RockyLinux-9`/`RockyLinux-10` entries are expected to be owned and
maintained by RESF using their existing `dl.rockylinux.org` builds — this repo
does not build those.

Naming convention for future CIQ WSL image repos, if other product lines are
ever added: `<product>-wsl-images` (e.g. a hypothetical `rlcpro9-wsl-images`).
Nothing beyond `rlcplus-wsl-images` is planned at this time.

## Layout

```
overlay/                       # Files layered onto the base RLC+ rootfs
  etc/wsl.conf
  etc/wsl-distribution.conf.template
  usr/libexec/wsl/oobe.sh
  usr/lib/tmpfiles.d/wsl-setup.conf
  usr/share/pixmaps/ciq-rlcplus-logo.ico   # real CIQ artwork, in place
build/
  build.sh                      # Assembles rootfs + overlay -> .wsl tarball
.github/workflows/
  build-release.yml             # CI: build both arches, cut a GitHub Release
                                 # (rootfs-fetch step is still a placeholder - see below)
```

## Status

All four combinations have been built and fully boot-tested on real hardware:

| | x86_64 | aarch64 |
|---|---|---|
| **RLC+ 9** | boot-tested on real hardware | boot-tested on real hardware (Snapdragon X2 Plus) |
| **RLC+ 10** | boot-tested on real hardware | boot-tested on real hardware (Snapdragon X2 Plus) |

Verified working across all four: OOBE user creation, passwordless sudo,
`NetworkManager` correctly masked with networking still functional, icon
renders correctly in Windows Terminal, `/etc/os-release` and `uname -a`
confirm correct distro identity and architecture.

## What still needs to be plugged in

1. **Automating the RLC+ rootfs source in CI.** The manual process is proven
   and documented below (`virt-tar-out` against the RLC+ GenericCloud qcow2).
   `.github/workflows/build-release.yml` still has this as a placeholder step
   — someone needs to wire up fetching the qcow2 from `depot.ciq.com` and
   running the same extraction inside the Actions runner so releases can be
   cut without a manual rocklab session each time.

## Why the build fixes things RESF's existing Rocky `.wsl` image doesn't

Inspecting RESF's current `Rocky-9-WSL-Base` image surfaced two gaps this repo
corrects from the start:

- **Branding**: RESF's build still ships `fedora-logo.ico` and an
  OOBE script literally titled "The Fedora WSL out of box experience script" —
  left over from the shared upstream tooling it was adapted from.
- **Unmasked units**: `NetworkManager.service`,
  `NetworkManager-wait-online.service`, and `tmp.mount` are still enabled in
  RESF's image. Microsoft's own WSL packaging guidance calls these out as
  units that typically need masking, since WSL manages networking itself.
  `build.sh` masks all three by symlinking them to `/dev/null` under
  `etc/systemd/system/`.

A third issue surfaced during our own testing, specific to building from a
**cloud image** rather than a minimal rootfs (RESF's base likely isn't a raw
cloud image the same way RLC+'s GenericCloud qcow2 is):

- **cloud-init**: GenericCloud images ship with cloud-init enabled, expecting
  a datasource (metadata service or NoCloud seed) that WSL doesn't provide.
  Left as-is, `oobe.sh` correctly detects cloud-init and defers user creation
  to it — but cloud-init then hangs forever waiting for a datasource that
  never appears, and no user ever gets created. `build.sh` masks
  `cloud-init.service`, `cloud-init-local.service`, `cloud-config.service`,
  `cloud-final.service`, and `cloud-init-network.service` so `oobe.sh`'s own
  first-run logic runs instead.
- **fstab**: the cloud image's `/etc/fstab` references disks/labels that
  don't exist under WSL, causing `mount -a` to fail on every boot. `build.sh`
  backs up the original to `/etc/fstab.orig-cloud-image` and replaces the live
  `/etc/fstab` with an empty, commented stub.

## Versioning / release convention

Every release is tagged and every asset filename is version-pinned —
**never publish or reference a floating "latest" filename**. The
`DistributionInfo.json` manifest entry pins an exact URL + SHA256 hash; if
that URL's contents ever change without the manifest being updated in lockstep,
every future `wsl --install RLCPlus-9` silently breaks with a hash mismatch
until someone notices and files a fix PR.

Asset naming: `RLCPlus-<major>-WSL-<version>-<build_tag>.<arch>.wsl`
e.g. `RLCPlus-9-WSL-9-20260806.0.x86_64.wsl`

Each release also gets a `.CHECKSUM` file (sha256sum output) alongside the
image, matching the pattern RESF already uses for their Rocky images.

## Manual build (proven working end-to-end)

```bash
# 1. Extract rootfs directly from the RLC+ GenericCloud qcow2 - no mounting,
#    no loop devices needed. Requires libguestfs-tools-c (virt-tar-out).
virt-tar-out -a RLC-Plus-9-<date>-GenericCloud-x86_64.qcow2 / rlc-plus-9-rootfs.tar

# 2. Unpack AS ROOT - this matters. The tarball preserves ownership info
#    (e.g. /etc/shadow) that a non-root `tar -x` will silently mangle.
mkdir -p ~/rlc-plus-9-rootfs
sudo tar -xf rlc-plus-9-rootfs.tar -C ~/rlc-plus-9-rootfs

# 3. Build (also as root, same ownership reasoning)
sudo ./build/build.sh \
  --version 9 \
  --arch x86_64 \
  --rootfs ~/rlc-plus-9-rootfs \
  --build-tag 20260806.0 \
  --out ./dist
```

Same process for `--version 10` and `--arch aarch64` - confirmed to work
identically across all four combinations. Note `virt-tar-out` produces a
plain `.tar`, not `.tar.gz`, despite what a lot of examples elsewhere assume -
use `tar -xf` (auto-detects), not `-xzf`.

**Architecture note:** building an aarch64 `.wsl` from an x86_64 host works
fine - `virt-tar-out` and `build.sh` only read/copy/repackage files, nothing
executes guest code, so no emulation is needed at build time. You'll need
real ARM64 hardware to actually *boot-test* the result, though - WSL2 doesn't
emulate a different CPU architecture from the one Windows is running on.

## Testing a built image

```powershell
wsl --install --from-file .\RLCPlus-9-WSL-9-<tag>.x86_64.wsl
```

If re-testing after a previous attempt, unregister first or you'll hit
`ERROR_ALREADY_EXISTS`:
```powershell
wsl --unregister RLCPlus-9
```

## Next step after a release is cut

Take the release asset URL + the contents of the matching `.CHECKSUM` file and
add/update the `RLCPlus-9`/`RLCPlus-10` entries in a PR against
`microsoft/WSL`'s `distributions/DistributionInfo.json`, following the
existing `AlmaLinux` entry as a structural template. The separate community
`RockyLinux-9`/`RockyLinux-10` entries are expected in the same manifest,
owned and maintained by RESF.
