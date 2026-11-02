import argparse
import os
import pathlib
import shlex
import shutil
import subprocess
import sys
import time

from Utilities.GtVpn.cli import credentials
from Utilities.GtVpn.cli import profile as profiles

OPENCONNECT = profiles.ROOT / "Third-Party" / "OpenConnect" / "openconnect_install" / "sbin" / "openconnect"
APP = profiles.ROOT.parent.parent.parent


def die(message):
    raise SystemExit("gtvpn: " + message)


def ask(prompt, current):
    shown = " [%s]" % current if current else ""
    answer = input("%s%s: " % (prompt, shown)).strip()
    return answer or current


def notify(text):
    if profiles.system() == "macos":
        command = ["osascript", "-e", 'display notification "%s" with title "GT VPN"' % text]
    elif shutil.which("notify-send"):
        command = ["notify-send", "GT VPN", text]
    else:
        return
    subprocess.run(command, capture_output=True)


def sudo(*command, **kwargs):
    return subprocess.run(["sudo", *command], **kwargs)


def alive(pid):
    return subprocess.run(["ps", "-p", str(pid)], capture_output=True).returncode == 0


def wait_exit(pid, seconds):
    for _ in range(seconds):
        if not alive(pid):
            return True
        time.sleep(1)
    return not alive(pid)


def running(profile):
    try:
        pid = int(pathlib.Path(profile.pid_file).read_text().strip())
    except (OSError, ValueError):
        return None
    return pid if alive(pid) else None


def launcher(profile):
    folder = "MacOS" if profiles.system() == "macos" else "Linux"
    return pathlib.Path(profile.install_dir) / "app" / "Contents" / folder / "gtvpn"


def payload():
    stamp = APP / ".payload"
    return stamp.read_text().strip() if stamp.exists() else APP.name


def installed(profile):
    stamp = pathlib.Path(profile.install_dir) / "app" / ".payload"
    try:
        current = stamp.read_text().strip() == payload()
    except OSError:
        return False
    return current and (pathlib.Path(profile.install_dir) / "openconnect").exists()


def install(profile):
    if not OPENCONNECT.exists():
        die("this build carries no openconnect at %s" % OPENCONNECT)
    target = pathlib.Path(profile.install_dir)
    staged = target / "app.new"
    command = pathlib.Path(profile.command_dir) / "gtvpn"
    q = shlex.quote
    wrapper = "#!/bin/sh\nexec %s \"$@\"\n" % q(str(launcher(profile)))
    script = "\n".join([
        "set -eu",
        "mkdir -p %s %s" % (q(str(target)), q(profile.cache_dir)),
        "rm -rf %s" % q(str(staged)),
        "cp -R %s %s" % (q(str(APP)), q(str(staged))),
        "printf '%%s\\n' %s > %s" % (q(payload()), q(str(staged / ".payload"))),
        "chown -R 0:0 %s" % q(str(staged)),
        "chmod -R go-w %s" % q(str(staged)),
        "rm -rf %s" % q(str(target / "app")),
        "mv %s %s" % (q(str(staged)), q(str(target / "app"))),
        "install -m 0755 %s %s" % (q(str(OPENCONNECT)), q(str(target / "openconnect"))),
        "chown 0:0 %s" % q(str(target / "openconnect")),
        "mkdir -p %s" % q(profile.command_dir),
        "printf %%s %s > %s" % (q(wrapper), q(str(command))),
        "chmod 0755 %s" % q(str(command)),
    ])
    print("Installing the VPN helpers into %s (needs your computer password)." % target)
    sudo("sh", "-c", script, check=True)
    sudo("env", "GTVPN_CACHE=" + profile.cache_dir, str(launcher(profile)), "version", check=True, stdout=subprocess.DEVNULL)


def cmd_setup(args):
    user = profiles.load_user()
    merged = profiles.load()
    user.username = ask("GT username (e.g. gburdell3)", merged.username)
    user.gateway = ask("VPN gateway host", merged.gateway)
    domains = ask("Domains to resolve through the VPN, comma separated (blank for none)", ",".join(merged.dns_domains))
    del user.dns_domains[:]
    user.dns_domains.extend([domain.strip() for domain in domains.split(",") if domain.strip()])
    if not user.username or not user.gateway:
        die("a username and a gateway are both needed")
    profiles.save_user(user)
    merged = profiles.load()
    where = credentials.store(merged)
    print("Saved your login in %s and your settings in %s." % (where, profiles.user_path()))
    install(merged)
    print("Ready. From now on: gtvpn connect, gtvpn disconnect, gtvpn status")


def slice_arguments(profile):
    arguments = []
    if profile.verbose:
        arguments.append("-v")
    if profile.keepalive.dns_probe:
        arguments.append("-K")
    if profile.dns_domains:
        arguments += ["--domains-vpn-dns", ",".join(profile.dns_domains)]
    return arguments + list(profile.routes)


def slice_script(profile):
    q = shlex.quote
    command = ["GTVPN_CACHE=" + q(profile.cache_dir), q(str(launcher(profile))), "slice"]
    command += [q(argument) for argument in slice_arguments(profile)]
    return " ".join(command) + " >>%s 2>&1" % q(profile.log_file)


def cmd_connect(args):
    profile = profiles.load()
    pid = running(profile)
    if pid:
        print("Already connected (pid %d)." % pid)
        return
    if not profile.username or not profile.gateway:
        die("not set up yet; run: gtvpn setup")
    if not installed(profile):
        die("the VPN helpers are missing or from another build; run: gtvpn setup")
    password = credentials.read(profile)
    if password is None:
        die("no saved password; run: gtvpn setup")
    if sudo("-n", "true", capture_output=True).returncode != 0:
        sudo("-v", check=True)
    print("Connecting to %s as %s. Approve the Duo push on your phone." % (profile.gateway, profile.username))
    notify("Approve the Duo push on your phone to connect.")
    command = [
        str(pathlib.Path(profile.install_dir) / "openconnect"),
        "--protocol=" + profile.protocol,
        "--user=" + profile.username,
        "--usergroup=" + profile.usergroup,
        "--script=" + slice_script(profile),
        "--passwd-on-stdin",
        "--background",
        "--pid-file=" + profile.pid_file,
        profile.gateway,
    ]
    result = sudo(*command, input="%s\n%s\n" % (password, profile.mfa.auto_response), text=True)
    del password
    pid = None
    for _ in range(10):
        pid = running(profile)
        if pid:
            break
        time.sleep(1)
    if result.returncode != 0 or not pid:
        die("connection failed; see the messages above")
    print("Connected (pid %d)." % pid)
    notify("Connected to the GT VPN.")


def cmd_disconnect(args):
    profile = profiles.load()
    pid = running(profile)
    if not pid:
        print("Not connected.")
        return
    sudo("kill", "-INT", str(pid), check=True)
    print("Logging off...")
    if not wait_exit(pid, 30):
        sudo("kill", "-TERM", str(pid), capture_output=True)
    if not wait_exit(pid, 5):
        die("openconnect (pid %d) did not exit" % pid)
    sudo("rm", "-f", profile.pid_file)
    print("Disconnected.")
    notify("Disconnected from the GT VPN.")


def tunnels():
    if profiles.system() == "macos":
        output = subprocess.run(["ifconfig"], capture_output=True, text=True).stdout
        found, interface = [], None
        for line in output.splitlines():
            if line and not line[0].isspace():
                interface = line.split(":")[0]
            elif interface and interface.startswith("utun") and line.strip().startswith("inet "):
                found.append("%s %s" % (interface, line.split()[1]))
        return found
    output = subprocess.run(["ip", "-o", "-4", "addr", "show"], capture_output=True, text=True).stdout
    return ["%s %s" % (fields[1], fields[3]) for fields in (line.split() for line in output.splitlines()) if fields[1].startswith("tun")]


def cmd_status(args):
    profile = profiles.load()
    pid = running(profile)
    if not pid:
        print("Not connected.")
        return
    print("Connected to %s (pid %d)." % (profile.gateway, pid) if profile.gateway else "Connected (pid %d)." % pid)
    for tunnel in tunnels():
        print("  " + tunnel)


def cmd_log(args):
    profile = profiles.load()
    try:
        lines = pathlib.Path(profile.log_file).read_text(errors="replace").splitlines()
    except OSError as error:
        die("cannot read %s: %s" % (profile.log_file, error.strerror))
    print("\n".join(lines[-50:]))


def resolve_domains(domains):
    device = os.environ.get("TUNDEV")
    servers = os.environ.get("INTERNAL_IP4_DNS", "").split()
    if not device or not servers or not shutil.which("resolvectl"):
        print("gtvpn: split DNS needs systemd-resolved; skipping", file=sys.stderr)
        return
    subprocess.run(["resolvectl", "dns", device, *servers])
    subprocess.run(["resolvectl", "domain", device, *["~" + domain for domain in domains]])


def cmd_slice(args):
    arguments = list(args.arguments)
    if profiles.system() == "linux" and "--domains-vpn-dns" in arguments:
        index = arguments.index("--domains-vpn-dns")
        domains = arguments[index + 1].split(",")
        del arguments[index:index + 2]
        if os.environ.get("reason") == "connect":
            resolve_domains(domains)
    from vpn_slice.__main__ import main

    main(arguments)


def cmd_version(args):
    print("gtvpn %s" % payload()[:12])


COMMANDS = {
    "setup": cmd_setup,
    "connect": cmd_connect,
    "up": cmd_connect,
    "on": cmd_connect,
    "disconnect": cmd_disconnect,
    "down": cmd_disconnect,
    "off": cmd_disconnect,
    "status": cmd_status,
    "log": cmd_log,
    "slice": cmd_slice,
    "version": cmd_version,
}


def main(argv=None):
    parser = argparse.ArgumentParser(prog="gtvpn", usage="gtvpn {setup|connect|disconnect|status|log}")
    parser.add_argument("command", nargs="?", default="status", choices=sorted(COMMANDS))
    parser.add_argument("arguments", nargs=argparse.REMAINDER)
    args = parser.parse_args(argv)
    COMMANDS[args.command](args)


if __name__ == "__main__":
    main()
