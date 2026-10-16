# shellcheck shell=bash
# Sourced from ~/.bashrc by install.sh. Interactive shells only.
case $- in *i*) ;; *) return 0 ;; esac

alias tailscale=ts

# Start the daemon in the background on the first shell after a container
# (re)start, and say whether you still need to log in. Set TS_AUTOSTART=0 in
# ~/.config/coder-tailscale.env to turn this off. Runs in a subshell so
# nothing here can exit or pollute your shell.
(
	# shellcheck disable=SC1091
	. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../lib/common.sh"
	[ "${TS_AUTOSTART:-1}" = 1 ] || exit 0
	ts_resolve_bins
	ts_ensure_daemon >/dev/null 2>&1 || {
		echo "tailscale: daemon failed to start (see $TS_LOG)"
		exit 0
	}
	[ "$(ts_backend_state)" = Running ] ||
		echo "tailscale: not logged in. Run 'ts-up' to connect this workspace."
)
