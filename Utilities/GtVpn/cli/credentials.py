import getpass
import os
import shutil
import subprocess

from Utilities.GtVpn.cli import profile as profiles


def _file():
    return profiles.config_dir() / "password"


def _write_file(password):
    path = _file()
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(descriptor, "w") as handle:
        handle.write(password)
    os.chmod(path, 0o600)


def _secret_tool(*args, password=None):
    if not shutil.which("secret-tool"):
        return None
    result = subprocess.run(["secret-tool", *args], input=password, capture_output=True, text=True)
    return result if result.returncode == 0 else None


def store(profile):
    service = profile.keychain.service
    if profiles.system() == "macos":
        print("Enter your GT password when asked (twice).")
        subprocess.run(
            ["security", "add-generic-password", "-U", "-s", service, "-a", profile.username, "-l", profile.keychain.label, "-w"],
            check=True,
        )
        return "the macOS Keychain"
    password = getpass.getpass("GT password: ")
    if not password:
        raise SystemExit("gtvpn: no password given")
    if _secret_tool("store", "--label=" + profile.keychain.label, "service", service, "username", profile.username, password=password):
        if _file().exists():
            _file().unlink()
        return "the login keyring"
    _write_file(password)
    return str(_file())


def read(profile):
    service = profile.keychain.service
    if profiles.system() == "macos":
        result = subprocess.run(
            ["security", "find-generic-password", "-s", service, "-a", profile.username, "-w"],
            capture_output=True,
            text=True,
        )
        return result.stdout.rstrip("\n") if result.returncode == 0 else None
    found = _secret_tool("lookup", "service", service, "username", profile.username)
    if found and found.stdout:
        return found.stdout.rstrip("\n")
    if _file().exists():
        return _file().read_text().rstrip("\n")
    return None
