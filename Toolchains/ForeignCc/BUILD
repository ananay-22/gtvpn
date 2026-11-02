load("@rules_foreign_cc//foreign_cc/built_tools:pkgconfig_build.bzl", "pkgconfig_tool")
load("@rules_foreign_cc//toolchains/native_tools:native_tools_toolchain.bzl", "native_tool_toolchain")

package(default_visibility = ["//visibility:public"])

native_tool_toolchain(
    name = "make_native",
    env = {"MAKE": "$(execpath @make)"},
    path = "$(execpath @make)",
    tags = ["manual"],
    target = "@make",
)

toolchain(
    name = "make",
    toolchain = ":make_native",
    toolchain_type = "@rules_foreign_cc//toolchains:make_toolchain",
)

pkgconfig_tool(
    name = "pkgconfig_tool",
    srcs = "@foreign_cc_pkgconfig_src//:srcs",
    target_compatible_with = select({
        "@platforms//os:linux": [],
        "@platforms//os:macos": [],
        "//conditions:default": ["@platforms//:incompatible"],
    }),
)

native_tool_toolchain(
    name = "pkgconfig_native",
    env = {"PKG_CONFIG": "$(execpath :pkgconfig_tool)/bin/pkg-config"},
    path = "$(execpath :pkgconfig_tool)/bin/pkg-config",
    tags = ["manual"],
    target = ":pkgconfig_tool",
)

toolchain(
    name = "pkgconfig",
    toolchain = ":pkgconfig_native",
    toolchain_type = "@rules_foreign_cc//toolchains:pkgconfig_toolchain",
)
