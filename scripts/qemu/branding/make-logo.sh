#!/bin/sh
# Regenerates scripts/qemu/branding/vmformac-logo.png (the edk2 boot logo) from
# resources/icon/AppIcon.svg with the xtask-icon rasterizer (resvg), 200x200 RGBA.
# build.sh converts it to the 24-bit BMP that replaces edk2's
# MdeModulePkg/Logo/Logo.bmp (png2bmp.py, transparent -> black).
# The PNG is committed so the GPL source payload builds without Rust; the
# xtask-icon test `boot_logo_matches_app_icon` fails if it is out of date.
# Usage: scripts/qemu/branding/make-logo.sh   (commit the resulting PNG)
set -eu
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
cd "$ROOT"
cargo run -q -p xtask-icon -- resources/icon/AppIcon.svg scripts/qemu/branding/vmformac-logo.png 200
echo "Wrote scripts/qemu/branding/vmformac-logo.png"
