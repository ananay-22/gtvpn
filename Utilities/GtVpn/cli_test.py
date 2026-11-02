import pathlib
import socket
import tempfile
import unittest

from Utilities.GtVpn.Proto import profile_pb2
from Utilities.GtVpn.cli import __main__ as cli
from Utilities.GtVpn.cli import profile as profiles


class ProfileTest(unittest.TestCase):
    def test_every_platform_default_parses_and_names_its_paths(self):
        for system in ("linux", "macos"):
            path = profiles.ROOT / "Utilities" / "GtVpn" / "Defaults" / system / "GtVpn" / "Profile.pbtxt"
            profile = profiles.parse(path)
            self.assertEqual(profile.protocol, "gp")
            self.assertTrue(profile.routes)
            for field in ("pid_file", "log_file", "install_dir", "cache_dir", "command_dir"):
                self.assertTrue(getattr(profile, field).startswith("/"), (system, field))
            self.assertFalse(profile.gateway)
            self.assertFalse(profile.dns_domains)

    def test_user_fields_replace_defaults_and_keep_the_rest(self):
        user = profile_pb2.Profile(gateway="gw.example.org", username="someone", routes=["10.1.0.0/16"])
        with tempfile.TemporaryDirectory() as directory:
            path = pathlib.Path(directory) / "Profile.pbtxt"
            profiles.save_user(user, path)
            merged = profiles.load(path)
        self.assertEqual(list(merged.routes), ["10.1.0.0/16"])
        self.assertEqual(merged.gateway, "gw.example.org")
        self.assertEqual(merged.protocol, "gp")
        self.assertEqual(merged.mfa.auto_response, "1")

    def test_slice_script_quotes_and_logs(self):
        profile = profiles.load(pathlib.Path("/nonexistent"))
        profile.dns_domains.extend(["a.example.org", "b.example.org"])
        script = cli.slice_script(profile)
        self.assertIn("GTVPN_CACHE=" + profile.cache_dir, script)
        self.assertIn(" slice --no-fork -v --keepalive --domains-vpn-dns a.example.org,b.example.org 128.61.0.0/16 ", script)
        self.assertTrue(script.endswith(" >>/var/log/gtvpn.log 2>&1"))


    def test_tunnel_up_follows_the_interface(self):
        self.assertTrue(cli.tunnel_up(socket.if_nameindex()[0][1]))
        self.assertFalse(cli.tunnel_up("gtvpn-none"))


if __name__ == "__main__":
    unittest.main()
