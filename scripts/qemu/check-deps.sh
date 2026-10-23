#!/bin/bash
# Check that every Mach-O file under a directory only references allowed
# library locations (global constraint: no Homebrew / build-tree paths at run
# time). Exits non-zero and lists each offending reference otherwise.
#
# Allowed load commands (otool -L): /usr/lib/*, /System/*, @rpath/*,
# @loader_path/*, @executable_path/*.
# Allowed LC_RPATH entries: @loader_path*, @executable_path*.
#
# Usage: scripts/qemu/check-deps.sh [dir]   (default: build/qemu-dist)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
DIR="${1:-$ROOT/build/qemu-dist}"
[ -d "$DIR" ] || { echo "check-deps: no such directory: $DIR" >&2; exit 2; }

bad=0
count=0
while IFS= read -r -d '' f; do
    # Only Mach-O files (executables, dylibs, bundles).
    if ! file -b "$f" | grep -q 'Mach-O'; then continue; fi
    count=$((count + 1))
    # Skip the first line ("<file>:"); every other line is a dependency
    # (for dylibs the first one is its own install name, which must be
    # relative as well).
    while IFS= read -r dep; do
        dep="${dep#"${dep%%[![:space:]]*}"}"
        dep="${dep%% (compatibility*}"
        [ -n "$dep" ] || continue
        case "$dep" in
            /usr/lib/*|/System/*|@rpath/*|@loader_path/*|@executable_path/*) ;;
            *) echo "BAD dependency: ${f#"$DIR"/} -> $dep"; bad=1 ;;
        esac
    done < <(otool -L "$f" | tail -n +2)
    while IFS= read -r rp; do
        case "$rp" in
            @loader_path*|@executable_path*) ;;
            *) echo "BAD rpath: ${f#"$DIR"/} -> $rp"; bad=1 ;;
        esac
    done < <(otool -l "$f" | awk '/cmd LC_RPATH/{r=1} r && $1=="path"{print $2; r=0}')
done < <(find "$DIR" -type f -print0)

if [ "$count" -eq 0 ]; then
    echo "check-deps: no Mach-O files found under $DIR" >&2
    exit 2
fi
if [ "$bad" -ne 0 ]; then
    echo "check-deps: FAILED ($count Mach-O files checked)" >&2
    exit 1
fi
echo "check-deps: OK ($count Mach-O files, only allowed references)"
