# gtvpn

Install Bazelisk: https://github.com/bazelbuild/bazelisk#installation

Build:

```bash
bazel build //Utilities/GtVpn:gtvpn
```

Install:

```bash
./bazel-bin/Utilities/GtVpn/gtvpn setup
```

On Linux, split DNS needs systemd-resolved.

Run:

```bash
gtvpn connect
```

Commands:

| Command | Does |
|---|---|
| `gtvpn setup` | Asks for your GT username and password, saves the password in the macOS Keychain or the Linux login keyring (`~/.config/gtvpn/password` when no keyring is running), and installs `gtvpn` into `/usr/local/bin` |
| `gtvpn connect` (`up`, `on`) | Connects to the DC gateway (the NI gateway if DC fails) and sends a Duo push; only GT networks and `*.gatech.edu` names go through the VPN |
| `gtvpn disconnect` (`down`, `off`) | Logs off and removes the VPN routes |
| `gtvpn status` | Shows whether the VPN is up and its tunnel addresses (the default command) |
| `gtvpn log` | Shows the last 50 lines of the VPN log |
| `gtvpn version` | Shows the version and build |

Maintained by Nana Gupta <ananay@gatech.edu>.
