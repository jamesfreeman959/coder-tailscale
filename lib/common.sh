# shellcheck shell=bash
# Shared settings and helpers for the coder-tailscale scripts.
# Sourced by bin/* and shell/bashrc.sh; not meant to be run directly.

# Optional per-user overrides (TS_PERSIST, TS_HOSTNAME, TS_UP_FLAGS, ...).
TS_CONFIG="${TS_CONFIG:-$HOME/.config/coder-tailscale.env}"
# shellcheck disable=SC1090
[ -f "$TS_CONFIG" ] && . "$TS_CONFIG"

TS_HOME="${TS_HOME:-$HOME/.local/share/tailscale}"
TS_SOCKET="${TS_SOCKET:-$TS_HOME/tailscaled.sock}"
TS_LOG="$TS_HOME/tailscaled.log"
TS_PIDFILE="$TS_HOME/tailscaled.pid"
TS_LOCK="$TS_HOME/tailscaled.lock"

# 0 = ephemeral (state in memory; log in after every daemon start, node
#     disappears from the tailnet when the daemon stops). Default.
# 1 = persistent (state file in $TS_HOME; log in once per workspace).
TS_PERSIST="${TS_PERSIST:-0}"

TS_HOSTNAME="${TS_HOSTNAME:-coder-${CODER_WORKSPACE_NAME:-$(hostname)}}"
# Extra flags for `tailscale up`, e.g. "--accept-routes".
TS_UP_FLAGS="${TS_UP_FLAGS:-}"

TS_MISE_TOOL="aqua:tailscale/tailscale"

ts_die() { echo "coder-tailscale: $*" >&2; exit 1; }

# Resolve the tailscale/tailscaled binaries through mise. `mise exec` with an
# explicit tool works from any directory (no mise.toml needed) and installs
# the tool if it's missing.
ts_resolve_bins() {
	[ -n "${TAILSCALE:-}" ] && [ -n "${TAILSCALED:-}" ] && return 0
	command -v mise >/dev/null || ts_die "mise not found on PATH"
	local bins
	bins=$(mise exec "$TS_MISE_TOOL" -- sh -c 'command -v tailscale; command -v tailscaled') ||
		ts_die "could not resolve $TS_MISE_TOOL via mise"
	TAILSCALE=$(echo "$bins" | sed -n 1p)
	TAILSCALED=$(echo "$bins" | sed -n 2p)
	[ -x "$TAILSCALE" ] && [ -x "$TAILSCALED" ] || ts_die "tailscale binaries not found"
}

ts_cli() { "$TAILSCALE" --socket="$TS_SOCKET" "$@"; }

# True if a tailscaled is answering on our socket.
ts_daemon_alive() {
	[ -S "$TS_SOCKET" ] && ts_cli version --daemon >/dev/null 2>&1
}

# NoState, NeedsLogin, NeedsMachineAuth, Stopped, Starting, Running, or
# "Down" if the daemon isn't reachable.
ts_backend_state() {
	local state
	state=$(ts_cli status --json --peers=false 2>/dev/null |
		sed -n 's/^[[:space:]]*"BackendState":[[:space:]]*"\([^"]*\)".*/\1/p')
	echo "${state:-Down}"
}

# Start tailscaled in userspace mode if it isn't already running.
# Safe to call from several shells at once (flock).
ts_ensure_daemon() {
	mkdir -p "$TS_HOME"
	chmod 700 "$TS_HOME"
	(
		flock -w 30 9 || ts_die "timed out waiting for $TS_LOCK"
		ts_daemon_alive && exit 0

		local state_arg
		if [ "$TS_PERSIST" = 1 ]; then
			state_arg="--state=$TS_HOME/tailscaled.state"
		else
			state_arg="--state=mem:"
		fi

		rm -f "$TS_SOCKET"
		setsid nohup "$TAILSCALED" \
			--tun=userspace-networking \
			"$state_arg" \
			--statedir="$TS_HOME" \
			--socket="$TS_SOCKET" \
			>"$TS_LOG" 2>&1 </dev/null 9>&- &
		echo $! >"$TS_PIDFILE"

		local i
		for i in $(seq 1 50); do
			ts_daemon_alive && exit 0
			sleep 0.2
		done
		ts_die "tailscaled did not come up; see $TS_LOG"
	) 9>"$TS_LOCK"
}

ts_stop_daemon() {
	local pid
	pid=$(cat "$TS_PIDFILE" 2>/dev/null || true)
	if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
		kill "$pid"
		local i
		for i in $(seq 1 25); do
			kill -0 "$pid" 2>/dev/null || break
			sleep 0.2
		done
	fi
	# Fallback for a daemon started some other way on our socket.
	pkill -u "$(id -u)" -f -- "^$TAILSCALED .*--socket=$TS_SOCKET" 2>/dev/null || true
	rm -f "$TS_PIDFILE" "$TS_SOCKET"
}
