import os
import pathlib
import sys

from google.protobuf import text_format

from Utilities.GtVpn.Proto import profile_pb2

ROOT = pathlib.Path(os.path.abspath(__file__)).parents[3]


def system():
    if sys.platform.startswith("linux"):
        return "linux"
    if sys.platform == "darwin":
        return "macos"
    raise SystemExit("gtvpn runs on Linux and macOS, not %s" % sys.platform)


def config_dir():
    if system() == "macos":
        return pathlib.Path.home() / "Library" / "Application Support" / "GtVpn"
    base = os.environ.get("XDG_CONFIG_HOME") or str(pathlib.Path.home() / ".config")
    return pathlib.Path(base) / "gtvpn"


def defaults_path():
    return ROOT / "Utilities" / "GtVpn" / "Defaults" / system() / "GtVpn" / "Profile.pbtxt"


def user_path():
    return config_dir() / "Profile.pbtxt"


def parse(path):
    profile = profile_pb2.Profile()
    text_format.Parse(path.read_text(), profile)
    return profile


def overlay(base, top):
    merged = profile_pb2.Profile()
    merged.CopyFrom(base)
    for field, _ in top.ListFields():
        merged.ClearField(field.name)
    merged.MergeFrom(top)
    return merged


def load_user(path=None):
    path = path or user_path()
    return parse(path) if path.exists() else profile_pb2.Profile()


def load(path=None):
    return overlay(parse(defaults_path()), load_user(path))


def save_user(profile, path=None):
    path = path or user_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text_format.MessageToString(profile))
