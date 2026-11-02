load("@com_google_protobuf//bazel/toolchains:proto_lang_toolchain.bzl", "proto_lang_toolchain")

package(default_visibility = ["//visibility:public"])

proto_lang_toolchain(
    name = "python",
    command_line = "--python_out=%s",
    progress_message = "Generating Python proto_library %{label}",
    runtime = "@com_google_protobuf//:protobuf_python",
    toolchain_type = "@com_google_protobuf//bazel/private:python_toolchain_type",
)
