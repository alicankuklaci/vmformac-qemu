# VMForMac QEMU: corresponding source

This repository holds the complete corresponding source for the QEMU and swtpm
binaries, their libraries, the firmware and the ROMs that ship inside VMForMac.
They sit in `Contents/Helpers`, `Contents/Frameworks` and
`Contents/Resources/qemu` of `VMForMac.app` and run Windows 11 on ARM guests.
The repository also records how every one of those files was produced.

It exists to meet the source-code terms of the licences below:

- GNU GPL v2: QEMU, dtc and keycodemapdb inside QEMU, and the iPXE ROM.
- GNU LGPL v2.0/v2.1: GLib, proxy-libintl and JSON-GLib.
- GNU LGPL v3: the SeaBIOS VGA BIOS ROMs, only for the VMForMac builds that
  shipped them (with `qemu-11.1.2-r2`, see Releases). Later builds leave them out.

VMForMac's own code (the app, `vmfctl`, the VMForMac Agent) is not part of this
repository.

## Contents

- `SOURCES.md`: every source archive, with its version, upstream URL and SHA-256.
  `SHA256SUMS` holds the same hashes in `shasum -c` form.
- `sources/` (release assets, not in git): the unmodified upstream archives,
  byte for byte as downloaded and as used for the build. This includes the
  build-time tools (pkgconf, GNU m4/autoconf/automake/libtool, libtasn1, ACPICA,
  the meson/ninja/setuptools/wheel/tomli wheels, virt-firmware and its wheels)
  and the Microsoft Secure Boot certificates. Download the assets of the release
  that matches your VMForMac build into `sources/`, then check them with
  `cd sources && shasum -a 256 -c ../SHA256SUMS`.
- `scripts/qemu/build.sh`: the script that produced the shipped binaries. All
  configure and meson options are in it.
- `scripts/qemu/versions.env`: the version, URL and SHA-256 pin of every input,
  and where each hash was checked.
- `scripts/qemu/check-deps.sh`: checks that the runtime links only macOS
  system libraries and its own `lib/`.
- `scripts/qemu/patches/`: patches applied on top of upstream. There are two:
  `qemu/0001-file-posix-compressed-files-are-data-on-macOS.patch` (QEMU's
  `block/file-posix.c` reads HFS+/APFS-compressed files as data instead of
  as one trailing hole) and
  `libslirp/0001-udp-icmp-connect-sockets-for-the-macOS-App-Sandbox.patch`
  (libslirp `connect()`s the host UDP and ICMP sockets it opens for the guest,
  one UDP socket per guest source and destination, so replies reach it in the
  macOS App Sandbox without the `network.server` entitlement). No other
  upstream source file is changed.
- `scripts/qemu/branding/`: the VMForMac boot logo (`vmformac-logo.png`) and
  `png2bmp.py`, which turns it into the `Logo.bmp` that replaces edk2's TianoCore
  logo before the firmware is built. Apart from the patches above, that is the only
  change to any source tree.
- `scripts/qemu/README.md`: build details (output layout, timings, Secure Boot
  variable store).
- `licenses/<component>/`: the licence texts of each component. `COPYING` (GPL v2),
  `COPYING.LIB` (LGPL v2.1) and `COPYING.LGPLv3` (with the GPL v3 it refers to,
  `COPYING.GPLv3`; for the SeaBIOS VGA BIOS of earlier builds) are at the top
  level.

## Components and licences

| Component | Version | Licence | Shipped in VMForMac as | Source |
|---|---|---|---|---|
| QEMU | 11.1.2 | GPL-2.0-only (parts GPL-2.0-or-later, LGPL, BSD, MIT) | `Helpers/qemu-system-aarch64`, `Resources/qemu/keymaps` | `qemu-11.1.2.tar.xz` |
| dtc / libfdt | 1.8.1 | GPL-2.0-or-later OR BSD-2-Clause | statically linked into QEMU | `dtc-1.8.1.tar.xz` |
| keycodemapdb, berkeley-softfloat-3 | in the QEMU tarball | GPL-2.0-or-later OR BSD-3-Clause / BSD-3-Clause | compiled into QEMU | `qemu-11.1.2.tar.xz` (`subprojects/`) |
| iPXE EFI ROM | prebuilt by QEMU (`pc-bios/efi-virtio.rom`) | GPL-2.0-or-later (parts UBDL) | `Resources/qemu/efi-virtio.rom` (builds with `qemu-11.1.2-r2`: all `efi-*.rom`) | `qemu-11.1.2.tar.xz` (`roms/ipxe`, `roms/Makefile`) |
| SeaBIOS VGA BIOS | 1.17.0, prebuilt by QEMU (`pc-bios/vgabios*.bin`) | LGPL-3.0-only | not shipped any more (builds with `qemu-11.1.2-r2`: `Resources/qemu/vgabios*.bin`) | `qemu-11.1.2.tar.xz` (`roms/seabios`, `roms/config.vga-*`) |
| edk2 firmware | edk2-stable202408 (`roms/edk2` in the QEMU tarball) | BSD-2-Clause-Patent and others (incl. OpenSSL in CryptoPkg), see `edk2-licenses.txt` | `Resources/qemu/edk2-aarch64-code.fd`, `edk2-aarch64-vars-ms.fd` (builds with `qemu-11.1.2-r2` also `edk2-aarch64-vars.fd`) | `qemu-11.1.2.tar.xz` + `scripts/qemu/branding/` |
| GLib | 2.90.1 | LGPL-2.1-or-later | `Frameworks/libglib-2.0.0.dylib`, `libgobject-2.0.0.dylib`, `libgio-2.0.0.dylib`, `libgmodule-2.0.0.dylib` | `glib-2.90.1.tar.xz` |
| proxy-libintl | 0.5 | LGPL-2.0-or-later | `Frameworks/libintl.8.dylib` | `proxy-libintl-0.5.tar.gz` |
| JSON-GLib | 1.10.8 | LGPL-2.1-or-later | `Frameworks/libjson-glib-1.0.0.dylib` | `json-glib-1.10.8.tar.xz` |
| PCRE2 | 10.49 | BSD-3-Clause WITH PCRE2-exception | `Frameworks/libpcre2-8.0.dylib` | `pcre2-10.49.tar.bz2` |
| libffi | 3.8.0 | MIT | `Frameworks/libffi.8.dylib` | `libffi-3.8.0.tar.gz` |
| pixman | 0.46.4 | MIT | `Frameworks/libpixman-1.0.dylib` | `pixman-0.46.4.tar.xz` |
| libslirp | 4.9.5 | BSD-3-Clause | `Frameworks/libslirp.0.dylib` | `libslirp-v4.9.5.tar.gz` |
| spice-protocol | 0.14.5 | BSD-3-Clause | headers only (build time) | `spice-protocol-0.14.5.tar.xz` |
| swtpm | 0.10.2 | BSD-3-Clause | `Helpers/swtpm`, `Frameworks/libswtpm_libtpms.0.dylib` | `swtpm-0.10.2.tar.gz` |
| libtpms | 0.10.2 | BSD-3-Clause (and the TCG reference code licence, see LICENSE) | `Frameworks/libtpms.0.dylib` | `libtpms-0.10.2.tar.gz` |
| OpenSSL | 3.5.9 | Apache-2.0 | `Frameworks/libcrypto.3.dylib` | `openssl-3.5.9.tar.gz` |

QEMU's prebuilt iPXE ROM `efi-virtio.rom` is shipped unchanged from the QEMU
tarball's `pc-bios/`. Its source is the `roms/ipxe` tree of the same tarball,
and `roms/Makefile` rebuilds it. The build installs more of `pc-bios/` (the
other NICs' iPXE ROMs and SeaBIOS's `vgabios*.bin`), but VMForMac copies into
the app only the data files its QEMU command line opens: `edk2-aarch64-code.fd`,
`edk2-aarch64-vars-ms.fd`, `edk2-licenses.txt`, `efi-virtio.rom` and
`keymaps/en-us` (an allow-list in VMForMac's `scripts/stage-qemu-data.sh`).
Builds with `qemu-11.1.2-r2` shipped all of `share/qemu/`, including the
SeaBIOS VGA BIOS, whose source is `roms/seabios` (with `roms/config.vga-*`).

Nothing GPL or LGPL goes onto the guest driver disk ("VMForMac Driver"). It
holds VMForMac's own setup script and agent; the agent's notices are on that
disk. The virtio-win driver ISO is not distributed by VMForMac. The app
downloads it from fedorapeople.org, unchanged.

## Rebuilding

You need an Apple Silicon Mac with the Xcode command line tools
(`xcode-select --install`). Put the release assets into `sources/`, then run
this from the root of this repository:

```sh
scripts/qemu/build.sh
```

The archives in `sources/` seed `build/cache/`, and each one is checked against
`versions.env`. A mismatch stops the build. The only download left is the
official LLVM 22.1.8 macOS arm64 release (1.5 GB, pinned by SHA-256 in
`versions.env`), used as the compiler and ELF linker for the edk2 firmware.
Instead of using the release assets you can also let `build.sh` download each
archive from the upstream URL in `versions.env`. It verifies the same SHA-256.

QEMU is configured with:

```
--target-list=aarch64-softmmu --enable-hvf --enable-slirp --enable-vnc
--disable-cocoa --disable-sdl --disable-gtk --disable-opengl --disable-docs
--disable-guest-agent --disable-tools --enable-fdt=internal
--enable-spice-protocol --enable-tpm --enable-pixman --disable-vmnet
--disable-curses --disable-rust --disable-vnc-sasl --disable-auth-pam
--disable-werror --disable-download
```

The options of every library (GLib, JSON-GLib, pixman, libslirp, OpenSSL,
libtpms, swtpm and the rest) are in `scripts/qemu/build.sh`, next to the
`meson_build` / `autotools_build` call for each one.

The build produces:

- `build/qemu-dist/`: the relocatable runtime the app is bundled from, with
  `bin/qemu-system-aarch64`, `bin/swtpm`, `lib/*.dylib`, `share/qemu/` (the app
  takes only the files listed above) and `share/licenses/` (all but
  `seabios-vgabios/`). The dylibs have install names `@rpath/<name>`. The helpers
  look in `@executable_path/../lib`; the app changes that rpath to
  `@executable_path/../Frameworks`.
- `build/qemu-src/`: this repository's content again.

## Replacing a library or QEMU in VMForMac

The LGPL lets you use VMForMac with a modified GLib, proxy-libintl or JSON-GLib.
The GPL lets you run a modified QEMU. VMForMac is a signed, sandboxed app, so
after replacing a file you have to sign the bundle again yourself:

1. Build with your changes (edit the source in `build/work/src/<component>`
   or add a patch to `scripts/qemu/patches/<component>/`, then run
   `scripts/qemu/build.sh`).
2. Copy the app somewhere you can write to (for example
   `cp -R /Applications/VMForMac.app ~/VMForMac-custom.app`).
3. Replace the files. Libraries go in `Contents/Frameworks/` under the same name
   (e.g. `build/qemu-dist/lib/libglib-2.0.0.dylib` →
   `Contents/Frameworks/libglib-2.0.0.dylib`). QEMU or swtpm go in
   `Contents/Helpers/`; after copying one, run
   `install_name_tool -delete_rpath @executable_path/../lib -add_rpath @executable_path/../Frameworks <file>`.
   Firmware and ROMs go in `Contents/Resources/qemu/`.
4. Sign it again, from the inside out, with your own identity or ad hoc (`-`).
   An ad-hoc signature has no Team ID, so leave out `--options runtime` for
   the helpers and dylibs. Entitlement files like the ones VMForMac uses are in
   the VMForMac app itself (`codesign -d --entitlements - <file>`):

   ```sh
   APP=~/VMForMac-custom.app/Contents
   for f in "$APP"/Frameworks/*.dylib; do codesign -f -s - "$f"; done
   codesign -d --entitlements :- "$APP/Helpers/qemu-system-aarch64" > qemu.entitlements
   codesign -d --entitlements :- "$APP/Helpers/swtpm" > swtpm.entitlements
   codesign -d --entitlements :- "$APP/MacOS/vmfctl" > vmfctl.entitlements
   codesign -d --entitlements :- "$APP/MacOS/VMForMac" > app.entitlements
   codesign -f -s - --entitlements qemu.entitlements "$APP/Helpers/qemu-system-aarch64"
   codesign -f -s - --entitlements swtpm.entitlements "$APP/Helpers/swtpm"
   codesign -f -s - --options runtime --entitlements vmfctl.entitlements "$APP/MacOS/vmfctl"
   codesign -f -s - --options runtime --entitlements app.entitlements ~/VMForMac-custom.app
   ```

   Remove the `com.apple.application-identifier` and
   `com.apple.developer.team-identifier` keys from `app.entitlements` before
   signing ad hoc. They only work with Apple's provisioning profile.

A re-signed copy is a different app to macOS: it gets its own sandbox container
and does not receive App Store updates.

## Firmware branding

The edk2 build differs from upstream only in its build options (`build.sh`,
`EDK2_DEFINES`) and the boot logo:

- `MdeModulePkg/Logo/Logo.bmp` is replaced with a 24-bit BMP made from
  `scripts/qemu/branding/vmformac-logo.png` (transparent pixels on black).
  LogoDxe/BootLogoLib shows it while the firmware starts.
- `PcdFirmwareVendor` = `VMForMac BIOS`. `PcdFirmwareVersionString` and
  `PcdFirmwareReleaseDateString` come from `VMFORMAC_FIRMWARE_*` in
  `versions.env`. The UEFI shell's `ver` and the boot banner show them.

## Secure Boot variable store

`edk2-aarch64-vars-ms.fd` is generated at build time by `virt-fw-vars`
(virt-firmware 26.10) from the empty `edk2-aarch64-vars.fd` of the same edk2
build:

- PK: a "VMForMac Platform Key" certificate generated during the build. Its
  private key is discarded, so no one can sign PK or KEK changes.
- KEK: Microsoft Corporation KEK CA 2011 and Microsoft Corporation KEK 2K CA 2023
  (plus the PK certificate).
- db: Microsoft Windows Production PCA 2011, Windows UEFI CA 2023, Microsoft
  Corporation UEFI CA 2011 and Microsoft UEFI CA 2023.
- Secure Boot enabled.

The certificates are downloaded from Microsoft. Their URLs and SHA-256s are in
`versions.env`.

## Releases

Each release tag names the QEMU version and a revision, and its assets are the
`sources/` archives:

- `qemu-11.1.2-r1`: first release.
- `qemu-11.1.2-r2`: VMForMac boot logo and firmware vendor/version strings in
  the edk2 build (`scripts/qemu/branding/`, `VMFORMAC_FIRMWARE_*`). The source
  archives are unchanged from r1. This is the build in the first App Store
  release of VMForMac.
- Next (unreleased, tag to follow with the VMForMac build that ships it):
  `scripts/qemu/patches/qemu/0001-file-posix-compressed-files-are-data-on-macOS.patch`
  and `scripts/qemu/patches/libslirp/0001-udp-icmp-connect-sockets-for-the-macOS-App-Sandbox.patch`
  (guest UDP, DNS and ping work in the App Sandbox without `network.server`).
  The source archives are unchanged.
  The app bundle no longer carries the SeaBIOS VGA BIOS (`vgabios*.bin`), the
  iPXE ROMs other than `efi-virtio.rom`, keymaps other than `en-us`, or the
  empty `edk2-aarch64-vars.fd`: QEMU never opens them for VMForMac's Windows
  guests. The build itself is unchanged.
