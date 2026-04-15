#!/bin/sh

set -eu

if [ $# -lt 1 ]; then
	echo "usage: $0 <tool> [--doctor] [args...]" >&2
	exit 2
fi

tool="$1"
shift

mode="run"
if [ "${1-}" = "--doctor" ]; then
	mode="doctor"
	shift
fi

script_dir=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
harness_dir=$(CDPATH= cd -- "$script_dir/.." && pwd)
repo_root=$(CDPATH= cd -- "$harness_dir/.." && pwd)
wrapper_bin="$harness_dir/bin"
toolchain_bin="$harness_dir/toolchain/bin"
grub_host_bin="$harness_dir/toolchain/grub-host/bin"

strip_path_entry() {
	target="$1"
	input_path="${2-}"
	old_ifs=$IFS
	IFS=:
	out=
	for entry in $input_path; do
		[ -n "$entry" ] || continue
		[ "$entry" = "$target" ] && continue
		if [ -n "$out" ]; then
			out="$out:$entry"
		else
			out="$entry"
		fi
	done
	IFS=$old_ifs
	printf '%s\n' "$out"
}

search_path=$(strip_path_entry "$wrapper_bin" "${PATH-}")

have_exec() {
	[ $# -gt 0 ] && [ -n "$1" ] && [ -x "$1" ]
}

run_make() {
	subdir="$1"
	shift
	command -v make >/dev/null 2>&1 || return 1
	build_path="$search_path"
	if [ -d /opt/homebrew/bin ]; then
		build_path="/opt/homebrew/bin:$build_path"
	fi
	(
		cd "$repo_root/$subdir"
		env PATH="$build_path" make "$@" >/dev/null
	)
}

run_meson_apk_build() {
	if ! command -v meson >/dev/null 2>&1 || ! command -v ninja >/dev/null 2>&1; then
		return 1
	fi
	build_path="$search_path"
	if [ -d /opt/homebrew/bin ]; then
		build_path="/opt/homebrew/bin:$build_path"
	fi
	(
		cd "$repo_root/apk-tools"
		if [ ! -d build-macos ] || [ ! -f build-macos/build.ninja ]; then
			env PATH="$build_path" meson setup build-macos . \
				-Ddocs=disabled \
				-Dhelp=disabled \
				-Dlua=disabled \
				-Dpython=disabled \
				-Dtests=disabled \
				-Dzstd=disabled >/dev/null
		fi
		env PATH="$build_path" ninja -C build-macos src/apk >/dev/null
	)
}

find_external() {
	name="$1"
	shift

	if have_exec "$toolchain_bin/$name"; then
		printf '%s\n' "$toolchain_bin/$name"
		return 0
	fi

	old_path="${PATH-}"
	PATH="$search_path"
	if command -v "$name" >/dev/null 2>&1; then
		command -v "$name"
		PATH="$old_path"
		return 0
	fi
	PATH="$old_path"

	for candidate in "$@"; do
		if have_exec "$candidate"; then
			printf '%s\n' "$candidate"
			return 0
		fi
	done

	return 1
}

resolve_abuild_sign() {
	if ! have_exec "$repo_root/abuild/abuild-sign" || ! have_exec "$repo_root/abuild/abuild-tar" || [ ! -f "$repo_root/abuild/functions.sh" ]; then
		run_make abuild abuild-sign abuild-tar functions.sh abuild.conf || true
	fi
	if have_exec "$repo_root/abuild/abuild-sign" && have_exec "$repo_root/abuild/abuild-tar" && [ -f "$repo_root/abuild/functions.sh" ]; then
		printf '%s\n' "$repo_root/abuild/abuild-sign"
		return 0
	fi
	return 1
}

resolve_abuild_tar() {
	if ! have_exec "$repo_root/abuild/abuild-tar"; then
		run_make abuild abuild-tar || true
	fi
	if have_exec "$repo_root/abuild/abuild-tar"; then
		printf '%s\n' "$repo_root/abuild/abuild-tar"
		return 0
	fi
	return 1
}

resolve_update_kernel() {
	if ! have_exec "$repo_root/alpine-conf/update-kernel" || [ ! -f "$repo_root/alpine-conf/libalpine.sh" ] || [ ! -f "$repo_root/alpine-conf/dasd-functions.sh" ]; then
		run_make alpine-conf update-kernel libalpine.sh dasd-functions.sh || true
	fi
	if have_exec "$repo_root/alpine-conf/update-kernel" && [ -f "$repo_root/alpine-conf/libalpine.sh" ] && [ -f "$repo_root/alpine-conf/dasd-functions.sh" ]; then
		printf '%s\n' "$repo_root/alpine-conf/update-kernel"
		return 0
	fi
	return 1
}

resolve_mkinitfs() {
	if ! have_exec "$repo_root/mkinitfs/mkinitfs" || [ ! -f "$repo_root/mkinitfs/initramfs-init" ] || [ ! -f "$repo_root/mkinitfs/mkinitfs.conf" ]; then
		run_make mkinitfs mkinitfs initramfs-init mkinitfs.conf nlplug-findfs/nlplug-findfs || true
	fi
	if have_exec "$repo_root/mkinitfs/mkinitfs" && [ -f "$repo_root/mkinitfs/initramfs-init" ] && [ -f "$repo_root/mkinitfs/mkinitfs.conf" ]; then
		printf '%s\n' "$repo_root/mkinitfs/mkinitfs"
		return 0
	fi
	return 1
}

resolve_apk() {
	for candidate in \
		"$repo_root/apk-tools/build-macos/src/apk" \
		"$repo_root/apk-tools/src/apk" \
		"$repo_root/apk-tools/src/apk.static" \
		"$repo_root/apk-tools/build/src/apk" \
		"$repo_root/apk-tools/build/src/apk.static"; do
		if have_exec "$candidate"; then
			printf '%s\n' "$candidate"
			return 0
		fi
	done

	if resolved=$(find_external apk /sbin/apk /usr/sbin/apk); then
		printf '%s\n' "$resolved"
		return 0
	fi

	run_meson_apk_build || true

	for candidate in \
		"$repo_root/apk-tools/build-macos/src/apk" \
		"$repo_root/apk-tools/src/apk" \
		"$repo_root/apk-tools/src/apk.static" \
		"$repo_root/apk-tools/build/src/apk" \
		"$repo_root/apk-tools/build/src/apk.static"; do
		if have_exec "$candidate"; then
			printf '%s\n' "$candidate"
			return 0
		fi
	done

	return 1
}

resolve_grub_mkimage() {
	for candidate in \
		"$toolchain_bin/grub-mkimage" \
		"$grub_host_bin/grub-mkimage"; do
		if have_exec "$candidate"; then
			printf '%s\n' "$candidate"
			return 0
		fi
	done

	find_external grub-mkimage \
		"$grub_host_bin/grub-mkimage" \
		"/opt/homebrew/bin/grub-mkimage" \
		"/usr/local/bin/grub-mkimage" \
		"/opt/local/bin/grub-mkimage" \
		"/usr/bin/grub-mkimage"
}

resolve_tool() {
	case "$1" in
	apk)
		resolve_apk
		;;
	abuild-sign)
		resolve_abuild_sign
		;;
	abuild-tar)
		resolve_abuild_tar
		;;
	update-kernel)
		resolve_update_kernel
		;;
	mkinitfs)
		resolve_mkinitfs
		;;
	grub-mkimage)
		resolve_grub_mkimage
		;;
	xorrisofs|mksquashfs|fakeroot|mformat|mcopy|qemu-img|qemu-system-aarch64)
		find_external "$1" \
			"/opt/homebrew/bin/$1" \
			"/usr/local/bin/$1" \
			"/opt/local/bin/$1" \
			"/usr/bin/$1" \
			"/bin/$1"
		;;
	*)
		echo "unsupported tool: $1" >&2
		return 1
		;;
	esac
}

if ! resolved=$(resolve_tool "$tool"); then
	if [ "$mode" = "doctor" ]; then
		exit 1
	fi
	echo "$tool: no usable backend found" >&2
	exit 127
fi

if [ "$mode" = "doctor" ]; then
	printf '%s\n' "$resolved"
	exit 0
fi

case "$tool" in
abuild-sign)
	export ABUILD_SHAREDIR="$repo_root/abuild"
	export PATH="$wrapper_bin:$toolchain_bin:$search_path:$repo_root/abuild"
	exec "$resolved" "$@"
	;;
abuild-tar)
	export PATH="$wrapper_bin:$toolchain_bin:$search_path:$repo_root/abuild"
	exec "$resolved" "$@"
	;;
update-kernel)
	export LIBDIR="$repo_root/alpine-conf"
	export PATH="$wrapper_bin:$toolchain_bin:$search_path:$repo_root/alpine-conf:$repo_root/abuild"
	exec "$resolved" "$@"
	;;
mkinitfs)
	export SYSCONFDIR="$repo_root/mkinitfs"
	export DATADIR="$repo_root/mkinitfs"
	export PATH="$wrapper_bin:$toolchain_bin:$search_path"
	exec "$resolved" "$@"
	;;
*)
	export PATH="$wrapper_bin:$toolchain_bin:$grub_host_bin:$search_path"
	exec "$resolved" "$@"
	;;
esac
