_RELEASE = "20260901"
_RELEASES = "https://github.com/astral-sh/python-build-standalone/releases/download/"

_FULL = {
    "3.10": "3.10.21",
    "3.11": "3.11.16",
    "3.12": "3.12.14",
    "3.13": "3.13.15",
    "3.14": "3.14.7",
}

def _asset(minor, slug, extension, sha256):
    version = _FULL[minor]
    path = "%s/cpython-%s+%s-%s.%s" % (_RELEASE, version, _RELEASE, slug, extension)
    return struct(
        version = version,
        path = path,
        url = _RELEASES + path.replace("+", "%2B"),
        sha256 = sha256,
    )

def _gnu(minor, triple, sha256):
    return _asset(minor, triple + "-install_only_stripped", "tar.gz", sha256)

def _musl(minor, sha256):
    return _asset(minor, "x86_64-unknown-linux-musl-lto+static-full", "tar.zst", sha256)

PLATFORM_INTERPRETERS = {
    "linux_x86_64": {
        "3.10": _gnu("3.10", "x86_64-unknown-linux-gnu", "a85d82bf451beea4605cecf0ad3e6cfdab833f146da8f1f82c7b7786f3ff3e3a"),
        "3.11": _gnu("3.11", "x86_64-unknown-linux-gnu", "64427febea27864d136db46c8efe968eb6fa5ca2813ce1dca4bb95aec31cb2e4"),
        "3.12": _gnu("3.12", "x86_64-unknown-linux-gnu", "72748da13197c1fb161e3afeef20a6a385ff24f2165e6e2758e47008e7faba4c"),
        "3.13": _gnu("3.13", "x86_64-unknown-linux-gnu", "8a689a077337bea6d1c4bc0b7df1d52fcaa28f5f67e50df8bf417c1e3f9d8874"),
        "3.14": _gnu("3.14", "x86_64-unknown-linux-gnu", "3959f92825141e04adf44982d3a83ee57af0877e893b0796e04c1468749d9b04"),
    },
    "linux_aarch64": {
        "3.10": _gnu("3.10", "aarch64-unknown-linux-gnu", "d376e6ffd768cc152fd8bc909799880631b105dd6115425b64ef4224b497aadc"),
        "3.11": _gnu("3.11", "aarch64-unknown-linux-gnu", "f9308ed57184fae73941c712ed847be420ce36d31ba73ce53f0508a1ee752f68"),
        "3.12": _gnu("3.12", "aarch64-unknown-linux-gnu", "577b4bec0793ad1ff0cbff9adbd0df078eddde38a4c41bf5d83ad381a85ee39d"),
        "3.13": _gnu("3.13", "aarch64-unknown-linux-gnu", "01ce0ce9189feaead3298abf10d4efe998c55a489b3d5d38ca4f83dda7e7977e"),
        "3.14": _gnu("3.14", "aarch64-unknown-linux-gnu", "8a0798baa8a2c27b5751d590aced543eaa85e20b3f73d93c1af049688acdc9c5"),
    },
    "macos_arm64": {
        "3.10": _gnu("3.10", "aarch64-apple-darwin", "c2ddcefee6ae51286001dc22320434676adcc89362330823b409eac51a101a4b"),
        "3.11": _gnu("3.11", "aarch64-apple-darwin", "768f05cf200273bbdda9a5955a5a6892a4b22f2a0b1e4b0a9160f5c7fce86816"),
        "3.12": _gnu("3.12", "aarch64-apple-darwin", "81a359f1cfadd4da11766534c5913791cea55f26e1bb902cacd2a531bb1e4b2b"),
        "3.13": _gnu("3.13", "aarch64-apple-darwin", "d3904bd6a072246e07aa0bdadee9a14e80521e42a943c0848059feb16a2816dc"),
        "3.14": _gnu("3.14", "aarch64-apple-darwin", "4632cb1a6edad9e73d3c81b6d2e69131637d995173e3e85005df14102b0592ba"),
    },
    "macos_x86_64": {
        "3.10": _gnu("3.10", "x86_64-apple-darwin", "3ff8fef5965b5b3fae2823d19779f588e6e964cac640d0036c7e578e127e6017"),
        "3.11": _gnu("3.11", "x86_64-apple-darwin", "908b381433f78b832c8d64960ced0f85871893cc8779f413f963e0c9e293c258"),
        "3.12": _gnu("3.12", "x86_64-apple-darwin", "65b195c9cedc1fef6767f044f9822069adbd1bd9204d424ece4628776fdc04bb"),
        "3.13": _gnu("3.13", "x86_64-apple-darwin", "f712a9143c8a5d248438ec7921a0b48d548bca4f1337d33c690d28c2d0504137"),
        "3.14": _gnu("3.14", "x86_64-apple-darwin", "7e151a7c9028855b61a7d6e78381f2020a1ef185281399f3b1aafc5e1c9a1a64"),
    },
    "windows_x86_64": {
        "3.10": _gnu("3.10", "x86_64-pc-windows-msvc", "423464e7b3951317c7888fb890a9fa5f6a9d4e0ff71eb1b865b316eaaf63717d"),
        "3.11": _gnu("3.11", "x86_64-pc-windows-msvc", "06cbe479e039f5b9cb5640c286d790074d63f549f92a32d599a3748293bd4510"),
        "3.12": _gnu("3.12", "x86_64-pc-windows-msvc", "7c45c9622400d578709a9b2cddbe8124cc21d382409d9f13406d706d28e31b14"),
        "3.13": _gnu("3.13", "x86_64-pc-windows-msvc", "63d263ab0162f34a241a56dc5b283c22d6e131f5516117e6a921350c69ba7d4f"),
        "3.14": _gnu("3.14", "x86_64-pc-windows-msvc", "ca3c33ca924dfcab3b74205a7a58a88b0255135c53f95497b26b5e60700fd66d"),
    },
}

INTERPRETERS = PLATFORM_INTERPRETERS["linux_x86_64"]

STATIC_INTERPRETERS = {
    "3.10": _musl("3.10", "3a17c5bfe63363730d0283baf75b9fc342cddeb0c724b25546f81339b5bd44ba"),
    "3.11": _musl("3.11", "959ef05f25c55738e1480420eb3ab4d9368fdcf6397c63ffbeeb125fbe2bb657"),
    "3.12": _musl("3.12", "2b89d2b76515cd89007f6b7c7ef7a5b0815aa2ff871a1572324374b1a063f52a"),
    "3.13": _musl("3.13", "81937f0eb62b3c8440543ffb0e3453d5ef3daf671c5344d4acc41207535ed84d"),
    "3.14": _musl("3.14", "e5a76e5893c39c89ed268ad71c3d6794c3be6b7236ec613449140c57686fc17f"),
}

PLATFORMS = {
    "linux_x86_64": struct(
        os = "linux",
        interpreter = "linux-x86_64-gnu",
        python_bin = "bin/python3",
        lib_var = "LD_LIBRARY_PATH",
        uname_s = "Linux",
        uname_m = "x86_64",
        label = "Linux x86_64",
        program = "Contents/Linux",
        sha = "sha256sum",
        shell = True,
    ),
    "linux_aarch64": struct(
        os = "linux",
        interpreter = "linux-aarch64-gnu",
        python_bin = "bin/python3",
        lib_var = "LD_LIBRARY_PATH",
        uname_s = "Linux",
        uname_m = "aarch64",
        label = "Linux aarch64",
        program = "Contents/Linux",
        sha = "sha256sum",
        shell = True,
    ),
    "macos_arm64": struct(
        os = "macos",
        interpreter = "macos-aarch64-none",
        python_bin = "bin/python3",
        lib_var = "DYLD_LIBRARY_PATH",
        uname_s = "Darwin",
        uname_m = "arm64",
        label = "macOS arm64",
        program = "Contents/MacOS",
        sha = "shasum -a 256",
        shell = True,
    ),
    "macos_x86_64": struct(
        os = "macos",
        interpreter = "macos-x86_64-none",
        python_bin = "bin/python3",
        lib_var = "DYLD_LIBRARY_PATH",
        uname_s = "Darwin",
        uname_m = "x86_64",
        label = "macOS x86_64",
        program = "Contents/MacOS",
        sha = "shasum -a 256",
        shell = True,
    ),
    "windows_x86_64": struct(
        os = "windows",
        interpreter = "windows-x86_64-none",
        python_bin = "python.exe",
        lib_var = "",
        uname_s = "",
        uname_m = "",
        label = "Windows x86_64",
        program = "Contents/Windows",
        sha = "",
        shell = False,
    ),
}
