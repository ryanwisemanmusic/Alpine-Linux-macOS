#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/.." && pwd)

arch="$1"
workdir="$2"
shift 2 || true
repos="$@"

[ -n "$repos" ] || repos="https://dl-cdn.alpinelinux.org/alpine/edge/main https://dl-cdn.alpinelinux.org/alpine/edge/community"

apkroot="$workdir/apkroot-$arch"
keysdir="$apkroot/etc/apk/keys"
mkdir -p "$keysdir"

tmpdir=$(mktemp -d -t fetch-apk-keys.XXXXXX)
trap 'rm -rf "$tmpdir"' EXIT

for repo in $repos; do
    # normalize base URL
    base=$(printf '%s' "$repo" | sed 's#/*$$##')
    listurl="$base/$arch/"
    if curl -sSfL "$listurl" -o "$tmpdir/list.html"; then
        pkg=$(grep -o 'alpine-keys[^"'\'' ]*\.apk' "$tmpdir/list.html" | head -n 1 || true)
        if [ -n "$pkg" ]; then
            pkgurl="$listurl$pkg"
            if curl -sSfL "$pkgurl" -o "$tmpdir/pkg.apk"; then
                # try to extract keys from the .apk (tar.gz format)
                if tar -tzf "$tmpdir/pkg.apk" >/dev/null 2>&1; then
                    tar -xzf "$tmpdir/pkg.apk" -C "$tmpdir"
                else
                    # try xz compressed
                    tar -xJf "$tmpdir/pkg.apk" -C "$tmpdir" || true
                fi
                if [ -d "$tmpdir/usr/share/apk/keys" ]; then
                    cp -a "$tmpdir/usr/share/apk/keys/." "$keysdir/" 2>/dev/null || true
                    echo "Fetched alpine keys from $pkgurl" >&2
                    exit 0
                fi
            fi
        fi
    fi
done

echo "Could not fetch alpine-keys package from repos: $repos" >&2
echo "You may need to provide signing keys under $keysdir manually." >&2
exit 1
