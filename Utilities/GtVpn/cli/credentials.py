import contextlib
import getpass
import os
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


def _keyring(action, *args):
    try:
        import secretstorage
    except ImportError:
        return None
    try:
        with contextlib.closing(secretstorage.dbus_init()) as connection:
            collection = secretstorage.get_default_collection(connection)
            if collection.is_locked() and collection.unlock():
                return None
            return action(collection, *args)
    except secretstorage.exceptions.SecretStorageException:
        return None


def _keyring_store(collection, profile, password):
    attributes = {"service": profile.keychain.service, "username": profile.username}
    collection.create_item(profile.keychain.label, attributes, password.encode(), replace=True)
    return True


def _keyring_read(collection, profile):
    attributes = {"service": profile.keychain.service, "username": profile.username}
    for item in collection.search_items(attributes):
        if item.is_locked() and item.unlock():
            continue
        return item.get_secret().decode()
    return None


def _unlock_keychain():
    if subprocess.run(["security", "show-keychain-info"], capture_output=True).returncode == 0:
        return
    print("Your login keychain is locked; enter your Mac login password to unlock it.")
    if subprocess.run(["security", "unlock-keychain"]).returncode != 0:
        raise SystemExit("gtvpn: could not unlock the login keychain")


def store(profile):
    service = profile.keychain.service
    if profiles.system() == "macos":
        _unlock_keychain()
        print("Enter your GT password when asked (twice).")
        subprocess.run(
            ["security", "add-generic-password", "-U", "-s", service, "-a", profile.username, "-l", profile.keychain.label, "-w"],
            check=True,
        )
        return "the macOS Keychain"
    password = getpass.getpass("GT password: ")
    if not password:
        raise SystemExit("gtvpn: no password given")
    if _keyring(_keyring_store, profile, password):
        if _file().exists():
            _file().unlink()
        return "the login keyring"
    _write_file(password)
    return str(_file())


def read(profile):
    service = profile.keychain.service
    if profiles.system() == "macos":
        _unlock_keychain()
        result = subprocess.run(
            ["security", "find-generic-password", "-s", service, "-a", profile.username, "-w"],
            capture_output=True,
            text=True,
        )
        return result.stdout.rstrip("\n") if result.returncode == 0 else None
    found = _keyring(_keyring_read, profile)
    if found:
        return found
    if _file().exists():
        return _file().read_text().rstrip("\n")
    return None
