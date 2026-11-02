load("@multi_platforms//:application.bzl", "APPLICATION_LAYOUT", "application_plist")
load("@rules_python_bzlmod//python:py_info.bzl", StarlarkPyInfo = "PyInfo")
load(":interpreters.bzl", "PLATFORMS", "STATIC_INTERPRETERS")
load(":lock.bzl", "PyAppLockInfo")

_PY_INFOS = (StarlarkPyInfo, PyInfo)
_BUNDLES = ("lock", "wheels")
_INTERPRETERS = ("gnu", "static")
_STATIC_RUNTIMES = {
    version: Label("@pyapp_static_%s//:interpreter" % version.replace(".", "_"))
    for version in STATIC_INTERPRETERS
}
_MAIN_REPO = "_main"
_LIBS = APPLICATION_LAYOUT.libs
_RESOURCES = APPLICATION_LAYOUT.resources
_SOURCES = _RESOURCES + "/python"
_STATIC_INTERPRETER = _RESOURCES + "/interpreter"
_INSTALLED = "site-packages"
_RUNTIME_OWNED = ("google/protobuf/",)
_EXECUTABLE = "755"
_READABLE = "644"
_PYTHON_VERSION = str(Label("@rules_python_bzlmod//python/config_settings:python_version"))

def _python_version_impl(settings, attr):
    if attr.runtime or not attr.python_version:
        return {_PYTHON_VERSION: settings[_PYTHON_VERSION]}
    return {_PYTHON_VERSION: attr.python_version}

_python_version = transition(
    implementation = _python_version_impl,
    inputs = [_PYTHON_VERSION],
    outputs = [_PYTHON_VERSION],
)

def _repo_path(file):
    short = file.short_path
    return short[3:] if short.startswith("../") else _MAIN_REPO + "/" + short

def _py_info(target):
    for info in _PY_INFOS:
        if info in target:
            return target[info]
    fail("%s carries no PyInfo" % target.label)

def _is_shared_library(file):
    return file.extension in ("so", "dylib", "dll") or ".so." in file.basename

def _module_path(repo_path, roots, outermost = False, packages = {}):
    chosen = ""
    for root in roots:
        if not repo_path.startswith(root + "/"):
            continue
        if not chosen or (len(root) < len(chosen) if outermost else len(root) > len(chosen)):
            chosen = root
    if chosen:
        return repo_path[len(chosen) + 1:]
    repo, _, rest = repo_path.partition("/")
    return repo_path if repo in packages else rest

def _is_solib(file):
    return file.short_path.startswith("_solib_")

def _place(placed, destination, file, mode, label):
    if destination in placed and placed[destination][0].path != file.path:
        fail("%s places %s from both %s and %s" % (label, destination, placed[destination][0].path, file.path))
    placed[destination] = (file, mode)

def _place_python(ctx, placed, static):
    infos = [_py_info(dep) for dep in ctx.attr.deps]
    roots = depset(transitive = [info.imports for info in infos]).to_list()
    installed = [root for root in roots if root.endswith("/" + _INSTALLED)]
    files = depset(
        [ctx.file.main],
        transitive = [info.transitive_sources for info in infos] +
                     [dep[DefaultInfo].default_runfiles.files for dep in ctx.attr.deps],
    ).to_list()
    own = ctx.label.workspace_name or _MAIN_REPO
    packages = {}
    for file in files:
        repo, _, rest = _repo_path(file).partition("/")
        if rest == "__init__.py" and repo != _MAIN_REPO:
            packages[repo] = True
    for file in [file for file in files if not _is_solib(file)] + [file for file in files if _is_solib(file)]:
        repo_path = _repo_path(file)
        if any([repo_path.startswith(root + "/") for root in installed]):
            if static:
                fail("%s runs the static interpreter, which takes no locked packages, but %s is one" % (ctx.label, file.short_path))
            continue
        if _is_shared_library(file):
            if static:
                fail("%s runs the static interpreter, which cannot load %s" % (ctx.label, file.short_path))
            if _is_solib(file) and _LIBS + "/" + file.basename in placed:
                continue
            _place(placed, _LIBS + "/" + file.basename, file, _EXECUTABLE, ctx.label)
            continue
        modules = [_module_path(repo_path, roots, outermost = file.extension != "py", packages = packages)]
        if file.extension == "py" and repo_path.startswith(own + "/"):
            modules.append(_module_path(repo_path, [], packages = packages))
        for module in {module: True for module in modules}:
            if module == "__init__.py" or module.startswith(_RUNTIME_OWNED):
                continue
            _place(placed, _SOURCES + "/" + module, file, _READABLE, ctx.label)
    main = _module_path(_repo_path(ctx.file.main), roots)[:-len(".py")].replace("/", ".")
    return main[:-len(".__main__")] if main.endswith(".__main__") else main

def _indexed(ctx, lock):
    if not lock.indexes:
        return lock.lock
    indexed = ctx.actions.declare_file(ctx.label.name + ".requirements_lock.txt")
    header = ["--index-url " + lock.indexes[0]] + ["--extra-index-url " + index for index in lock.indexes[1:]]
    ctx.actions.run_shell(
        inputs = [lock.lock],
        outputs = [indexed],
        arguments = [lock.lock.path, indexed.path] + header,
        command = "lock=$1; out=$2; shift 2; printf '%s\\n' \"$@\" > \"$out\"; cat \"$lock\" >> \"$out\"",
        mnemonic = "PyAppIndexedLock",
    )
    return indexed

def _place_lock(ctx, lock, installed, placed):
    _place(placed, _RESOURCES + "/requirements_lock.txt", installed, _READABLE, ctx.label)
    _place(placed, _RESOURCES + "/uv", ctx.file._uv, _EXECUTABLE, ctx.label)
    if ctx.attr.bundle != "wheels":
        return
    if not lock.wheels:
        fail("%s bundles wheels, but %s carries none" % (ctx.label, ctx.attr.lock.label))
    for wheel in lock.wheels:
        _place(placed, _RESOURCES + "/wheels/" + wheel.basename, wheel, _READABLE, ctx.label)
    _place(placed, _RESOURCES + "/interpreter/" + lock.python.path, lock.interpreter, _READABLE, ctx.label)

def _place_static(ctx, placed):
    python = "bin/python" + ctx.attr.python_version
    for file in ctx.files.runtime:
        relative = _repo_path(file).partition("/")[2]
        _place(placed, _STATIC_INTERPRETER + "/" + relative, file, _EXECUTABLE if relative == python else _READABLE, ctx.label)
    return _STATIC_INTERPRETER.partition("/")[2] + "/" + python

def _pack_arguments(ctx, placed, plat):
    if ctx.attr.runtime:
        return ["--interpreter", _place_static(ctx, placed)], [], ctx.file._static_launcher
    lock = ctx.attr.lock[PyAppLockInfo]
    if ctx.attr.python_version and not lock.python.version.startswith(ctx.attr.python_version + "."):
        fail("%s builds its deps for Python %s, but %s installs %s" % (ctx.label, ctx.attr.python_version, ctx.attr.lock.label, lock.python.version))
    installed = _indexed(ctx, lock)
    _place_lock(ctx, lock, installed, placed)
    arguments = ["--python", lock.python.version, "--bundle", ctx.attr.bundle, "--lock", installed.path]
    launcher = ctx.file._launch_macos if plat.os == "macos" else ctx.file._launch_linux
    return arguments, [installed], launcher

def _constraint(ctx, constraints):
    for constraint in constraints:
        if ctx.target_platform_has_constraint(constraint[platform_common.ConstraintValueInfo]):
            return constraint.label.name
    return None

def _platform_name(ctx):
    os = _constraint(ctx, ctx.attr._oses)
    cpu = _constraint(ctx, ctx.attr._cpus)
    if os == "osx":
        os = "macos"
    if cpu == "aarch64" and os == "macos":
        cpu = "arm64"
    name = "%s_%s" % (os, cpu)
    if name not in PLATFORMS:
        fail("%s cannot be built for %s/%s" % (ctx.label, os, cpu))
    return name

def _py_app_impl(ctx):
    plat = PLATFORMS[_platform_name(ctx)]
    placed = {}
    module = _place_python(ctx, placed, bool(ctx.attr.runtime))
    arguments, inputs, launcher = _pack_arguments(ctx, placed, plat)
    plist = application_plist(ctx, ctx.file._plist, ctx.label.name, ctx.attr.bundle_id, ctx.attr.version)
    _place(placed, APPLICATION_LAYOUT.plist, plist, _READABLE, ctx.label)

    header = ctx.file._header_macos if plat.os == "macos" else ctx.file._header_linux
    manifest = ctx.actions.declare_file(ctx.label.name + ".manifest")
    ctx.actions.write(manifest, "".join([
        "%s\t%s\t%s\n" % (mode, destination, file.path)
        for destination, (file, mode) in sorted(placed.items())
    ]))
    out = ctx.actions.declare_file(ctx.label.name)
    python = ctx.attr._python[platform_common.ToolchainInfo].py3_runtime
    ctx.actions.run(
        executable = python.interpreter,
        tools = python.files,
        arguments = [
            "-I",
            ctx.file._pack.path,
            "--name",
            ctx.label.name,
            "--module",
            module,
            "--program",
            plat.program + "/" + ctx.label.name,
            "--header",
            header.path,
            "--launcher",
            launcher.path,
            "--manifest",
            manifest.path,
            "--out",
            out.path,
            "--lib-var",
            plat.lib_var,
            "--interp-infix",
            plat.interpreter,
            "--python-bin",
            plat.python_bin,
            "--uname-s",
            plat.uname_s,
            "--uname-m",
            plat.uname_m,
            "--platform-label",
            plat.label,
            "--sha",
            plat.sha,
        ] + arguments,
        inputs = [manifest, header, launcher, ctx.file._pack] + inputs + [file for file, _ in placed.values()],
        outputs = [out],
        mnemonic = "PyApp",
        progress_message = "Packing %s as a self-extracting %s app" % (ctx.label.name, plat.label),
    )
    return [DefaultInfo(executable = out, files = depset([out]))]

_py_app = rule(
    implementation = _py_app_impl,
    doc = "A self-extracting app for one of %s. The default gnu interpreter is python-build-standalone's shared " % sorted(PLATFORMS) +
          "build, installed on first run by the bundled uv. Its python_version, when given, must be the lock's and " +
          "is the version its deps are built for. The static interpreter is linux x86_64 only: it runs on glibc " +
          "and musl alike, but takes the standard library only.",
    executable = True,
    attrs = {
        "bundle": attr.string(values = list(_BUNDLES)),
        "bundle_id": attr.string(mandatory = True),
        "deps": attr.label_list(cfg = _python_version, providers = [[provider] for provider in _PY_INFOS]),
        "lock": attr.label(providers = [PyAppLockInfo]),
        "main": attr.label(mandatory = True, allow_single_file = [".py"]),
        "python_version": attr.string(),
        "runtime": attr.label(allow_files = True),
        "version": attr.string(default = "0.0.0"),
        "_allowlist_function_transition": attr.label(default = "@bazel_tools//tools/allowlists/function_transition_allowlist"),
        "_cpus": attr.label_list(
            default = [Label("@platforms//cpu:" + cpu) for cpu in ("x86_64", "aarch64")],
            providers = [platform_common.ConstraintValueInfo],
        ),
        "_header_linux": attr.label(default = Label("//:app.header.tpl"), allow_single_file = True),
        "_header_macos": attr.label(default = Label("//:app.header.macos.tpl"), allow_single_file = True),
        "_launch_linux": attr.label(default = Label("//:app.launch.tpl"), allow_single_file = True),
        "_launch_macos": attr.label(default = Label("//:app.launch.macos.tpl"), allow_single_file = True),
        "_oses": attr.label_list(
            default = [Label("@platforms//os:" + os) for os in ("linux", "macos", "windows")],
            providers = [platform_common.ConstraintValueInfo],
        ),
        "_pack": attr.label(default = Label("//:pack.py"), allow_single_file = True),
        "_plist": attr.label(default = Label("@multi_platforms//:application.plist.tpl"), allow_single_file = True),
        "_python": attr.label(default = Label("@rules_python_bzlmod//python:current_py_toolchain"), cfg = "exec"),
        "_static_launcher": attr.label(default = Label("//:app.static.tpl"), allow_single_file = True),
        "_uv": attr.label(default = Label("//:uv"), allow_single_file = True),
    },
)

def _bundled(lock, bundle):
    return lock.same_package_label(lock.name + "_wheels") if bundle == "wheels" else lock

def _gnu(name, lock, bundle, python_version):
    if not lock:
        fail("%s: the gnu interpreter installs a lock; name one" % name)
    bundle = bundle or "lock"
    if bundle not in _BUNDLES:
        fail("%s: bundle is one of %s, not %s" % (name, _BUNDLES, bundle))
    found = dict(bundle = bundle, lock = _bundled(native.package_relative_label(lock), bundle))
    if python_version:
        found["python_version"] = python_version
    return found

def _static(name, lock, bundle, python_version):
    if lock or bundle:
        fail("%s: the static interpreter runs the standard library only, so it takes no lock and no bundle" % name)
    if python_version not in _STATIC_RUNTIMES:
        fail("%s: the static interpreter needs a python_version among %s, not %s" % (name, sorted(_STATIC_RUNTIMES), python_version))
    return dict(python_version = python_version, runtime = _STATIC_RUNTIMES[python_version])

_GNU_PLATFORMS = ["linux_x86_64", "linux_aarch64", "macos_arm64", "macos_x86_64"]
_LINUX_X86_64 = ["linux_x86_64"]

def _compatible_with(platforms):
    return select(dict(
        [(Label("//:" + platform), []) for platform in platforms] +
        [("//conditions:default", [Label("@platforms//:incompatible")])],
    ))

def py_app(name, main, lock = None, deps = [], bundle = None, interpreter = "gnu", python_version = None, **kwargs):
    if interpreter not in _INTERPRETERS:
        fail("%s: interpreter is one of %s, not %s" % (name, _INTERPRETERS, interpreter))
    found = (_gnu if interpreter == "gnu" else _static)(name, lock, bundle, python_version)
    platforms = _GNU_PLATFORMS if interpreter == "gnu" and found["bundle"] == "lock" else _LINUX_X86_64
    kwargs.update(found)
    kwargs.setdefault("target_compatible_with", _compatible_with(platforms))
    _py_app(
        name = name,
        main = main,
        deps = deps,
        **kwargs
    )
