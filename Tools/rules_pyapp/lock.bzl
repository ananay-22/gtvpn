load(":interpreters.bzl", "INTERPRETERS")

PyAppLockInfo = provider(
    "A hashed requirements lock, the CPython it is installed into, and, when bundled, the wheels it pins for " +
    "linux x86_64 and that CPython's python-build-standalone archive.",
    fields = ["lock", "indexes", "python", "wheels", "interpreter"],
)

def _pyapp_lock_impl(ctx):
    if ctx.attr.python_version not in INTERPRETERS:
        fail("%s: python_version %s is not one of %s" % (ctx.label, ctx.attr.python_version, sorted(INTERPRETERS)))
    if bool(ctx.files.wheels) != bool(ctx.file.interpreter):
        fail("%s bundles wheels and an interpreter together or neither" % ctx.label)
    files = [ctx.file.src] + ctx.files.wheels + ([ctx.file.interpreter] if ctx.file.interpreter else [])
    return [
        DefaultInfo(files = depset(files)),
        PyAppLockInfo(
            lock = ctx.file.src,
            indexes = ctx.attr.indexes,
            python = INTERPRETERS[ctx.attr.python_version],
            wheels = ctx.files.wheels,
            interpreter = ctx.file.interpreter,
        ),
    ]

pyapp_lock = rule(
    implementation = _pyapp_lock_impl,
    attrs = {
        "indexes": attr.string_list(),
        "interpreter": attr.label(allow_single_file = [".tar.gz"]),
        "python_version": attr.string(mandatory = True),
        "src": attr.label(mandatory = True, allow_single_file = True),
        "wheels": attr.label_list(allow_files = [".whl"]),
    },
    provides = [PyAppLockInfo],
)
