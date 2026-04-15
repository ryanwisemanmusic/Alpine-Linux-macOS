#!/bin/sh

set -eu

script_dir=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
harness_dir=$(CDPATH= cd -- "$script_dir/.." && pwd)
toolchain_dir="$harness_dir/toolchain"
toolchain_bin="$toolchain_dir/bin"
src_dir="$harness_dir/src"
build_dir="$harness_dir/build"
grub_version="${GRUB_VERSION:-2.12}"
grub_name="grub-$grub_version"
grub_tarball="$src_dir/$grub_name.tar.xz"
grub_url="${GRUB_URL:-https://ftp.gnu.org/gnu/grub/$grub_name.tar.xz}"
grub_src="$src_dir/$grub_name"
grub_src_rel="../../src/$grub_name"
grub_build="$build_dir/grub-host-aarch64"
grub_prefix="$toolchain_dir/grub-host"
grub_extra_deps="$grub_src/grub-core/extra_deps.lst"

resolve_tool() {
	name="$1"
	shift

	for candidate in "$@"; do
		if [ -n "$candidate" ] && [ -x "$candidate" ]; then
			printf '%s\n' "$candidate"
			return 0
		fi
	done

	if command -v "$name" >/dev/null 2>&1; then
		command -v "$name"
		return 0
	fi

	return 1
}

cpu_jobs() {
	if [ -n "${JOBS-}" ]; then
		printf '%s\n' "$JOBS"
		return 0
	fi

	if command -v sysctl >/dev/null 2>&1; then
		sysctl -n hw.logicalcpu 2>/dev/null && return 0
		sysctl -n hw.ncpu 2>/dev/null && return 0
	fi

	printf '%s\n' 4
}

mkdir -p "$toolchain_bin" "$src_dir" "$build_dir"

curl_bin=$(resolve_tool curl /usr/bin/curl "$toolchain_bin/curl")
tar_bin=$(resolve_tool tar /usr/bin/tar "$toolchain_bin/tar")
make_bin=$(resolve_tool make /usr/bin/make "$toolchain_bin/make")
gawk_bin=$(resolve_tool gawk /opt/homebrew/bin/gawk "$toolchain_bin/gawk")
pkg_config_bin=$(resolve_tool pkg-config /opt/homebrew/bin/pkg-config "$toolchain_bin/pkg-config")
target_cc=$(resolve_tool aarch64-elf-gcc /opt/homebrew/bin/aarch64-elf-gcc "$toolchain_bin/aarch64-elf-gcc")
target_objcopy=$(resolve_tool aarch64-elf-objcopy /opt/homebrew/bin/aarch64-elf-objcopy "$toolchain_bin/aarch64-elf-objcopy")
target_ranlib=$(resolve_tool aarch64-elf-ranlib /opt/homebrew/bin/aarch64-elf-ranlib "$toolchain_bin/aarch64-elf-ranlib")
target_nm=$(resolve_tool aarch64-elf-nm /opt/homebrew/bin/aarch64-elf-nm "$toolchain_bin/aarch64-elf-nm")
target_strip=$(resolve_tool aarch64-elf-strip /opt/homebrew/bin/aarch64-elf-strip "$toolchain_bin/aarch64-elf-strip")
jobs=$(cpu_jobs)

build_path="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$toolchain_bin"

if [ ! -f "$grub_tarball" ]; then
	env PATH="$build_path" "$curl_bin" -L "$grub_url" -o "$grub_tarball"
fi

if [ ! -d "$grub_src" ]; then
	env PATH="$build_path" "$tar_bin" -xf "$grub_tarball" -C "$src_dir"
fi

: > "$grub_extra_deps"

mkdir -p "$grub_build"
(
	cd "$grub_build"
	env \
		LC_ALL=C \
		PATH="$build_path" \
		PKG_CONFIG="$pkg_config_bin" \
		TARGET_CC="$target_cc" \
		TARGET_OBJCOPY="$target_objcopy" \
		TARGET_RANLIB="$target_ranlib" \
		TARGET_NM="$target_nm" \
		TARGET_STRIP="$target_strip" \
		"$grub_src_rel/configure" \
			--prefix="$grub_prefix" \
			--disable-werror \
			--target=aarch64-elf \
			--with-platform=efi

	env PATH="$build_path" "$make_bin" -j"$jobs" AWK="$gawk_bin"
	env PATH="$build_path" "$make_bin" AWK="$gawk_bin" install
)

for tool in grub-mkimage grub-mkstandalone grub-mkrescue grub-mknetdir; do
	if [ -x "$grub_prefix/bin/$tool" ]; then
		ln -sfn "$grub_prefix/bin/$tool" "$toolchain_bin/$tool"
	fi
done

printf 'Built local GRUB arm64-efi host tools under %s\n' "$grub_prefix"
