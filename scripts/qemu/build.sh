#!/bin/bash
# Reproducible build of QEMU (aarch64-softmmu, hvf) and every library it needs,
# from the pinned sources in scripts/qemu/versions.env.
#
#   build/cache/      downloaded archives (SHA-256 verified; mismatch aborts)
#   build/venv/       repo-local Python venv with meson + ninja (build-time only)
#   build/tools/      pkgconf, GNU m4/autoconf/automake/libtool, LLVM (build-time only)
#   build/work/       extracted sources and build trees
#   build/prefix/     private install prefix for the libraries and QEMU
#   build/qemu-dist/  relocated runtime: bin/{qemu-system-aarch64,swtpm},
#                     lib/*.dylib, share/qemu/... (Secure Boot capable edk2
#                     code + vars templates, one with Microsoft keys enrolled),
#                     share/licenses/; dylibs are found via @executable_path/../lib
#   build/qemu-src/   corresponding-source payload: tarballs, patches,
#                     versions.env, build scripts, licence texts
#
# Nothing from Homebrew (or any other non-system prefix) is used: PATH is
# reset to the venv/tools plus system directories, pkg-config only looks at
# build/prefix, and scripts/qemu/check-deps.sh verifies the result.
#
# Usage: scripts/qemu/build.sh [--clean]
#   --clean   remove everything under build/ except build/cache first.
# Completed stages are remembered in build/work/stamps; rerunning resumes.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
B="$ROOT/build"
CACHE="$B/cache"
VENV="$B/venv"
TOOLS="$B/tools"
WORK="$B/work"
SRC="$WORK/src"
BLD="$WORK/build"
STAMPS="$WORK/stamps"
PREFIX="$B/prefix"
DIST="$B/qemu-dist"
PAYLOAD="$B/qemu-src"
PATCHES="$SCRIPT_DIR/patches"
# Python used only to create build/venv. Default: the Xcode command line
# tools interpreter (no user-installed Python needed); override via HOST_PYTHON.
HOST_PYTHON="${HOST_PYTHON:-/usr/bin/python3}"

# shellcheck source=versions.env
. "$SCRIPT_DIR/versions.env"

if [ "${1:-}" = "--clean" ]; then
    rm -rf "$VENV" "$TOOLS" "$WORK" "$PREFIX" "$DIST" "$PAYLOAD"
fi

[ "$(uname -s)" = Darwin ] && [ "$(uname -m)" = arm64 ] || {
    echo "build.sh: Apple Silicon macOS required" >&2; exit 1; }
"$HOST_PYTHON" -I -c 'import sys; sys.exit(sys.version_info < (3, 9))' ||
    { echo "build.sh: $HOST_PYTHON must be Python >= 3.9 (QEMU requirement)" >&2; exit 1; }
HOST_PYTHON_ID="$HOST_PYTHON $("$HOST_PYTHON" -I -c 'import sys; print(sys.version.split()[0])')"

# ---------------------------------------------------------------- environment
# Keep the host's package managers out of the build entirely.
for v in CPATH C_INCLUDE_PATH CPLUS_INCLUDE_PATH OBJC_INCLUDE_PATH LIBRARY_PATH \
         CFLAGS CPPFLAGS CXXFLAGS OBJCFLAGS LDFLAGS PKG_CONFIG PKG_CONFIG_PATH \
         PKG_CONFIG_LIBDIR PKG_CONFIG_SYSROOT_DIR DYLD_LIBRARY_PATH \
         DYLD_FALLBACK_LIBRARY_PATH DYLD_INSERT_LIBRARIES PYTHONPATH PYTHONHOME \
         VIRTUAL_ENV CONDA_PREFIX HOMEBREW_PREFIX CC CXX OBJC; do
    unset "$v" || true
done
export PATH="$VENV/bin:$TOOLS/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export MACOSX_DEPLOYMENT_TARGET="$MACOS_DEPLOYMENT_TARGET"
export SDKROOT="$(xcrun --sdk macosx --show-sdk-path)"
export CC=/usr/bin/clang CXX=/usr/bin/clang++ OBJC=/usr/bin/clang
export PKG_CONFIG="$TOOLS/bin/pkgconf"
export PKG_CONFIG_LIBDIR="$PREFIX/lib/pkgconfig:$PREFIX/share/pkgconfig"
export PKG_CONFIG_PATH=""
export PIP_NO_CACHE_DIR=1 PIP_DISABLE_PIP_VERSION_CHECK=1
JOBS="$(sysctl -n hw.ncpu)"

mkdir -p "$CACHE" "$SRC" "$BLD" "$STAMPS" "$PREFIX"
TIMES="$WORK/build-times.txt"
BUILD_START=$(date +%s)

log() { printf '\n==> %s\n' "$*"; }
die() { echo "build.sh: $*" >&2; exit 1; }
var() { eval "printf '%s' \"\${$1}\""; }

# Stage stamps. A stage's key hashes the version + SHA-256 of its sources,
# the contents of its patches/<dir>/*.patch, any extra input, and the key of
# the previous stage (so a rebuilt library also rebuilds everything after
# it). The stage is skipped only when build/work/stamps/<stage> holds the
# same key.
patch_hash() { # patch_hash DIR
    if [ -d "$PATCHES/$1" ]; then
        find "$PATCHES/$1" -type f -name '*.patch' | LC_ALL=C sort |
            while IFS= read -r p; do printf '%s\n' "${p#"$PATCHES"/}"; cat "$p"; done |
            shasum -a 256 | awk '{print $1}'
    else
        echo none
    fi
}
CHAIN=""
begin() { # begin STAGE "SOURCE NAMES" "PATCH DIRS" [EXTRA]; true = must build
    local s d
    STAGE="$1"; STAGE_START=$(date +%s)
    KEY="$( { printf 'prev=%s\n' "$CHAIN"
              for s in $2; do printf '%s %s %s\n' "$s" "$(var "${s}_VERSION")" "$(var "${s}_SHA256")"; done
              for d in $3; do printf 'patches/%s %s\n' "$d" "$(patch_hash "$d")"; done
              printf 'extra=%s\n' "${4:-}"; } | shasum -a 256 | awk '{print $1}')"
    CHAIN="$KEY"
    [ "$(cat "$STAMPS/$STAGE" 2>/dev/null || true)" = "$KEY" ] && return 1
    rm -f "$STAMPS/$STAGE"
    return 0
}
mark_stage() {
    printf '%s\n' "$KEY" >"$STAMPS/$STAGE"
    stage_time "$STAGE"
}
stage_time() { printf '%-16s %5ss\n' "$1" "$(( $(date +%s) - STAGE_START ))" >>"$TIMES"; }

# Run a command; drop only the given benign stderr/stdout line pattern, show
# everything else, and fail the build if the command fails.
run_filtered() { # run_filtered PATTERN CMD...
    local pat="$1" out rc=0; shift
    out="$("$@" 2>&1)" || rc=$?
    if [ -n "$out" ]; then printf '%s\n' "$out" | grep -v -E "$pat" >&2 || true; fi
    [ "$rc" -eq 0 ] || die "command failed ($rc): $*"
}

# ------------------------------------------------------------------ downloads
fetch() { # fetch NAME -> verified file in $CACHE
    local name="$1" file url sha got
    file="$(var "${name}_FILE")"; url="$(var "${name}_URL")"; sha="$(var "${name}_SHA256")"
    if [ ! -f "$CACHE/$file" ] && [ -f "$ROOT/sources/$file" ]; then
        cp "$ROOT/sources/$file" "$CACHE/$file"   # running from the source payload
    fi
    if [ -f "$CACHE/$file" ]; then
        got="$(shasum -a 256 "$CACHE/$file" | awk '{print $1}')"
        [ "$got" = "$sha" ] && return 0
        echo "cached $file has wrong hash ($got); re-downloading" >&2
        rm -f "$CACHE/$file"
    fi
    log "download $file"
    curl -fL --retry 3 --proto '=https' -o "$CACHE/$file.part" "$url"
    got="$(shasum -a 256 "$CACHE/$file.part" | awk '{print $1}')"
    if [ "$got" != "$sha" ]; then
        rm -f "$CACHE/$file.part"
        die "SHA-256 mismatch for $file: expected $sha, got $got"
    fi
    mv "$CACHE/$file.part" "$CACHE/$file"
}

unpack() { # unpack NAME DIRNAME -> $SRC/DIRNAME (fresh), patches applied
    local name="$1" dir="$2" file tmp top
    file="$(var "${name}_FILE")"
    rm -rf "${SRC:?}/$dir"
    tmp="$(mktemp -d "$SRC/.unpack.XXXXXX")"
    tar -xf "$CACHE/$file" -C "$tmp"
    top="$(ls "$tmp")"
    [ "$(printf '%s\n' "$top" | wc -l | tr -d ' ')" = 1 ] || die "$file: unexpected layout"
    mv "$tmp/$top" "$SRC/$dir"
    rmdir "$tmp"
    if [ -d "$PATCHES/$dir" ]; then
        for p in "$PATCHES/$dir"/*.patch; do
            [ -e "$p" ] || continue
            log "patch $dir: $(basename "$p")"
            patch -d "$SRC/$dir" -p1 --forward <"$p"
        done
    fi
}

meson_build() { # meson_build DIR [meson args...]
    local dir="$1"; shift
    rm -rf "${BLD:?}/$dir"
    meson setup "$BLD/$dir" "$SRC/$dir" --prefix="$PREFIX" --libdir=lib \
        --buildtype=release -Ddefault_library=shared --wrap-mode=nodownload "$@"
    meson compile -C "$BLD/$dir" -j "$JOBS"
    meson install -C "$BLD/$dir" --quiet
}

autotools_build() { # autotools_build DIR [configure args...]
    local dir="$1"; shift
    rm -rf "${BLD:?}/$dir"; mkdir -p "$BLD/$dir"
    (cd "$BLD/$dir" && "$SRC/$dir/configure" --prefix="$PREFIX" --libdir="$PREFIX/lib" \
        --enable-shared --disable-static "$@" CFLAGS="-O2" &&
        make -j "$JOBS" && make install)
}

for s in $ALL_SOURCES $EXTERNAL_TOOLS; do fetch "$s"; done

# ------------------------------------------------------------ build-time tools
if begin venv "MESON NINJA SETUPTOOLS WHEEL TOMLI" "" "$HOST_PYTHON_ID"; then
    log "python venv (meson $MESON_VERSION, ninja $NINJA_VERSION, setuptools $SETUPTOOLS_VERSION, wheel $WHEEL_VERSION, tomli $TOMLI_VERSION; $HOST_PYTHON_ID)"
    rm -rf "$VENV"
    "$HOST_PYTHON" -I -m venv "$VENV"
    "$VENV/bin/python3" -I -m pip install --no-index --no-deps \
        "$CACHE/$MESON_FILE" "$CACHE/$NINJA_FILE" \
        "$CACHE/$SETUPTOOLS_FILE" "$CACHE/$WHEEL_FILE" "$CACHE/$TOMLI_FILE"
    mark_stage
fi

if begin pkgconf "PKGCONF" "pkgconf"; then
    log "pkgconf $PKGCONF_VERSION"
    unpack PKGCONF pkgconf
    rm -rf "$BLD/pkgconf"
    meson setup "$BLD/pkgconf" "$SRC/pkgconf" --prefix="$TOOLS" --libdir=lib \
        --buildtype=release -Ddefault_library=static \
        -Dwith-pkg-config-dir="$PREFIX/lib/pkgconfig:$PREFIX/share/pkgconfig"
    meson compile -C "$BLD/pkgconf" -j "$JOBS"
    meson install -C "$BLD/pkgconf" --quiet
    ln -sf pkgconf "$TOOLS/bin/pkg-config"
    mark_stage
fi

# ------------------------------------------------------------------ libraries
if begin pcre2 "PCRE2" "pcre2"; then
    log "pcre2 $PCRE2_VERSION"
    unpack PCRE2 pcre2
    autotools_build pcre2 --disable-jit --disable-pcre2grep-libz \
        --disable-pcre2grep-libbz2 --disable-pcre2test-libreadline
    mark_stage
fi

if begin libffi "LIBFFI" "libffi"; then
    log "libffi $LIBFFI_VERSION"
    unpack LIBFFI libffi
    autotools_build libffi --disable-docs --disable-multi-os-directory
    mark_stage
fi

if begin glib "GLIB PROXY_LIBINTL" "glib"; then
    log "glib $GLIB_VERSION"
    unpack GLIB glib
    # GLib needs libintl; macOS has none, so use GLib's own proxy-libintl
    # fallback (offline, from the verified cache) instead of building gettext.
    mkdir -p "$SRC/glib/subprojects/packagecache"
    cp "$CACHE/$PROXY_LIBINTL_FILE" "$SRC/glib/subprojects/packagecache/"
    meson_build glib -Dtests=false -Dinstalled_tests=false -Dnls=disabled \
        -Dintrospection=disabled -Ddocumentation=false -Dman-pages=disabled \
        -Ddtrace=disabled -Dsystemtap=disabled -Dsysprof=disabled \
        -Dlibelf=disabled -Dselinux=disabled -Dlibmount=disabled \
        -Dglib_debug=disabled
    mark_stage
fi

if begin pixman "PIXMAN" "pixman"; then
    log "pixman $PIXMAN_VERSION"
    unpack PIXMAN pixman
    meson_build pixman -Dtests=disabled -Ddemos=disabled -Dgtk=disabled \
        -Dlibpng=disabled -Dopenmp=disabled
    mark_stage
fi

if begin slirp "SLIRP" "libslirp"; then
    log "libslirp $SLIRP_VERSION"
    unpack SLIRP libslirp
    meson_build libslirp
    mark_stage
fi

if begin spice-protocol "SPICE_PROTOCOL" "spice-protocol"; then
    log "spice-protocol $SPICE_PROTOCOL_VERSION"
    unpack SPICE_PROTOCOL spice-protocol
    meson_build spice-protocol
    mark_stage
fi

# ----------------------------------------------------------------------- QEMU
if begin qemu "QEMU DTC" "qemu qemu-dtc"; then
    log "qemu $QEMU_VERSION"
    unpack QEMU qemu
    # libfdt: QEMU's internal "dtc" subproject, from the pinned dtc release.
    unpack DTC qemu-dtc
    rm -rf "$SRC/qemu/subprojects/dtc"
    mv "$SRC/qemu-dtc" "$SRC/qemu/subprojects/dtc"
    rm -rf "$BLD/qemu"; mkdir -p "$BLD/qemu"
    (cd "$BLD/qemu" && "$SRC/qemu/configure" \
        --prefix="$PREFIX" \
        --python="$VENV/bin/python3" \
        --disable-download \
        --target-list=aarch64-softmmu \
        --enable-hvf --enable-slirp --enable-vnc \
        --disable-cocoa --disable-sdl --disable-gtk --disable-opengl \
        --disable-docs --disable-guest-agent --disable-tools \
        --enable-fdt=internal --enable-spice-protocol --enable-tpm \
        --enable-pixman \
        --disable-vmnet --disable-curses --disable-rust \
        --disable-vnc-sasl --disable-auth-pam \
        --disable-werror)
    make -C "$BLD/qemu" -j "$JOBS"
    make -C "$BLD/qemu" install
    mark_stage
fi

# ------------------------------------------- GNU autotools (build-time only)
# libtpms and swtpm are released as git tag archives without a generated
# configure script, so they need autoreconf. GNU libtool is installed as
# glibtool/glibtoolize (it must never shadow Apple's /usr/bin/libtool).
gnu_tool_build() { # gnu_tool_build DIR [configure args...] -> installed into $TOOLS
    local dir="$1"; shift
    rm -rf "${BLD:?}/$dir"; mkdir -p "$BLD/$dir"
    (cd "$BLD/$dir" && "$SRC/$dir/configure" --prefix="$TOOLS" "$@" CFLAGS="-O2" &&
        make -j "$JOBS" && make install)
}
if begin m4 "M4" "m4"; then
    log "m4 $M4_VERSION (build tool)"
    unpack M4 m4
    gnu_tool_build m4 --disable-nls
    mark_stage
fi
if begin autoconf "AUTOCONF" "autoconf"; then
    log "autoconf $AUTOCONF_VERSION (build tool)"
    unpack AUTOCONF autoconf
    M4="$TOOLS/bin/m4" gnu_tool_build autoconf
    mark_stage
fi
if begin automake "AUTOMAKE" "automake"; then
    log "automake $AUTOMAKE_VERSION (build tool)"
    unpack AUTOMAKE automake
    gnu_tool_build automake
    mark_stage
fi
if begin libtool "LIBTOOL" "libtool"; then
    log "libtool $LIBTOOL_VERSION (build tool, as glibtool)"
    unpack LIBTOOL libtool
    M4="$TOOLS/bin/m4" gnu_tool_build libtool --program-prefix=g --disable-ltdl-install
    mark_stage
fi
autoreconf_src() { # autoreconf_src DIR: generate configure for a git tag archive
    (cd "$SRC/$1" && mkdir -p m4 &&
        M4="$TOOLS/bin/m4" LIBTOOLIZE="$TOOLS/bin/glibtoolize" autoreconf --force --install)
}
# Autoconf projects that probe libraries with AC_CHECK_LIB (not pkg-config)
# need the private prefix on the compiler/linker search path.
PREFIX_FLAGS=(CPPFLAGS="-I$PREFIX/include" LDFLAGS="-L$PREFIX/lib")

# ------------------------------------------------------ swtpm and its libraries
if begin openssl "OPENSSL" "openssl"; then
    log "openssl $OPENSSL_VERSION (libcrypto)"
    unpack OPENSSL openssl
    rm -rf "$BLD/openssl"; mkdir -p "$BLD/openssl"
    # Shared libcrypto/libssl only: no command line tools, docs or tests; no
    # loadable modules or engines (the default provider is built in), so
    # nothing is ever loaded from a build-time path. OPENSSLDIR (where
    # openssl.cnf would be read from) is /var/empty: root-owned and empty on
    # macOS, so no configuration file can be planted there.
    (cd "$BLD/openssl" && /usr/bin/perl "$SRC/openssl/Configure" darwin64-arm64-cc \
        --prefix="$PREFIX" --libdir=lib --openssldir=/var/empty \
        shared no-apps no-docs no-tests no-module no-legacy no-engine &&
        make -j "$JOBS" && make install_sw)
    mark_stage
fi

if begin libtasn1 "LIBTASN1" "libtasn1"; then
    log "libtasn1 $LIBTASN1_VERSION (configure-time dependency of swtpm; not shipped)"
    unpack LIBTASN1 libtasn1
    autotools_build libtasn1 --disable-doc --disable-valgrind-tests --disable-gcc-warnings
    mark_stage
fi

if begin json-glib "JSON_GLIB" "json-glib"; then
    log "json-glib $JSON_GLIB_VERSION"
    unpack JSON_GLIB json-glib
    meson_build json-glib -Dintrospection=disabled -Ddocumentation=disabled \
        -Dman=false -Dtests=false -Dconformance=false -Dinstalled_tests=false \
        -Dnls=disabled
    mark_stage
fi

if begin libtpms "LIBTPMS" "libtpms"; then
    log "libtpms $LIBTPMS_VERSION"
    unpack LIBTPMS libtpms
    autoreconf_src libtpms
    autotools_build libtpms --with-openssl --with-tpm2 "${PREFIX_FLAGS[@]}"
    mark_stage
fi

if begin swtpm "SWTPM" "swtpm"; then
    log "swtpm $SWTPM_VERSION"
    unpack SWTPM swtpm
    autoreconf_src swtpm
    rm -rf "$BLD/swtpm"; mkdir -p "$BLD/swtpm"
    # Only the swtpm daemon (QEMU's -tpmdev emulator backend) is built. A TPM
    # 2.0 state is created by swtpm itself on first start; swtpm_setup /
    # swtpm_localca / swtpm_cert (EK certificates, need gnutls + gmp) are not.
    (cd "$BLD/swtpm" && "$SRC/swtpm/configure" --prefix="$PREFIX" --libdir="$PREFIX/lib" \
        --enable-shared --disable-static --with-openssl --without-gnutls \
        --without-seccomp --without-cuse --without-selinux --disable-tests \
        "${PREFIX_FLAGS[@]}" CFLAGS="-O2" &&
        make -C include -j "$JOBS" && make -C src/utils -j "$JOBS" &&
        make -C src/swtpm -j "$JOBS" && make -C src/swtpm install)
    mark_stage
fi

# ------------------------------------------- edk2 with Secure Boot (aarch64)
# QEMU's prebuilt edk2-aarch64-code.fd is built without SECURE_BOOT_ENABLE and
# cannot enforce Secure Boot. Rebuild the same edk2 (roms/edk2 inside the
# pinned QEMU tarball, with all its submodules) with the options of QEMU's
# roms/edk2-build.config [build.armvirt.aa64] plus SECURE_BOOT_ENABLE=TRUE.
FW="$WORK/firmware"
LLVM_DIR="$TOOLS/llvm"
if begin llvm "LLVM" ""; then
    log "llvm $LLVM_VERSION (build tool: clang, lld, llvm-ar, llvm-objcopy)"
    rm -rf "$LLVM_DIR"; mkdir -p "$LLVM_DIR"
    top="${LLVM_FILE%.tar.xz}"
    tar -xf "$CACHE/$LLVM_FILE" -C "$LLVM_DIR" --strip-components 1 \
        "$top/bin/clang" "$top/bin/clang-${LLVM_VERSION%%.*}" "$top/bin/lld" \
        "$top/bin/ld.lld" "$top/bin/llvm-ar" "$top/bin/llvm-objcopy" "$top/lib/clang"
    "$LLVM_DIR/bin/clang" --version | head -1
    mark_stage
fi

if begin acpica "ACPICA" "acpica"; then
    log "acpica $ACPICA_VERSION (build tool: iasl)"
    unpack ACPICA acpica
    # Apple's linker rejects the unaligned pointers in ACPICA's packed dump
    # tables when emitting chained fixups; classic fixups only warn.
    make -C "$SRC/acpica" -j "$JOBS" iasl CC=/usr/bin/clang LDFLAGS="-Wl,-no_fixup_chains"
    install -m 755 "$SRC/acpica/generate/unix/bin/iasl" "$TOOLS/bin/iasl"
    mark_stage
fi

EDK2_DEFINES=(
    # [opts.common]
    -D NETWORK_HTTP_BOOT_ENABLE=TRUE -D NETWORK_IP6_ENABLE=TRUE
    -D NETWORK_TLS_ENABLE=TRUE -D NETWORK_ISCSI_ENABLE=TRUE
    -D NETWORK_ALLOW_HTTP_CONNECTIONS=TRUE -D TPM2_ENABLE=TRUE
    -D TPM2_CONFIG_ENABLE=TRUE -D TPM1_ENABLE=TRUE -D CAVIUM_ERRATUM_27456=TRUE
    # [opts.armvirt.silent]
    -D DEBUG_PRINT_ERROR_LEVEL=0x80000000
    # added by VMForMac (Windows 11 requires Secure Boot capable firmware)
    -D SECURE_BOOT_ENABLE=TRUE
    # VMForMac branding (versions.env; edk2-build.py's pcd_string form)
    --pcd "PcdFirmwareVendor=L${VMFORMAC_FIRMWARE_VENDOR}\\0"
    --pcd "PcdFirmwareVersionString=L${VMFORMAC_FIRMWARE_VERSION}\\0"
    --pcd "PcdFirmwareReleaseDateString=L${VMFORMAC_FIRMWARE_DATE}\\0"
    # [pcds.nx.broken.shim.grub]
    --pcd PcdDxeNxMemoryProtectionPolicy=0xC000000000007FD1
    --pcd PcdUninstallMemAttrProtocol=TRUE
)
# Boot logo: the VMForMac icon replaces the TianoCore Logo.bmp that LogoDxe
# (ArmVirtQemu's splash screen, via BootLogoLib) embeds as an HII image.
LOGO_PNG="$SCRIPT_DIR/branding/vmformac-logo.png"
LOGO_KEY="$(cat "$LOGO_PNG" "$SCRIPT_DIR/branding/png2bmp.py" | shasum -a 256 | awk '{print $1}')"
if begin edk2 "QEMU" "qemu-edk2" "${EDK2_DEFINES[*]} logo=$LOGO_KEY"; then
    log "edk2 ($(sed -n 's/^EDK2_STABLE = //p' "$SRC/qemu/roms/edk2-version" 2>/dev/null || echo 'from QEMU'), ArmVirtQemu AARCH64, Secure Boot)"
    unpack QEMU qemu-edk2
    E="$SRC/qemu-edk2/roms/edk2"
    "$VENV/bin/python3" -I "$SCRIPT_DIR/branding/png2bmp.py" "$LOGO_PNG" "$E/MdeModulePkg/Logo/Logo.bmp"
    (
        cd "$E"
        export WORKSPACE="$E" PACKAGES_PATH="$E" EDK_TOOLS_PATH="$E/BaseTools"
        export CONF_PATH="$E/Conf"
        export CLANGDWARF_BIN="$LLVM_DIR/bin/"
        # BaseTools' Decompress.c redefines UINT8_MAX, an error with -Werror on
        # current clang (fixed in later edk2 releases).
        make -C BaseTools -j "$JOBS" CC=/usr/bin/clang CXX=/usr/bin/clang++ \
            EXTRA_OPTFLAGS=-Wno-macro-redefined
        # Pass an explicit argument: a bare ". ./edksetup.sh" would see
        # build.sh's own arguments (e.g. --clean) and fail with its usage text.
        set +u; . ./edksetup.sh BaseTools; set -u
        export PYTHON_COMMAND="$VENV/bin/python3"   # edksetup resets it to python3
        build -n "$JOBS" -a AARCH64 -t CLANGDWARF -b RELEASE \
            -p ArmVirtPkg/ArmVirtQemu.dsc "${EDK2_DEFINES[@]}"
    )
    out="$E/Build/ArmVirtQemu-AARCH64/RELEASE_CLANGDWARF/FV"
    rm -rf "$FW"; mkdir -p "$FW"
    # Same 64 MiB pflash layout as QEMU's pc-bios images (pad with zeros).
    cp "$out/QEMU_EFI.fd" "$FW/edk2-aarch64-code.fd"
    cp "$out/QEMU_VARS.fd" "$FW/edk2-aarch64-vars.fd"
    truncate -s 64m "$FW/edk2-aarch64-code.fd" "$FW/edk2-aarch64-vars.fd"
    mark_stage
fi

# ------------------------------------- Secure Boot vars with Microsoft keys
if begin virt-firmware "VIRT_FIRMWARE CRYPTOGRAPHY CFFI PYCPARSER TYPING_EXTENSIONS" ""; then
    log "virt-firmware $VIRT_FIRMWARE_VERSION (cryptography $CRYPTOGRAPHY_VERSION) into the venv"
    "$VENV/bin/python3" -I -m pip install --no-index --no-deps \
        "$CACHE/$VIRT_FIRMWARE_FILE" "$CACHE/$CRYPTOGRAPHY_FILE" "$CACHE/$CFFI_FILE" \
        "$CACHE/$PYCPARSER_FILE" "$CACHE/$TYPING_EXTENSIONS_FILE"
    mark_stage
fi

# PK: a fresh "VMForMac Platform Key" self-signed certificate generated by
# virt-fw-vars --enroll-generate; its private key is never written outside a
# temporary file and is discarded, so nobody can sign PK/KEK updates. KEK: the
# two Microsoft KEK CAs (plus the PK certificate, as OVMF/virt-firmware do), so
# Windows Update can still apply KEK-signed db/dbx updates. db: the Microsoft
# Windows (Production PCA 2011, Windows UEFI CA 2023) and third-party (UEFI CA
# 2011, UEFI CA 2023) CAs. dbx: virt-firmware's placeholder entry.
MS_OWNER=77fa9abd-0359-4d32-bd60-28f4e78f784b   # MicrosoftVendor GUID
PK_CN="VMForMac Platform Key"
if begin vars-ms "$MS_KEK_CERTS $MS_DB_CERTS" "" "pk=$PK_CN"; then
    log "edk2-aarch64-vars-ms.fd (Microsoft KEK/db, Secure Boot enabled)"
    args=()
    for c in $MS_KEK_CERTS; do args+=(--add-kek "$MS_OWNER" "$CACHE/$(var "${c}_FILE")"); done
    for c in $MS_DB_CERTS; do args+=(--add-db "$MS_OWNER" "$CACHE/$(var "${c}_FILE")"); done
    mkdir -p "$WORK/tmp"
    rm -f "$FW/edk2-aarch64-vars-ms.fd"
    TMPDIR="$WORK/tmp" "$VENV/bin/virt-fw-vars" -l warning \
        -i "$FW/edk2-aarch64-vars.fd" -o "$FW/edk2-aarch64-vars-ms.fd.part" \
        --enroll-generate "$PK_CN" --microsoft-kek none --no-microsoft \
        "${args[@]}" --secure-boot
    [ "$(stat -f %z "$FW/edk2-aarch64-vars-ms.fd.part")" = "$(stat -f %z "$FW/edk2-aarch64-code.fd")" ] ||
        die "vars-ms size differs from the code image"
    "$VENV/bin/virt-fw-vars" -l warning -i "$FW/edk2-aarch64-vars-ms.fd.part" --print |
        grep -q -E '^SecureBootEnable +: bool: ON' || die "SecureBootEnable not set in vars-ms"
    mv "$FW/edk2-aarch64-vars-ms.fd.part" "$FW/edk2-aarch64-vars-ms.fd"
    mark_stage
fi

# --------------------------------------------------------- relocated runtime
# dist and payload are cheap and always reassembled.
STAGE_START=$(date +%s)
log "assemble $DIST"
rm -rf "$DIST"
mkdir -p "$DIST/bin" "$DIST/lib" "$DIST/share"
HELPERS="qemu-system-aarch64 swtpm"
for h in $HELPERS; do cp "$PREFIX/bin/$h" "$DIST/bin/"; done
mkdir -p "$DIST/share/qemu"
# Only what an aarch64 virt guest can use: keymaps (VNC), edk2 licences, UEFI
# NIC option ROMs and VGA BIOS ROMs (PCI devices fail to start if their
# default romfile is missing). Firmware for other guest architectures and
# share/qemu/firmware/*.json (which hold absolute build-prefix paths and are
# not read by QEMU itself) are left out. QEMU's own edk2-aarch64-code.fd and
# edk2-arm-vars.fd are replaced by the Secure Boot build from $FW:
#   edk2-aarch64-code.fd      code (read-only pflash 0)
#   edk2-aarch64-vars.fd      empty variable store template (pflash 1)
#   edk2-aarch64-vars-ms.fd   the same with PK/KEK/db enrolled, Secure Boot on
(cd "$PREFIX/share/qemu" && cp -R keymaps edk2-licenses.txt efi-*.rom vgabios*.bin \
    "$DIST/share/qemu/")
cp "$FW/edk2-aarch64-code.fd" "$FW/edk2-aarch64-vars.fd" "$FW/edk2-aarch64-vars-ms.fd" \
    "$DIST/share/qemu/"

deps_of() { otool -L "$1" | tail -n +2 | sed -E 's/^[[:space:]]+//; s/ \(compat.*$//'; }

copy_closure() { # copy every $PREFIX dylib that $1 needs into $DIST/lib
    local dep name real
    while IFS= read -r dep; do
        case "$dep" in "$PREFIX"/*) ;; *) continue ;; esac
        name="$(basename "$dep")"
        [ -e "$DIST/lib/$name" ] && continue
        real="$(realpath "$dep")"
        cp "$real" "$DIST/lib/$name"
        chmod u+w "$DIST/lib/$name"
        copy_closure "$DIST/lib/$name"
    done < <(deps_of "$1")
}
for h in $HELPERS; do copy_closure "$DIST/bin/$h"; done

relocate() { # relocate FILE RPATH
    local f="$1" rp="$2" dep args=()
    case "$f" in *.dylib) args+=(-id "@rpath/$(basename "$f")") ;; esac
    while IFS= read -r dep; do
        case "$dep" in "$PREFIX"/*) args+=(-change "$dep" "@rpath/$(basename "$dep")") ;; esac
    done < <(deps_of "$f")
    while IFS= read -r old; do
        args+=(-delete_rpath "$old")
    done < <(otool -l "$f" | awk '/cmd LC_RPATH/{r=1} r && $1=="path"{print $2; r=0}')
    args+=(-add_rpath "$rp")
    run_filtered 'will invalidate the code signature' strip -x "$f"
    run_filtered 'invalidate the code signature' install_name_tool "${args[@]}" "$f"
}
for f in "$DIST"/lib/*.dylib; do relocate "$f" @loader_path; done
for h in $HELPERS; do relocate "$DIST/bin/$h" @executable_path/../lib; done

# install_name_tool invalidates signatures; arm64 requires a valid one.
# Ad-hoc sign here (the app build re-signs with the real identity); QEMU needs
# the hypervisor entitlement for -accel hvf.
for f in "$DIST"/lib/*.dylib; do
    run_filtered ': replacing existing signature$' codesign -f -s - "$f"
done
run_filtered ': replacing existing signature$' codesign -f -s - \
    --entitlements "$SRC/qemu/accel/hvf/entitlements.plist" "$DIST/bin/qemu-system-aarch64"
run_filtered ': replacing existing signature$' codesign -f -s - "$DIST/bin/swtpm"
"$SCRIPT_DIR/check-deps.sh" "$DIST"
stage_time dist

# --------------------------------------------------- corresponding source
STAGE_START=$(date +%s)
log "assemble $PAYLOAD"
rm -rf "$PAYLOAD"
mkdir -p "$PAYLOAD/sources" "$PAYLOAD/licenses" "$PAYLOAD/scripts"
for s in $ALL_SOURCES; do cp "$CACHE/$(var "${s}_FILE")" "$PAYLOAD/sources/"; done
# One copy of the build scripts, versions.env and patches/ (scripts/qemu/),
# laid out so that scripts/qemu/build.sh works from the payload root too.
cp -R "$SCRIPT_DIR" "$PAYLOAD/scripts/qemu"
mv "$PAYLOAD/scripts/qemu/payload-README.md" "$PAYLOAD/README.md"
(cd "$PAYLOAD/sources" && shasum -a 256 * >"$PAYLOAD/SHA256SUMS")
# Top-level licence texts of the copyleft parts: GPL v2 (QEMU, iPXE), LGPL v2.1
# (GLib, JSON-GLib), LGPL v3 and the GPL v3 it builds on (SeaBIOS VGA BIOS).
cp "$SRC/qemu/COPYING" "$PAYLOAD/COPYING"
cp "$SRC/qemu/COPYING.LIB" "$PAYLOAD/COPYING.LIB"
cp "$SRC/qemu/roms/seabios/COPYING.LESSER" "$PAYLOAD/COPYING.LGPLv3"
cp "$SRC/qemu/roms/seabios/COPYING" "$PAYLOAD/COPYING.GPLv3"
{
    printf '# Source archives\n\n'
    printf 'Every archive the build uses, from `scripts/qemu/versions.env`. "Shipped" ones end up\n'
    printf 'in the VMForMac app; the others are build-time tools and inputs. Release assets\n'
    printf 'carry the same files; `SHA256SUMS` lists the hashes in `shasum -c` form.\n\n'
    printf '| Archive | Version | Shipped | Upstream URL | SHA-256 |\n|---|---|---|---|---|\n'
    for s in $ALL_SOURCES; do
        case " $SHIPPED_SOURCES " in *" $s "*) shipped=yes ;; *) shipped=no ;; esac
        printf '| `%s` | %s | %s | <%s> | `%s` |\n' "$(var "${s}_FILE")" "$(var "${s}_VERSION")" \
            "$shipped" "$(var "${s}_URL")" "$(var "${s}_SHA256")"
    done
    printf '\nBuild-time download, not in `sources/` (1.5 GB): `%s` %s, <%s>, `%s`.\n' \
        "$LLVM_FILE" "$LLVM_VERSION" "$LLVM_URL" "$LLVM_SHA256"
} >"$PAYLOAD/SOURCES.md"
# The payload is published as a git repository with the archives attached to
# a release (too large for git), so git ignores sources/ and build outputs.
printf '/sources/\n/build/\n' >"$PAYLOAD/.gitignore"

licenses_from() { # licenses_from SRCDIR LABEL
    local d="$1" label="$2" f
    mkdir -p "$PAYLOAD/licenses/$label"
    for f in "$d"/COPYING* "$d"/LICENSE* "$d"/LICENCE* "$d"/COPYRIGHT* \
             "$d"/README.license "$d"/BSD-2-Clause "$d"/GPL "$d"/LICENSES; do
        [ -e "$f" ] && cp -R "$f" "$PAYLOAD/licenses/$label/"
    done
    return 0
}
licenses_from "$SRC/qemu" "qemu-$QEMU_VERSION"
cp "$SRC/qemu/pc-bios/edk2-licenses.txt" "$PAYLOAD/licenses/qemu-$QEMU_VERSION/"
licenses_from "$SRC/qemu/subprojects/dtc" "dtc-$DTC_VERSION"
licenses_from "$SRC/qemu/subprojects/keycodemapdb" "keycodemapdb"
licenses_from "$SRC/qemu/subprojects/berkeley-softfloat-3" "berkeley-softfloat-3"
licenses_from "$SRC/glib" "glib-$GLIB_VERSION"
for d in "$SRC"/glib/subprojects/proxy-libintl*/; do
    [ -d "$d" ] && licenses_from "$d" "proxy-libintl-$PROXY_LIBINTL_VERSION"
done
if [ ! -d "$PAYLOAD/licenses/proxy-libintl-$PROXY_LIBINTL_VERSION" ]; then
    tmp="$(mktemp -d "$WORK/.lic.XXXXXX")"
    tar -xf "$CACHE/$PROXY_LIBINTL_FILE" -C "$tmp"
    licenses_from "$tmp/$(ls "$tmp")" "proxy-libintl-$PROXY_LIBINTL_VERSION"
    rm -rf "$tmp"
fi
licenses_from "$SRC/pcre2" "pcre2-$PCRE2_VERSION"
licenses_from "$SRC/libffi" "libffi-$LIBFFI_VERSION"
licenses_from "$SRC/pixman" "pixman-$PIXMAN_VERSION"
licenses_from "$SRC/libslirp" "libslirp-$SLIRP_VERSION"
licenses_from "$SRC/spice-protocol" "spice-protocol-$SPICE_PROTOCOL_VERSION"
licenses_from "$SRC/openssl" "openssl-$OPENSSL_VERSION"
licenses_from "$SRC/json-glib" "json-glib-$JSON_GLIB_VERSION"
licenses_from "$SRC/libtpms" "libtpms-$LIBTPMS_VERSION"
licenses_from "$SRC/swtpm" "swtpm-$SWTPM_VERSION"
# QEMU's prebuilt ROMs that ship in Resources/qemu: iPXE (efi-*.rom, GPL-2.0+)
# and SeaBIOS's VGA BIOS (vgabios*.bin, LGPL-3.0). Their source is roms/ipxe and
# roms/seabios of the QEMU tarball.
licenses_from "$SRC/qemu/roms/ipxe" "ipxe"
mkdir -p "$PAYLOAD/licenses/seabios-vgabios"
cp "$SRC/qemu/roms/seabios/COPYING.LESSER" "$SRC/qemu/roms/seabios/COPYING" \
    "$PAYLOAD/licenses/seabios-vgabios/"
# The edk2 firmware is built from QEMU's roms/edk2; its licences (edk2 and the
# bundled OpenSSL, Brotli, libfdt, ...) are in qemu-*/edk2-licenses.txt.
for d in "$PAYLOAD"/licenses/*/; do
    [ -n "$(ls -A "$d")" ] || die "no licence text found for $(basename "$d")"
done

# The licence texts also ship with the runtime (the app copies them to
# Contents/Resources/Licenses/).
rm -rf "$DIST/share/licenses"
cp -R "$PAYLOAD/licenses" "$DIST/share/licenses"
# GPL_SOURCE_URL in crates/vmf-core/src/paths.rs (the only place it is defined).
GPL_SOURCE_URL="$(sed -n 's/^pub const GPL_SOURCE_URL: &str = "\(https:[^"]*\)";$/\1/p' \
    "$ROOT/crates/vmf-core/src/paths.rs" 2>/dev/null || true)"
cat >"$DIST/share/licenses/README.txt" <<EOT
Licence texts of the third-party components bundled with VMForMac's QEMU
engine (QEMU $QEMU_VERSION, swtpm $SWTPM_VERSION, libtpms $LIBTPMS_VERSION, edk2
firmware, GLib, OpenSSL and the other libraries), one directory per component.

The complete corresponding source code, the build scripts and these texts are
published at ${GPL_SOURCE_URL:-the VMForMac QEMU source repository}
EOT
stage_time payload

TOTAL=$(( $(date +%s) - BUILD_START ))
printf '%-16s %5ss\n' "TOTAL(this run)" "$TOTAL" >>"$TIMES"
log "done in ${TOTAL}s"
"$DIST/bin/qemu-system-aarch64" --version | head -1
