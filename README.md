# rocky-wsl-images (RLC+)

Builds and hosts the official `.wsl` images for **RLC+ (Rocky Linux Plus, CIQ)**,
for submission to and ongoing maintenance in Microsoft's WSL distribution
manifest (`microsoft/WSL` → `distributions/DistributionInfo.json`).

This repo produces the `RLCPlus-9` and `RLCPlus-10` entries. The separate
community `RockyLinux-9`/`RockyLinux-10` entries are expected to be owned and
maintained by RESF using their existing `dl.rockylinux.org` builds — this repo
does not build those.

## Layout

```
overlay/                       # Files layered onto the base RLC+ rootfs
  etc/wsl.conf
  etc/wsl-distribution.conf.template
  usr/libexec/wsl/oobe.sh
  usr/lib/tmpfiles.d/wsl-setup.conf
  usr/share/pixmaps/            # TODO: add ciq-rlcplus-logo.ico here
build/
  build.sh                      # Assembles rootfs + overlay -> .wsl tarball
.github/workflows/
  build-release.yml             # CI: build both arches, cut a GitHub Release
```

## What still needs to be plugged in

1. **RLC+ rootfs source.** `build.sh` takes an already-extracted rootfs
   directory as input; it does not build one. Wire up whichever CIQ already
   uses internally — most likely either:
   - `docker export`/`podman export` from the RLC+ container image, or
   - loop-mounting the RLC+ GenericCloud qcow2 (`depot.ciq.com`) and tarring
     the filesystem
   Update the placeholder step in `.github/workflows/build-release.yml`
   accordingly.
2. **A real CIQ/RLC+ icon**, converted to `.ico`, dropped at
   `overlay/usr/share/pixmaps/ciq-rlcplus-logo.ico`. Until this exists, the
   build proceeds but the distro falls back to WSL's default icon (this is
   intentional — RESF's existing image shipped with a leftover Fedora icon by
   skipping this step, which we're not repeating).

## Why the build fixes two things RESF's existing Rocky `.wsl` image doesn't

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

## Manual build

```
./build/build.sh \
  --version 9 \
  --arch x86_64 \
  --rootfs /path/to/extracted-rlcplus-9-rootfs \
  --build-tag 20260806.0 \
  --out ./dist
```

## Next step after a release is cut

Take the release asset URL + the contents of the matching `.CHECKSUM` file and
add/update the `RockyLinuxPlus` (naming TBD, see internal discussion) entry in
a PR against `microsoft/WSL`'s `distributions/DistributionInfo.json`, following
the existing `AlmaLinux` entry as a structural template.
