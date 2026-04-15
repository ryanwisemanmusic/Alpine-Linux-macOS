#!/bin/sh

set -eu

script_dir=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
harness_dir=$(CDPATH= cd -- "$script_dir/.." && pwd)
wrapper_bin="$harness_dir/bin"
tool_shim="$script_dir/tool-shim.sh"

mkdir -p "$wrapper_bin"

for tool in \
	apk \
	abuild-sign \
	abuild-tar \
	update-kernel \
	mkinitfs \
	xorrisofs \
	mksquashfs \
	fakeroot \
	mformat \
	mcopy \
	grub-mkimage \
	qemu-system-aarch64 \
	qemu-img; do
	cat > "$wrapper_bin/$tool" <<EOF
#!/bin/sh
exec "$tool_shim" "$tool" "\$@"
EOF
	chmod +x "$wrapper_bin/$tool"
done

# Add small local helpers to improve macOS compatibility for builds:
# - `nproc`: return number of CPUs
# - `date`: minimal GNU-compatible support for -d "@SECONDS" and +FORMAT with -u
cat > "$wrapper_bin/nproc" <<'EOF'
#!/bin/sh
case "$(uname -s)" in
Darwin)
	sysctl -n hw.ncpu 2>/dev/null || echo 1
	;;
*)
	if command -v getconf >/dev/null 2>&1; then
		getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1
	else
		echo 1
	fi
	;;
esac
EOF
chmod +x "$wrapper_bin/nproc"

cat > "$wrapper_bin/date" <<'EOF'
#!/bin/sh
# Minimal GNU-date-compatible wrapper handling: -u, -d "@SECONDS", +FORMAT
utc=""
epoch=""
format=""
other=""
while [ $# -gt 0 ]; do
	case "$1" in
		-u) utc=1; shift ;;
		-d) shift; datearg="$1"; shift
			if [ "${datearg#@}" != "$datearg" ]; then
				epoch="${datearg#@}"
			else
				date_str="$datearg"
			fi
			;;
		+*) format="$1"; shift ;;
		*) other="$other \"$1\""; shift ;;
	esac
done

if [ -n "$epoch" ]; then
	if [ -n "$format" ]; then
		if [ -n "$utc" ]; then
			/bin/date -u -r "$epoch" "$format"
		else
			/bin/date -r "$epoch" "$format"
		fi
	else
		if [ -n "$utc" ]; then
			/bin/date -u -r "$epoch"
		else
			/bin/date -r "$epoch"
		fi
	fi
	exit $?
fi

# fallback to system date for other cases
eval exec /bin/date $other
EOF
chmod +x "$wrapper_bin/date"
