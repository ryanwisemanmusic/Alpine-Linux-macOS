#!/bin/sh
set -eu

state_file="$1"
shift || true

trap 'rm -f "$state_file"' EXIT HUP INT TERM
. "$state_file"
rm -f "$state_file"
trap - EXIT HUP INT TERM

if [ $# -eq 0 ]; then
	exec "${SHELL:-/bin/sh}"
fi

exec "$@"
