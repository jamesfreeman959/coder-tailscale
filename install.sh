#!/usr/bin/env bash
# One-time setup for a workspace. Idempotent: safe to re-run, or to run from a
# Coder startup script on every start.
#
#   - installs tailscale globally through mise
#   - links ts, ts-up and ts-down into ~/.local/bin
#   - adds a source line to ~/.bashrc, and ~/.zshrc if zsh is installed
#     (alias + login hint + daemon autostart)
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
rc_line="[ -f \"$here/shell/rc.sh\" ] && . \"$here/shell/rc.sh\"  # coder-tailscale"
for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
	if [ "$rc" = "$HOME/.zshrc" ] && ! command -v zsh >/dev/null && [ ! -f "$rc" ]; then
		continue
	fi
	if grep -qF "# coder-tailscale" "$rc" 2>/dev/null; then
		echo "    $(basename "$rc"): already present"
	else
		printf '\n%s\n' "$rc_line" >>"$rc"
		echo "    $(basename "$rc"): added"
	fi
done

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
echo "Done. Open a new terminal, then run: ts-up"
