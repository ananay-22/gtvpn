load("@com_google_protobuf//bazel:py_proto_library.bzl", "py_proto_library")

package(default_visibility = ["//visibility:public"])

proto_library(
    name = "profile_proto",
    srcs = ["profile.proto"],
)

py_proto_library(
    name = "profile_py_proto",
    deps = [":profile_proto"],
)
