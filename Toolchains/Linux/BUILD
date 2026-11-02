load(":defs.bzl", "linux_cc_toolchain")

package(default_visibility = ["//visibility:public"])

exports_files(["sysroot.BUILD"])

linux_cc_toolchain(
    name = "linux_x86_64",
    arch = "x86_64",
    llvm = "@llvm_linux_x86_64",
)
