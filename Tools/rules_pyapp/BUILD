package(default_visibility = ["//visibility:public"])

exports_files([
    "app.header.tpl",
    "app.header.macos.tpl",
    "app.launch.tpl",
    "app.launch.macos.tpl",
    "app.static.tpl",
    "pack.py",
])

_UV_PLATFORMS = [
    "linux_aarch64",
    "linux_x86_64",
    "macos_arm64",
    "macos_x86_64",
    "windows_x86_64",
]

[config_setting(
    name = platform,
    constraint_values = [
        "@platforms//os:" + platform.split("_")[0],
        "@platforms//cpu:" + platform.split("_", 1)[1],
    ],
) for platform in _UV_PLATFORMS]

alias(
    name = "uv",
    actual = select({":" + platform: "@pyapp_uv_%s//:uv" % platform for platform in _UV_PLATFORMS}),
    target_compatible_with = select(dict(
        [(":" + platform, []) for platform in _UV_PLATFORMS] +
        [("//conditions:default", ["@platforms//:incompatible"])],
    )),
)
