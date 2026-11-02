_SYSROOT_URL = "https://commondatastorage.googleapis.com/chrome-linux-sysroot"

_SYSROOTS = {
    "bullseye": {
        "x86_64": "52d61d4446ffebfaa3dda2cd02da4ab4876ff237853f46d273e7f9b666652e1d",
        "aarch64": "c7176a4c7aacbf46bda58a029f39f79a68008d3dee6518f154dcf5161a5486d8",
    },
}

_ARCHES = ["x86_64", "aarch64"]

_CPU = {
    "x86_64": "@platforms//cpu:x86_64",
    "aarch64": "@platforms//cpu:aarch64",
}

def _sysroot_archive_impl(rctx):
    sha256 = _SYSROOTS[rctx.attr.version][rctx.attr.arch]
    rctx.download_and_extract(
        url = "{}/{}".format(_SYSROOT_URL, sha256),
        sha256 = sha256,
        type = "tar.xz",
    )
    rctx.symlink(rctx.attr.build_file, "BUILD.bazel")

sysroot_archive = repository_rule(
    implementation = _sysroot_archive_impl,
    attrs = {
        "arch": attr.string(values = _ARCHES),
        "build_file": attr.label(allow_single_file = True, default = "//Toolchains/Linux:sysroot.BUILD"),
        "version": attr.string(values = _SYSROOTS.keys()),
    },
)

def linux_cc_toolchain(name, llvm, arch, exec_arch = "x86_64"):
    native.toolchain(
        name = name,
        exec_compatible_with = [
            "@platforms//os:linux",
            _CPU[exec_arch],
        ],
        target_compatible_with = [
            "@platforms//os:linux",
            _CPU[arch],
        ],
        toolchain = "{}//:cc-clang-{}-linux".format(llvm, arch),
        toolchain_type = "@bazel_tools//tools/cpp:toolchain_type",
    )
