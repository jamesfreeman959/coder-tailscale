# coder-tailscale

Run Tailscale **inside** a Coder dev container, as an unprivileged user, so a
workspace can SSH across the tailnet with Tailscale SSH **check mode**.

```bash
./install.sh   # once per workspace (home is persistent)
ts-up          # after each container start: prints a login URL, approve it on your laptop
ts ssh user@host
```

## Why

### The problem with a shared, tagged gateway

A common setup is one tagged tailnet device (e.g. `tag:gateway`) acting as the
gateway for every workspace. Plain OpenSSH from that device to tailnet hosts
fails, even when the policy grants TCP 22:

- When a node runs **Tailscale SSH** (`tailscale up --ssh`), `tailscaled`
  takes over port 22 on that node's tailnet IP. Every incoming connection is
  checked against the policy's `ssh` rules, and there's **no fallback to
  OpenSSH**. A source with no matching `ssh` rule is rejected ("tailnet policy
  does not permit you to SSH to this node") before `sshd` sees it.
- **Check mode can't apply to a tagged source.** Check mode makes the *user*
  behind the connection re-authenticate in a browser. A tagged device has no
  owning user, so there's nobody to prompt, and the policy won't validate a
  `check` rule with a tagged `src`.

The workarounds each cost something:

| Option | Cost |
|---|---|
| Run OpenSSH on a second port (e.g. 2222) on every target, grant it to the tag | Config change on every target host |
| Turn off Tailscale SSH on the targets | Lose check mode from your laptop too |
| SSH to LAN IPs through a subnet router | Only covers LAN hosts; broadens the gateway's grant |
| Tailscale SSH `accept` rule for the tag | No per-session prompt; any workspace process can SSH unprompted |
| Untag the gateway, log it in as you | Every workspace shares your full identity |

### What this repo does instead

Each workspace runs its **own** `tailscaled`, logged in **as you** (a user
identity, not a tag). Your existing user-identity `check` rules then apply as
they are:

- `ts ssh host` prints an approval URL, which you approve on your laptop.
- No changes on the target hosts, and no policy change needed.
- Each workspace is a separate device. By default it's **ephemeral**: it
  disappears from the tailnet when the workspace stops.

## How it works

- **Binary:** installed through mise (`aqua:tailscale/tailscale`). The scripts
  resolve it with `mise exec aqua:tailscale/tailscale -- …`, so it works from
  any directory and doesn't depend on mise's shell activation.
- **No root:** `tailscaled --tun=userspace-networking` needs no `NET_ADMIN`,
  no `/dev/net/tun`, and adds no kernel routes. That also keeps it clear of
  Coder's own agent networking, which is built on Tailscale code too.
- **Socket and state under `~`:** the defaults (`/var/run/tailscale/…`) need
  root, so everything lives in `~/.local/share/tailscale/`. Every CLI call
  needs `--socket`, which is what the `ts` wrapper adds.
- **No tailnet interface:** in userspace mode the OS can't route to
  `100.x.y.z`, so plain `ssh` needs a `ProxyCommand` through `tailscale nc`.
  `ts ssh` handles this itself.

## Setup

```bash
git clone <this repo> ~/coder-tailscale   # anywhere under your persistent home
cd ~/coder-tailscale
./install.sh
. ~/.bashrc   # or open a new terminal
ts-up
```

`install.sh` is idempotent. It:

1. Runs `mise use -g aqua:tailscale/tailscale@latest`.
2. Symlinks `ts`, `ts-up` and `ts-down` into `~/.local/bin`.
3. Adds one line to `~/.bashrc` that sources `shell/bashrc.sh`.
4. Adds `Include …/ssh/config` at the top of `~/.ssh/config`.

## Daily use

After a container start or restart, open a terminal. The `.bashrc` hook starts
`tailscaled` in the background and tells you if you need to log in:

```
tailscale: not logged in. Run 'ts-up' to connect this workspace.
```

Run `ts-up`, open the URL on your laptop, and you're connected.

| Command | What it does |
|---|---|
| `ts-up` | Start the daemon if needed, then `tailscale up` if not connected |
| `ts-up --daemon-only` | Just make sure the daemon is running (startup scripts) |
| `ts-up -- --accept-routes` | Pass extra flags to `tailscale up` |
| `ts …` | `tailscale --socket=… …` (also aliased as `tailscale`) |
| `ts-down` | Stop the daemon (logs out first in ephemeral mode) |
| `ts-down --logout` | Log out and stop, in either mode |

### SSH

```bash
ts ssh user@host                    # Tailscale SSH; check mode applies
ssh host.your-tailnet.ts.net        # OpenSSH via ProxyCommand (see ssh/config)
ssh 100.101.102.103                 # same
```

`ssh/config` routes `*.ts.net` and `100.*` through `ts nc`. To use short
MagicDNS names, add them to the `Host` line, or add your own block to
`~/.ssh/config`:

```
Host host1 host2
	ProxyCommand ~/.local/bin/ts nc %h %p
```

For hosts that don't run Tailscale SSH, plain OpenSSH over the tailnet works
as usual: keys, agent forwarding and all.

## Configuration

Optional overrides go in `~/.config/coder-tailscale.env` (sourced as shell):

```bash
TS_PERSIST=1               # keep login across daemon restarts (see below)
TS_HOSTNAME=my-workspace   # default: coder-$CODER_WORKSPACE_NAME
TS_UP_FLAGS="--accept-routes"
TS_AUTOSTART=0             # don't start the daemon from .bashrc
```

### Ephemeral vs persistent

| | `TS_PERSIST=0` (default) | `TS_PERSIST=1` |
|---|---|---|
| State | In memory (`--state=mem:`) | `~/.local/share/tailscale/tailscaled.state` |
| Login | After every daemon start | Once per workspace |
| Device list | Removed when the daemon stops | Stays, offline when stopped |
| Node key on disk | No | Yes, in the workspace's home volume |
| Key expiry | n/a | User devices expire (default 180 days) |

Ephemeral is the default because a persistent login leaves credentials for
your full identity on disk in the workspace. One browser click per restart is
the price.

### Coder template (optional)

The `.bashrc` hook only starts the daemon when you open a terminal. To have it
running as soon as the workspace starts (e.g. for a VS Code remote session
that never opens a shell), add this to the agent's `startup_script`:

```bash
~/coder-tailscale/install.sh >/dev/null   # wherever you cloned it
~/.local/bin/ts-up --daemon-only
```

Login still has to be interactive. Don't bake an auth key into the template:
an untagged key would give anyone who sees it your identity on the tailnet.

## Security notes

- **Reach:** the workspace gets **everything your user identity is granted**
  in the tailnet policy, not a narrow per-device grant. Tailscale SSH stays
  gated by check mode, but anything running in the workspace can open other
  connections (HTTPS, APIs, …) without a prompt while it's logged in. If you
  need to narrow that, look at device posture conditions (`srcPosture`) in the
  policy.
- **Check period:** a check is valid for the check period (12h by default).
- `~/.local/share/tailscale` is `chmod 700`. The socket inside it controls the
  daemon.

## Troubleshooting

- **`tailscale` not on PATH:** mise only puts tools on the PATH in interactive
  shells, and only for directories whose `mise.toml` lists them. Use `ts`, or
  `mise use -g aqua:tailscale/tailscale` (which `install.sh` does).
- **`failed to connect to local tailscaled`:** you ran the real `tailscale`
  without `--socket`. Use `ts`.
- **Daemon won't start:** check `~/.local/share/tailscale/tailscaled.log`.
- **Stuck lock or stale daemon:** `ts-down`, then `ts-up`.
- **`ssh 100.x.y.z` hangs:** the `Include` is missing from `~/.ssh/config`, or
  comes after a `Host` block. It must be at the top.

## Layout

```
install.sh         one-time setup (idempotent)
bin/ts             tailscale CLI wrapper (adds --socket)
bin/ts-up          start daemon + log in
bin/ts-down        log out (ephemeral) + stop daemon
lib/common.sh      shared settings and helpers
shell/bashrc.sh    alias, daemon autostart, login hint
ssh/config         ProxyCommand for tailnet hosts
```

## License

[MIT](LICENSE)
