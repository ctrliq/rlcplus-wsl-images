# rlcplus-wsl-images

Builds and hosts the official `.wsl` images for **RLC+ (Rocky Linux Plus, CIQ)**,
for submission to and ongoing maintenance in Microsoft's WSL distribution
manifest (`microsoft/WSL` → `distributions/DistributionInfo.json`).

This repo produces the manifest entries currently named `CIQ_RLCPlus-9` and
`CIQ_RLCPlus-10` upstream (originally merged as `RLCPlus-9`/`RLCPlus-10`,
renamed for clearer vendor attribution). Built artifact filenames in this
repo's releases stay `RLCPlus-*` - only the upstream manifest's `Name`/
`FriendlyName` fields changed, not the files themselves. The separate
community `RockyLinux-9`/`RockyLinux-10` entries are expected to be owned and
maintained by RESF using their existing `dl.rockylinux.org` builds - this repo
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
  usr/share/wsl/ciq-rlcplus-logo.ico   # real CIQ artwork, in place
build/
  build.sh                      # Assembles rootfs + overlay -> .wsl tarball
.github/workflows/
  build-release.yml             # CI: fetches the source qcow2, builds both
                                 # arches, cuts a GitHub Release
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

Upstream status: merged into `microsoft/WSL` master on 2026-10-02 (PR #41323),
reformatted 2026-10-08 (PR #41841), renamed to `CIQ_RLCPlus-*` as of PR #41919
(pending review as of this writing).

## Maintenance

This is an ongoing obligation, not a one-time submission. A maintenance cycle
is **triggered by CIQ publishing a new RLC+ GenericCloud qcow2** - a point
release (e.g. 9.9, 10.3) or an out-of-band respin for a significant CVE - not
by a fixed calendar schedule. Watch for new releases at the GenericCloud qcow2
source and re-run the cycle below whenever one drops for a version this repo
tracks.

### The cycle, each time

1. **Build.** Either run `.github/workflows/build-release.yml` via
   `workflow_dispatch` with the new qcow2 URLs and a fresh build tag, or run
   `build/build.sh` manually per the steps below if doing it by hand.
2. **Spot-check.** A full from-scratch boot test isn't necessary for every
   routine point release now that the packaging approach itself is proven
   twice over - a structural check is enough day-to-day:
   ```bash
   tar -tzf <new-file>.wsl | grep -E "wsl-distribution.conf$|wsl.conf$|oobe.sh$|ciq-rlcplus-logo.ico$|fstab.orig-cloud-image$"
   ```
   Reserve a full real-hardware boot test for anything that touches
   `build.sh`, the overlay files, or a jump between major OS versions -
   routine point-release rebuilds of an already-proven combination don't need
   the full ceremony every time.
3. **Cut a new GitHub Release**, new tag (e.g. `v20270115`), new build-tagged
   filenames, matching `.CHECKSUM`s. Never reuse or overwrite a prior tag's
   assets - see Versioning below for why.
4. **Update the upstream manifest.** New PR against `microsoft/WSL`, same
   fork/branch pattern used for the original submission and the later
   rename - new URLs, new hashes, nothing else touched. Run
   `validate-modern.py --compare-with-branch origin/master` locally before
   opening the PR.
5. **Leave the old release in place** on this repo (don't delete it) until
   the new manifest PR is confirmed merged, in case a rollback is ever needed.

## Why the build fixes things RESF's existing Rocky `.wsl` image doesn't

Inspecting RESF's current `Rocky-9-WSL-Base` image surfaced two gaps this repo
corrects from the start:

- **Branding**: RESF's build still ships `fedora-logo.ico` and an
  OOBE script literally titled "The Fedora WSL out of box experience script" -
  left over from the shared upstream tooling it was adapted from.
- **Unmasked units**: `NetworkManager.service`,
  `NetworkManager-wait-online.service`, and `tmp.mount` are still enabled in
  RESF's image. Microsoft's own WSL packaging guidance calls these out as
  units that typically need masking, since WSL manages networking itself.
  `build.sh` masks all three by symlinking them to `/dev/null` under
  `etc/systemd/system/`.

A third issue surfaced during our own testing, specific to building from a
**cloud image** rather than a minimal rootfs:

- **cloud-init**: GenericCloud images ship with cloud-init enabled, expecting
  a datasource (metadata service or NoCloud seed) that WSL doesn't provide.
  Left as-is, `oobe.sh` correctly detects cloud-init and defers user creation
  to it - but cloud-init then hangs forever waiting for a datasource that
  never appears, and no user ever gets created. `build.sh` masks
  `cloud-init.service`, `cloud-init-local.service`, `cloud-config.service`,
  `cloud-final.service`, and `cloud-init-network.service` so `oobe.sh`'s own
  first-run logic runs instead.
- **fstab**: the cloud image's `/etc/fstab` references disks/labels that
  don't exist under WSL, causing `mount -a` to fail on every boot. `build.sh`
  backs up the original to `/etc/fstab.orig-cloud-image` and replaces the live
  `/etc/fstab` with an empty, commented stub.

## Versioning / release convention

Every release is tagged and every asset filename is version-pinned -
**never publish or reference a floating "latest" filename**. The
`DistributionInfo.json` manifest entry pins an exact URL + SHA256 hash; if
that URL's contents ever change without the manifest being updated in lockstep,
every future `wsl --install` for these distros silently breaks with a hash
mismatch until someone notices and files a fix PR.

Asset naming: `RLCPlus-<major>-WSL-<version>-<build_tag>.<arch>.wsl`
e.g. `RLCPlus-9-WSL-9-20260812.0.x86_64.wsl`

Each release also gets a `.CHECKSUM` file (sha256sum output) alongside the
image.

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
add/update the `CIQ_RLCPlus-9`/`CIQ_RLCPlus-10` entries in a PR against
`microsoft/WSL`'s `distributions/DistributionInfo.json`, following the
existing entry as a structural template. The separate community
`RockyLinux-9`/`RockyLinux-10` entries are expected in the same manifest,
owned and maintained by RESF.
