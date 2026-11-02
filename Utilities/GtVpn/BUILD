load("@pyapp//:defs.bzl", "py_app")
load("@rules_python_bzlmod//python:defs.bzl", "py_library", "py_test")

package(default_visibility = ["//visibility:public"])

exports_files(["requirements_lock.txt"])

filegroup(
    name = "openconnect",
    srcs = ["//Third-Party/OpenConnect:openconnect"],
    output_group = "openconnect",
)

py_library(
    name = "cli",
    srcs = glob(["cli/*.py"]),
    data = [
        ":openconnect",
        "//Utilities/GtVpn/Defaults:profiles",
    ],
    deps = ["//Utilities/GtVpn/Proto:profile_py_proto"],
)

py_app(
    name = "gtvpn",
    bundle_id = "edu.gatech.ccg.gtvpn",
    lock = "@gtvpn_lock",
    main = "cli/__main__.py",
    target_compatible_with = select({
        "@platforms//os:linux": [],
        "@platforms//os:macos": [],
        "//conditions:default": ["@platforms//:incompatible"],
    }),
    version = "0.5.3",
    deps = [":cli"],
)

py_test(
    name = "cli_test",
    size = "small",
    srcs = ["cli_test.py"],
    target_compatible_with = select({
        "@platforms//os:linux": [],
        "@platforms//os:macos": [],
        "//conditions:default": ["@platforms//:incompatible"],
    }),
    deps = [":cli"],
)
