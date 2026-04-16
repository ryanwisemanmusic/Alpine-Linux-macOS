#!/bin/sh

set -eu

script_dir=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
harness_dir=$(CDPATH= cd -- "$script_dir/.." && pwd)
toolchain_dir="$harness_dir/toolchain"
toolchain_bin="$toolchain_dir/bin"
drop_firmware_dir="$harness_dir/drop/firmware"

resolve_brew() {
	for candidate in /opt/homebrew/bin/brew /usr/local/bin/brew; do
		if [ -x "$candidate" ]; then
			printf '%s\n' "$candidate"
			return 0
		fi
	done

	if command -v brew >/dev/null 2>&1; then
		command -v brew
		return 0
	fi

	return 1
}

require_tool() {
	name="$1"
	if ! command -v "$name" >/dev/null 2>&1; then
		printf '%s\n' "Missing required host tool: $name" >&2
		exit 1
	fi
}

stage_link() {
	name="$1"
	target="$2"

	if [ -z "$target" ] || [ ! -x "$target" ]; then
		return 0
	fi

	ln -sfn "$target" "$toolchain_bin/$name"
}

stage_firmware_link() {
	dest_name="$1"
	target="$2"

	if [ -z "$target" ] || [ ! -f "$target" ]; then
		return 0
	fi

	ln -sfn "$target" "$drop_firmware_dir/$dest_name"
}

if ! brew_bin=$(resolve_brew); then
	printf '%s\n' 'Homebrew is required for make bootstrap but was not found.' >&2
	exit 1
fi

brew_prefix=$(CDPATH= cd -- "$(dirname "$brew_bin")" && pwd)
build_path="$brew_prefix:/usr/local/bin:/usr/bin:/bin"
export PATH="$build_path"

require_tool xcode-select
if ! xcode-select -p >/dev/null 2>&1; then
	printf '%s\n' 'Xcode Command Line Tools are required before running make bootstrap.' >&2
	exit 1
fi

for tool in curl tar make shasum cc bison flex sed sort install; do
	require_tool "$tool"
done

mkdir -p "$toolchain_bin" "$drop_firmware_dir"

missing_formulae=
for formula in \
	qemu \
	xorriso \
	squashfs \
	mtools \
	fakeroot \
	coreutils \
	gnu-getopt \
	gnu-tar \
	meson \
	ninja \
	pkgconf \
	freetype \
	gawk \
	aarch64-elf-binutils \
	aarch64-elf-gcc; do
	if ! "$brew_bin" list --formula --versions "$formula" >/dev/null 2>&1; then
		missing_formulae="$missing_formulae $formula"
	fi
done

if [ -n "$missing_formulae" ]; then
	"$brew_bin" install $missing_formulae
fi

for tool in \
	qemu-system-aarch64 \
	qemu-img \
	xorrisofs \
	mksquashfs \
	fakeroot \
	mformat \
	mcopy \
	meson \
	ninja \
	pkg-config \
	gawk \
	aarch64-elf-gcc \
	aarch64-elf-objcopy \
	aarch64-elf-ranlib \
	aarch64-elf-nm \
	aarch64-elf-strip; do
	if command -v "$tool" >/dev/null 2>&1; then
		stage_link "$tool" "$(command -v "$tool")"
	fi
done

for candidate in \
	"$("$brew_bin" --prefix coreutils 2>/dev/null)/libexec/gnubin/install" \
	"/opt/homebrew/opt/coreutils/libexec/gnubin/install" \
	"/opt/homebrew/bin/ginstall" \
	"/usr/local/opt/coreutils/libexec/gnubin/install" \
	"/usr/local/bin/ginstall"; do
	if [ -x "$candidate" ]; then
		stage_link install "$candidate"
		break
	fi
done

for candidate in \
	"$("$brew_bin" --prefix gnu-getopt 2>/dev/null)/bin/getopt" \
	"/opt/homebrew/opt/gnu-getopt/bin/getopt" \
	"/usr/local/opt/gnu-getopt/bin/getopt"; do
	if [ -x "$candidate" ]; then
		stage_link getopt "$candidate"
		break
	fi
done

for candidate in \
	"$("$brew_bin" --prefix gnu-tar 2>/dev/null)/libexec/gnubin/tar" \
	"/opt/homebrew/opt/gnu-tar/libexec/gnubin/tar" \
	"/opt/homebrew/bin/gtar" \
	"/usr/local/opt/gnu-tar/libexec/gnubin/tar" \
	"/usr/local/bin/gtar"; do
	if [ -x "$candidate" ]; then
		stage_link tar "$candidate"
		break
	fi
done

for candidate in \
	"$brew_prefix/../share/qemu/edk2-aarch64-code.fd" \
	"$brew_prefix/../share/qemu/edk2-arm-code.fd"; do
	if [ -f "$candidate" ]; then
		stage_firmware_link "edk2-aarch64-code.fd" "$candidate"
		break
	fi
done

for candidate in \
	"$brew_prefix/../share/qemu/edk2-aarch64-vars.fd" \
	"$brew_prefix/../share/qemu/edk2-arm-vars.fd"; do
	if [ -f "$candidate" ]; then
		stage_firmware_link "edk2-aarch64-vars.fd" "$candidate"
		break
	fi
done

printf 'Staged host tool links in %s\n' "$toolchain_bin"
printf 'Staged firmware links in %s\n' "$drop_firmware_dir"
