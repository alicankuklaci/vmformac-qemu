# QEMU engine build

`scripts/qemu/build.sh` builds the QEMU and swtpm binaries that VMForMac uses for
Windows 11 on ARM guests, every library they need, and a Secure Boot capable edk2
firmware with a Microsoft-keys variable store, from pinned source archives. Nothing from
Homebrew or any other non-system prefix is used, at build time or at run time.

## What is built

| Component | Version | Role |
|---|---|---|
| QEMU | 11.1.2 | `qemu-system-aarch64` (aarch64-softmmu, hvf) |
| GLib | 2.90.1 | runtime library (LGPL-2.1+) |
| proxy-libintl | 0.5 | GLib's libintl stand-in (instead of gettext) |
| PCRE2 | 10.49 | GLib dependency (8-bit, no JIT) |
| libffi | 3.8.0 | GLib dependency |
| pixman | 0.46.4 | QEMU display/VNC |
| libslirp | 4.9.5 | user-mode networking (`-netdev user`) |
| spice-protocol | 0.14.5 | headers only; enables `-chardev qemu-vdagent` |
| dtc (libfdt) | 1.8.1 | QEMU internal subproject, linked statically |
| swtpm | 0.10.2 | `swtpm` TPM 2.0 emulator (`-tpmdev emulator`); only the daemon is built |
| libtpms | 0.10.2 | swtpm's TPM implementation (`--with-openssl --with-tpm2`) |
| OpenSSL | 3.5.9 (LTS) | `libcrypto.3.dylib` for libtpms/swtpm (`no-apps no-module no-legacy no-engine`, OPENSSLDIR `/var/empty`) |
| json-glib | 1.10.8 | swtpm dependency |
| edk2 | edk2-stable202408 (`roms/edk2` of the QEMU tarball) | ArmVirtQemu AARCH64 rebuilt with `SECURE_BOOT_ENABLE=TRUE` |
| libtasn1 | 4.21.0 | needed only by swtpm's configure; not shipped |
| GNU m4 / autoconf / automake / libtool | 1.4.21 / 2.73 / 1.19 / 2.6.2 | build-time only (autoreconf for libtpms/swtpm); libtool installed as `glibtool` |
| ACPICA iasl | 20260930 | build-time only (edk2 ASL) |
| LLVM (official macOS arm64 binary) | 22.1.8 | build-time only: clang + lld + llvm-ar + llvm-objcopy for edk2's CLANGDWARF toolchain |
| virt-firmware + cryptography, cffi, pycparser, typing_extensions | 26.10 + 50.0.2, 2.0.0, 2.23, 4.16.0 | build-time only (`virt-fw-vars`, in `build/venv`) |
| pkgconf | 3.0.10 | build-time only (`build/tools`) |
| meson / ninja / setuptools / wheel / tomli | 1.11.2 / 1.13.2 / 82.0.1 / 0.48.0 / 2.5.0 | build-time only (`build/venv`) |

URLs, SHA-256 hashes and where each hash came from are in `versions.env`.
macOS system libraries (`libz`, `libiconv`, `libbz2`, frameworks) are used from
`/usr/lib` and `/System`.

QEMU is configured with `--target-list=aarch64-softmmu --enable-hvf --enable-slirp
--enable-vnc --disable-cocoa --disable-sdl --disable-gtk --disable-opengl
--disable-docs --disable-guest-agent --disable-tools`, plus `--enable-fdt=internal
--enable-spice-protocol --enable-tpm --enable-pixman --disable-vmnet --disable-curses
--disable-rust --disable-vnc-sasl --disable-auth-pam --disable-download`.

### Why edk2 is rebuilt

QEMU's prebuilt `pc-bios/edk2-aarch64-code.fd` is built without
`SECURE_BOOT_ENABLE` (see QEMU's `roms/edk2-build.config`): booted with an
enrolled variable store it reports no `SecureBoot`/`SetupMode` variables. The
build therefore compiles the same edk2 sources (shipped in the QEMU tarball with
all submodules) with QEMU's `[build.armvirt.aa64]` options plus
`SECURE_BOOT_ENABLE=TRUE`, using edk2's `CLANGDWARF` toolchain. Apple's toolchain
has no ELF linker, hence the pinned LLVM release (only `bin/{clang,lld,llvm-ar,
llvm-objcopy}` and `lib/clang` are extracted into `build/tools/llvm`). The images
are padded to QEMU's 64 MiB pflash size.

### Branding

- Boot logo: `branding/vmformac-logo.png` (resources/icon/AppIcon.svg rasterized
  at 200x200 by `xtask-icon`; regenerate with `branding/make-logo.sh`, the
  `xtask-icon` test `boot_logo_matches_app_icon` fails when it is stale) is
  converted by `branding/png2bmp.py` (stdlib only, run with the venv's
  `python3 -I`) into a 24-bit BMP, transparent pixels on black, which replaces
  `MdeModulePkg/Logo/Logo.bmp` in the unpacked tree. ArmVirtQemu's LogoDxe
  embeds it as the HII image `BootLogoLib` draws centred during boot. The PNG is
  committed (and part of the payload) so the payload builds without Rust.
- Strings: `--pcd PcdFirmwareVendor=LVMForMac BIOS\0`, plus
  `PcdFirmwareVersionString` and `PcdFirmwareReleaseDateString` from
  `VMFORMAC_FIRMWARE_VERSION` / `VMFORMAC_FIRMWARE_DATE` in `versions.env`
  (UEFI shell `ver`, the boot banner, and the SMBIOS type 0 fallback of
  `SmbiosPlatformDxe`). The app passes the same values as `-smbios type=0`
  (QEMU's own type 0 otherwise wins) and `-smbios
  type=1,manufacturer=VMForMac,product=VMForMac Virtual Machine`
  (`vmf_qemu::cmdline::FIRMWARE_*`, a unit test compares them with `versions.env`).
- The edk2 stage key includes the PCD strings and a hash of the PNG and
  `png2bmp.py`, so changing either rebuilds the firmware (and the vars stage
  after it).

### Microsoft-keys variable store

`edk2-aarch64-vars-ms.fd` is generated from the empty vars template of that build
with `virt-fw-vars`: PK = a "VMForMac Platform Key" certificate generated at build
time (`--enroll-generate`; the private key is discarded, so PK/KEK cannot be
changed by anyone); KEK = Microsoft Corporation KEK CA 2011 + KEK 2K CA 2023 (+ the
PK cert); db = Microsoft Windows Production PCA 2011, Windows UEFI CA 2023,
Microsoft Corporation UEFI CA 2011, Microsoft UEFI CA 2023; Secure Boot enabled.
The certificates are downloaded from Microsoft's pkiops URLs (the targets of the
fwlinks in "Windows Secure Boot Key Creation and Management Guidance") and pinned
by SHA-256. Because the PK is random, the file differs between clean builds.

## How to run

```sh
scripts/qemu/build.sh            # resumes completed stages (build/work/stamps)
scripts/qemu/build.sh --clean    # wipe build/ except build/cache, then build
scripts/qemu/check-deps.sh       # verify build/qemu-dist only links allowed paths
```

Requirements: Apple Silicon Mac, Xcode command line tools (clang, make,
install_name_tool, codesign, and `/usr/bin/python3` >= 3.9, used only to create
`build/venv`; override with `HOST_PYTHON=...`), and network access for the first
download (none when run from the source payload, whose `sources/` seeds the cache).

Stages are skipped on rerun only if their stamp in `build/work/stamps` matches a
key over the stage's source versions + SHA-256s, its `patches/<dir>` contents and
the previous stage's key, so editing `versions.env` or a patch rebuilds that
stage and everything after it. `qemu-dist` and `qemu-src` are always reassembled.

How isolation works:

- `PATH` is reset to `build/venv/bin:build/tools/bin` plus system directories, and
  compiler/linker/pkg-config environment variables are cleared.
- pkg-config is pkgconf built from source; `PKG_CONFIG_LIBDIR` points only at
  `build/prefix/lib/pkgconfig`, so Homebrew `.pc` files are never seen.
- Downloads go to `build/cache/` and are checked against `versions.env`; a mismatch
  aborts. Python wheels are installed with `pip --no-index` from that cache.
- GLib's proxy-libintl wrap is fed from the cache; meson runs with
  `--wrap-mode=nodownload` and QEMU with `--disable-download`.

## Outputs

- `build/qemu-dist/` — relocatable runtime:
  `bin/qemu-system-aarch64`, `bin/swtpm`, `lib/*.dylib` (install names `@rpath/…`, binary rpath
  `@executable_path/../lib`, dylib rpath `@loader_path`), `share/qemu/` (keymaps,
  `edk2-aarch64-code.fd` (Secure Boot build), `edk2-aarch64-vars.fd` (empty vars
  template), `edk2-aarch64-vars-ms.fd` (Microsoft keys, Secure Boot on), `edk2-licenses.txt`,
  `efi-*.rom` NIC option ROMs, `vgabios*.bin`; firmware for other guest
  architectures and the `firmware/*.json` descriptors are left out). QEMU finds
  `share/qemu` relative to its executable, so the tree can be moved anywhere. Binaries are ad-hoc signed,
  QEMU with `com.apple.security.hypervisor`; the app build re-signs them.
  `share/licenses/` holds the licence texts. The app bundles take only part of
  `share/qemu/` (no `vgabios*.bin`, one ROM, one keymap, no empty vars
  template) and all of `share/licenses/` except `seabios-vgabios/`: see the
  allow-list in `scripts/stage-qemu-data.sh`.
- `build/qemu-src/` — corresponding source for the GPL source repository:
  `README.md` (from `payload-README.md`), `sources/` (every archive),
  `SHA256SUMS`, `scripts/qemu/` (build scripts, `versions.env`, `patches/`) and
  `licenses/<component>/`. `scripts/qemu/build.sh` can be run from its root.

## Patches

`patches/<component>/*.patch` are applied with `patch -p1` after unpacking
(component directory names: `qemu`, `glib`, `pcre2`, `libffi`, `pixman`,
`libslirp`, `spice-protocol`, `qemu-dtc`, `pkgconf`, `m4`, `autoconf`, `automake`,
`libtool`, `openssl`, `libtasn1`, `json-glib`, `libtpms`, `swtpm`, `acpica`,
`qemu-edk2` (the QEMU tarball unpacked again for its `roms/edk2`)).

- `qemu/0001-file-posix-compressed-files-are-data-on-macOS.patch`: on macOS,
  `lseek(SEEK_DATA)` fails with `ENXIO` at every offset of an HFS+/APFS-compressed
  file, which `block/file-posix.c` took for a trailing hole, so the whole file
  read as zeros. Apple's installer compresses the app bundle, so the pflash
  firmware in `Contents/Resources/qemu` came up empty and the guest never started.
  For a `UF_COMPRESSED` file that `ENXIO` now means "no information" (data).

## Build time

Apple M2 (8 cores), macOS 26.5.1, Apple clang 21, venv from `/usr/bin/python3`
3.9.6, 2026-10-21, `build.sh --clean` with a warm `build/cache`: **1210 s wall
(~20 min)**; per stage: venv 8 s, pkgconf 7 s, pcre2 24 s, libffi 17 s, glib 74 s,
pixman 9 s, libslirp 6 s, spice-protocol 2 s, QEMU 247 s, m4 156 s, autoconf 6 s,
automake 10 s, libtool 28 s, OpenSSL 116 s, libtasn1 45 s, json-glib 7 s,
libtpms 94 s, swtpm 24 s, LLVM extract 108 s, ACPICA 8 s, edk2 163 s,
virt-firmware 2 s, vars-ms 3 s, dist 5 s, payload 2 s
(`build/work/build-times.txt`). A no-change rerun takes a few seconds (dist +
payload only). The first download adds the archives (~215 MB) and the LLVM
release (1.5 GB).

Output sizes: `build/qemu-dist` 108 MB on disk (three 64 MB edk2 images, mostly
padding, plus a 29 MB QEMU binary and ~11 MB of dylibs), `build/qemu-src` 216 MB.

## Guest tools (Windows on ARM)

Researched 2026-10-21. Nothing here is built or bundled: guest media is
downloaded at runtime, checksum-verified, and only attached to the VM; nothing
from it runs on the host.

### virtio-win drivers (used)

`virtio-win-0.1.302.iso`, pinned in `vmf_core::catalog::VIRTIO_WIN`:
<https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/archive-virtio/virtio-win-0.1.302-1/virtio-win-0.1.302.iso>,
877 373 440 bytes, SHA-256
`303f7ae40dad495d6ae474fdc571df58958a4dbc5c37a522d80f9a203867949d`.

ARM64 builds on the ISO (each under `<driver>/w10/ARM64`, `w11/ARM64` and, except
viofs, `2k25/ARM64`): Balloon, NetKVM, pvpanic, viofs, viogpudo, vioinput,
viomem, viorng, vioscsi, vioserial, viosock, viostor. There is **no** ARM64 build of
qemupciserial, fwcfg/qemufwcfg, qxl/qxldod, smbus or sriov, and the ISO's
`virtio-win-guest-tools.exe`, `virtio-win-gt-*.msi` and `guest-agent/qemu-ga-*.msi`
are x86/x64 only. The answer file loads NetKVM, viogpudo, vioserial and Balloon
from `w11\ARM64` during Setup; at first logon it runs `VMForMac Driver Setup.cmd`
from the "VMForMac Driver" disk (below), which installs every `*\w11\ARM64\*.inf`;
the ignored test `unattend::tests::drivers_manifest_matches_iso_layout`
mounts the cached ISO read-only and checks those paths.

### VMForMac Driver disk

The virtio-win ISO is attached unmodified, so every driver keeps its Microsoft
signature. What the user sees as "VMForMac Driver" is a second, small medium
built by `vmf_qemu::driver_medium`: a FAT image labelled `VMFMDRIVER` (FAT labels
are at most 11 upper-case characters) holding `VMForMac Driver Setup.cmd` and
`VMForMac Driver.txt` (no autorun.inf or desktop.ini). It is the same for every
VM, built deterministically and cached as
`<cache>/guest-tools/vmformac-driver-<hash>.img` (FNV-1a of the image, so a
changed file set gets a new name), and attached read-only as a removable USB
disk (`-drive if=none,id=vmfdrv0,readonly=on,...` + `usb-storage,removable=on`)
whenever the virtio-win ISO is. The script finds the virtio-win drive by
`NetKVM\w11\ARM64`, runs `pnputil /add-driver <driver>\w11\ARM64\*.inf
/subdirs /install` for every driver (idempotent), elevates itself when
double-clicked without admin rights, and logs to
`%ProgramFiles%\VMForMac\logs\driver-setup.log`. Further guest tools are added to
`driver_medium::files()`.

### SPICE guest agent for the clipboard (none usable)

The clipboard needs `vdagent.exe`/`vdservice.exe` in the guest (QEMU side:
`-chardev qemu-vdagent` + virtio-serial). No open-source ARM64 build is available as
a verifiable release:

- spice-space.org: <https://www.spice-space.org/download/windows/vdagent/vdagent-win-0.10.0/>
  (latest, 2020) has only `spice-vdagent-x64/x86-0.10.0.msi` and x64/x86 zips.
  The upstream project (gitlab.freedesktop.org/spice/win32/vd_agent) publishes no
  releases with binaries.
- virtio-win 0.1.302: no SPICE agent; its guest tools are x86/x64 only.
- UTM: `https://getutm.app/downloads/utm-guest-tools-latest.iso` redirects to
  <https://github.com/utmapp/qemu/releases/download/v10.0.2-utm/utm-guest-tools-0.1.271.iso>
  (127 084 544 bytes, SHA-256
  `65b6a69b392ee01dd314c10f3dad9ebbf9c4160be43f5f0dd6bb715944d9095b`, GitHub
  release asset digest, verified locally). It holds virtio-win drivers and one NSIS
  installer `utm-guest-tools-0.1.271.exe` that embeds `vdagent_arm64\vdagent.exe`
  (see <https://github.com/utmapp/spice-nsis>, `win-guest-tools.nsis`). That ARM64
  agent has no published source tag or build recipe: spice-nsis's Makefile marks
  the ARM64 vdagent as "TODO: not available", and `utmapp/vd_agent` is the
  Linux/macOS agent. The installer also bundles Microsoft's proprietary
  `vc_redist.arm64.exe`. The ISO's own `Autounattend.xml` writes LabConfig
  TPM/Secure Boot bypasses. So it is not used.
- Fedora's mingw packages (`mingw-spice-vdagent`) have no aarch64 Windows target.

The clipboard is therefore off for Windows VMs (`vmf_qemu::guest_tools`): no
vdagent chardev/virtserialport on the command line, and the UI shows the note
`windows.clipboard_unavailable`.

### Display

viogpudo (virtio-gpu display-only driver) exists for ARM64. Checked with this
QEMU build:

- `-device ramfb,id=ramfb0 -device virtio-gpu-pci,id=gpu0` with
  `-vnc unix:<sock>,display=<id>` binds VNC to either head (`query-vnc-servers`
  reports the display). Several `-vnc ...,id=<n>,display=<id>` servers can run at
  once.
- The firmware (edk2 VirtioGpuDxe and QemuRamfbDxe) draws on both heads.
- Windows 11 ARM64 Setup without viogpudo draws only on ramfb. The virtio-gpu
  head shows QEMU's "Display output is not active." placeholder at 1280x800 and
  refuses `SetDesktopSize`. So ramfb must stay for Boot Manager and Setup
  (virtio-gpu's GOP is blit-only, with no linear framebuffer).

QEMU always runs two VNC servers, `<uuid>.vnc` (`id=vnc0,display=ramfb0`) and
`<uuid>-gpu.vnc` (`id=vnc1,display=gpu0`). The VM window holds both and shows the
virtio-gpu head only while it is live: its last frame is real content rather than
QEMU's placeholder (black, with gray `0xaaaaaa` text only in the middle 16-px text
row; see `vmf_qemu::display_head`). Every reset goes back to ramfb. The VM menu
offers Automatic / Boot Display / Desktop Display, and a manual choice holds until
the next reset. Resolution following needs an installed guest with viogpudo and is
verified in Task 13.
