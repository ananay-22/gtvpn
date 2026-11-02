load("@rules_foreign_cc//foreign_cc:defs.bzl", "configure_make")

package(default_visibility = ["//visibility:public"])

configure_make(
    name = "openconnect",
    configure_options = [
        "--with-openssl",
        "--without-gnutls",
        "--without-stoken",
        "--without-libpcsclite",
        "--without-gssapi",
        "--without-libproxy",
        "--without-libpskc",
        "--without-lz4",
        "--without-java",
        "--with-builtin-json",
        "--with-vpnc-script=/etc/vpnc/vpnc-script",
        "--disable-nls",
        "--disable-docs",
        "--disable-shared",
        "--enable-static",
        "--disable-maintainer-mode",
        "--disable-dependency-tracking",
        "OPENSSL_CFLAGS=-I$$EXT_BUILD_DEPS/include",
        "OPENSSL_LIBS=\"-Wl,$$EXT_BUILD_DEPS/lib/libssl.a -Wl,$$EXT_BUILD_DEPS/lib/libcrypto.a\"",
        "LIBXML2_CFLAGS=-I$$EXT_BUILD_DEPS/include",
        "LIBXML2_LIBS=-Wl,$$EXT_BUILD_DEPS/lib/libxml2.a",
        "ZLIB_CFLAGS=-I$$EXT_BUILD_DEPS/include",
        "ZLIB_LIBS=-Wl,$$EXT_BUILD_DEPS/lib/libz.a",
        "LIBS=\"-Wl,$$EXT_BUILD_DEPS/lib/libssl.a -Wl,$$EXT_BUILD_DEPS/lib/libcrypto.a -Wl,$$EXT_BUILD_DEPS/lib/libxml2.a -Wl,$$EXT_BUILD_DEPS/lib/libz.a\"",
    ] + select({
        "@platforms//os:macos": ["AR=ar"],
        "//conditions:default": [],
    }),
    lib_name = "openconnect_install",
    lib_source = "@openconnect_src//:srcs",
    out_bin_dir = "sbin",
    out_binaries = ["openconnect"],
    target_compatible_with = select({
        "@platforms//os:linux": [],
        "@platforms//os:macos": [],
        "//conditions:default": ["@platforms//:incompatible"],
    }),
    targets = [
        "openconnect",
        "install-sbinPROGRAMS",
    ],
    deps = [
        "@libxml2",
        "@openssl//:crypto",
        "@openssl//:ssl",
        "@bcr_zlib//:zlib",
    ],
)
