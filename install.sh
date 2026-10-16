#!/usr/bin/env bash
# One-time setup for a workspace. Idempotent: safe to re-run, or to run from a
# Coder startup script on every start.
#
#   - installs tailscale globally through mise
#   - links ts, ts-up and ts-down into ~/.local/bin
#   - adds a source line to ~/.bashrc (alias + login hint + daemon autostart)
#   - adds an Include to ~/.ssh/config for tailnet hosts
set -euo pipefail
here="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
. "$here/lib/common.sh"

echo "==> mise: $TS_MISE_TOOL (global)"
mise use -g "$TS_MISE_TOOL@latest"

echo "==> linking commands into ~/.local/bin"
mkdir -p "$HOME/.local/bin"
for cmd in ts ts-up ts-down; do
	chmod +x "$here/bin/$cmd"
	ln -sfn "$here/bin/$cmd" "$HOME/.local/bin/$cmd"
done

echo "==> ~/.bashrc"
bashrc_line="[ -f \"$here/shell/bashrc.sh\" ] && . \"$here/shell/bashrc.sh\"  # coder-tailscale"
if grep -qF "# coder-tailscale" "$HOME/.bashrc" 2>/dev/null; then
	echo "    already present"
else
	printf '\n%s\n' "$bashrc_line" >>"$HOME/.bashrc"
	echo "    added"
fi

echo "==> ~/.ssh/config"
mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"
include_line="Include $here/ssh/config"
touch "$HOME/.ssh/config"
chmod 600 "$HOME/.ssh/config"
if grep -qxF "$include_line" "$HOME/.ssh/config"; then
	echo "    already present"
else
	# Include must come before any Host block to apply globally.
	tmp=$(mktemp)
	{ echo "$include_line"; echo; cat "$HOME/.ssh/config"; } >"$tmp"
	cat "$tmp" >"$HOME/.ssh/config"
	rm -f "$tmp"
	echo "    added"
fi

echo
echo "Done. Open a new terminal (or: . ~/.bashrc), then run: ts-up"
