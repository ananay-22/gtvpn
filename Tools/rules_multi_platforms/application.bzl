load("@rules_python//python:py_info.bzl", StarlarkPyInfo = "PyInfo")

_PY_INFOS = (StarlarkPyInfo, PyInfo)

LinuxContentsInfo = provider(
    "The files a Linux application folder places, the files it needs another part to place, and the staged parts " +
    "it is made of.",
    fields = ["app", "placed", "requires", "parts"],
)

def _part(ctx, staged, app):
    return struct(name = ctx.label.name, folder = staged.folder, manifest = staged.manifest, app = app)

def linux_part(ctx, placed, requires):
    staged = _folder(ctx, ctx.label.name, placed, requires)
    return [
        DefaultInfo(files = depset([staged.folder])),
        LinuxContentsInfo(app = None, placed = placed, requires = requires, parts = [_part(ctx, staged, None)]),
    ]

APPLICATION_LAYOUT = struct(
    contents = "Contents",
    plist = "Contents/Info.plist",
    linux = "Contents/Linux",
    macos = "Contents/MacOS",
    windows = "Contents/Windows",
    libs = "Contents/Libs",
    helpers = "Contents/Helpers",
    resources = "Contents/Resources",
)

APPLICATION_RPATH = "$ORIGIN/../Libs"

APPLICATION_LINKOPTS = select({
    str(Label("@platforms//os:linux")): [
        "-Wl,-rpath," + APPLICATION_RPATH.replace("$", "$$"),
        "-Wl,--disable-new-dtags",
    ],
    "//conditions:default": [],
})

_CONTENTS = APPLICATION_LAYOUT.contents
_LIBS = APPLICATION_LAYOUT.libs
_MANIFESTS = _CONTENTS + "/Manifests"
_PYTHON = _LIBS + "/python"
_RESOURCES = APPLICATION_LAYOUT.resources
_MAIN = "_main"
_STAGE = "stage"
_INSTALLED = "/site-packages"
_RUNTIME_OWNED = ("google/protobuf/",)

LINUX_TEMPLATES = {
    "_launch": attr.label(default = Label("//:application.launch.tpl"), allow_single_file = True),
    "_outer": attr.label(default = Label("//:application.outer.tpl"), allow_single_file = True),
    "_plist": attr.label(default = Label("//:application.plist.tpl"), allow_single_file = True),
    "_pth": attr.label(default = Label("//:application.pth.tpl"), allow_single_file = True),
    "_stage": attr.label(default = Label("//:application.stage.tpl"), allow_single_file = True),
}

def _repo_path(file):
    path = file.short_path
    if path.startswith("../"):
        return path[3:]
    return _MAIN + "/" + path

def _split(repo_path):
    repo, _, rest = repo_path.partition("/")
    return repo, rest

def _asset(file):
    repo, rest = _split(_repo_path(file))
    if repo == _MAIN:
        return rest
    return "external/" + repo + "/" + rest

def _module(repo_path, roots):
    chosen = ""
    for root in roots:
        if repo_path.startswith(root + "/") and len(root) > len(chosen):
            chosen = root
    return repo_path[len(chosen) + 1:] if chosen else repo_path

def _is_shared_library(file):
    return file.extension in ("so", "dylib", "dll") or ".so." in file.basename

def _is_python(target):
    return any([info in target for info in _PY_INFOS])

def _substitute(value):
    return value.replace("{contents}", "$contents").replace("{libs}", "$contents/Libs").replace(
        "{resources}",
        "$contents/Resources",
    )

def _python(target, windows = False):
    runtime = target[platform_common.ToolchainInfo].py3_runtime
    repo, path = _split(_repo_path(runtime.interpreter))
    version = runtime.interpreter_version_info
    stdlib = "python%s.%s" % (version.major, version.minor)
    return struct(
        runtime = runtime,
        repo = repo,
        path = path,
        version = version,
        stdlib = stdlib,
        site_packages = _PYTHON + "/Lib/site-packages" if windows else "%s/lib/%s/site-packages" % (_PYTHON, stdlib),
        paths = path[:-len(".exe")] + "._pth" if windows else path + "._pth",
    )

def _place_interpreter(ctx, python, placed):
    for file in python.runtime.files.to_list() + [python.runtime.interpreter]:
        repo, rest = _split(_repo_path(file))
        if repo == python.repo:
            placed.setdefault(_PYTHON + "/" + rest, file)
    paths = ctx.actions.declare_file(ctx.label.name + ".pth")
    ctx.actions.expand_template(template = ctx.file._pth, output = paths, substitutions = {
        "{VERSION}": "%s%s" % (python.version.major, python.version.minor),
        "{STDLIB}": python.stdlib,
    })
    placed.setdefault(_PYTHON + "/" + python.paths, paths)

def _place_modules(ctx, python, placed, requires, bundle_python = True):
    for module, found in _modules([ctx.attr.binary]).items():
        owned = bundle_python or not found.installed
        (placed if owned else requires).setdefault(python.site_packages + "/" + module, found.file)

def _py_info(target):
    for info in _PY_INFOS:
        if info in target:
            return target[info]
    fail("%s carries no PyInfo" % target.label)

def _modules(targets):
    imports = depset(transitive = [_py_info(target).imports for target in targets]).to_list()
    sources = depset(transitive = [_py_info(target).transitive_sources for target in targets]).to_list()
    packages = {}
    for file in sources:
        repo, rest = _split(_repo_path(file))
        if rest == "__init__.py":
            packages[repo] = True
    roots = {imported: True for imported in imports}
    for file in sources:
        repo = _split(_repo_path(file))[0]
        if repo not in packages:
            roots[repo] = True
    for target in targets:
        for file in target[DefaultInfo].default_runfiles.files.to_list():
            repo_path = _repo_path(file)
            if any([repo_path.startswith(root + "/") for root in imports]):
                sources.append(file)
    installed_roots = [root for root in imports if root.endswith(_INSTALLED)]
    modules = {}
    for file in sources:
        repo_path = _repo_path(file)
        module = _module(repo_path, roots)
        installed = any([repo_path.startswith(root + "/") for root in installed_roots])
        if module == "__init__.py" or (not installed and module.startswith(_RUNTIME_OWNED)):
            continue
        modules.setdefault(module, struct(file = file, installed = installed))
    return modules

def _place_runfile_libs(target, placed):
    for file in target[DefaultInfo].default_runfiles.files.to_list():
        if _is_shared_library(file):
            placed.setdefault(_LIBS + "/" + file.basename, file)

def _place_libs(targets, placed, shared_only = False):
    for target in targets:
        for file in target[DefaultInfo].files.to_list():
            if not shared_only or _is_shared_library(file):
                placed.setdefault(_LIBS + "/" + file.basename, file)
        _place_runfile_libs(target, placed)

def _executable(target):
    executable = target[DefaultInfo].files_to_run.executable
    if not executable:
        fail("%s is not executable" % target.label)
    return executable

def _place_helpers(ctx, placed):
    for target, folder in ctx.attr.additional_contents.items():
        executable = target[DefaultInfo].files_to_run.executable
        files = [executable] if executable else target[DefaultInfo].files.to_list()
        for file in files:
            placed.setdefault(_CONTENTS + "/" + folder + "/" + file.basename, file)
        if executable:
            _place_runfile_libs(target, placed)

def _rpath_check(ctx, executables):
    checks = []
    for executable in executables:
        check = ctx.actions.declare_file("%s.rpath/%s" % (ctx.label.name, executable.basename))
        ctx.actions.run_shell(
            inputs = [executable],
            outputs = [check],
            arguments = [executable.path, check.path, APPLICATION_RPATH],
            command = "\n".join([
                "if ! grep -qaF \"$3\" \"$1\"; then",
                "  echo \"$1 has no rpath $3; link it with APPLICATION_LINKOPTS from @multi_platforms//:application.bzl\" >&2",
                "  exit 1",
                "fi",
                "touch \"$2\"",
            ]),
            mnemonic = "LinuxApplicationRpath",
            progress_message = "Checking that %s finds its libraries in Contents/Libs" % executable.short_path,
        )
        checks.append(check)
    return checks

def _place_resources(targets, placed):
    for target in targets:
        for file in target[DefaultInfo].files.to_list():
            placed.setdefault(_RESOURCES + "/" + _asset(file), file)

def _place_launchers(ctx, app, python, placed):
    placed.setdefault(APPLICATION_LAYOUT.linux + "/" + app, _launch_script(ctx, python))
    _place_outer(ctx, app, placed)

def _launch_script(ctx, python):
    exports = "".join([
        "%s=\"%s\"\nexport %s\n" % (key, _substitute(value), key)
        for key, value in sorted(ctx.attr.environment.items())
    ])
    arguments = "".join([" \"%s\"" % _substitute(argument) for argument in ctx.attr.arguments])
    inner = ctx.actions.declare_file(ctx.label.name + ".launch")
    ctx.actions.expand_template(template = ctx.file._launch, output = inner, is_executable = True, substitutions = {
        "{EXPORTS}": exports,
        "{INTERPRETER}": python.path,
        "{MODULE}": ctx.attr.module,
        "{ARGUMENTS}": arguments,
    })
    return inner

def application_plist(ctx, template, app, bundle_id, version):
    plist = ctx.actions.declare_file(ctx.label.name + ".plist")
    ctx.actions.expand_template(template = template, output = plist, substitutions = {
        "{BUNDLE_ID}": bundle_id,
        "{APP}": app,
        "{VERSION}": version,
    })
    return plist

def _place_plist(ctx, app, placed):
    plist = application_plist(ctx, ctx.file._plist, app, ctx.attr.bundle_id, ctx.attr.version)
    placed.setdefault(APPLICATION_LAYOUT.plist, plist)

def _listing(entries):
    return "".join(["%s\t%s\n" % (path, _repo_path(file)) for path, file in sorted(entries.items())])

def _stage_script(ctx):
    name = ctx.label.name
    script = ctx.actions.declare_file(name + ".stage")
    ctx.actions.expand_template(template = ctx.file._stage, output = script, is_executable = True, substitutions = {
        "{MANIFESTS}": _MANIFESTS,
        "{NAME}": name,
        "{STAGE}": _STAGE,
    })
    return script

def _folder(ctx, app, placed, requires):
    if _STAGE in placed:
        fail("%s cannot place a file named %s; the staging script takes that name" % (ctx.label, _STAGE))
    placed_listing = ctx.actions.declare_file(ctx.label.name + ".placed")
    ctx.actions.write(placed_listing, _listing(placed))
    requires_listing = ctx.actions.declare_file(ctx.label.name + ".requires")
    ctx.actions.write(requires_listing, _listing(requires))
    staged = dict(placed)
    staged[_MANIFESTS + "/" + ctx.label.name + ".placed"] = placed_listing
    staged[_MANIFESTS + "/" + ctx.label.name + ".requires"] = requires_listing
    staged[_STAGE] = _stage_script(ctx)
    return struct(folder = _copy(ctx, app, staged), manifest = placed_listing)

def _copy(ctx, app, staged):
    copies = ctx.actions.declare_file(ctx.label.name + ".copies")
    ctx.actions.write(copies, "".join([
        "%s\t%s\n" % (file.path, destination)
        for destination, file in sorted(staged.items())
    ]))
    folder = ctx.actions.declare_directory(ctx.label.name + "/" + app)
    ctx.actions.run_shell(
        inputs = [copies] + staged.values(),
        outputs = [folder],
        arguments = [folder.path, copies.path],
        command = "\n".join([
            "set -e",
            "while IFS=\"$(printf '\\t')\" read -r source destination; do",
            "  mkdir -p \"$1/$(dirname \"$destination\")\"",
            "  cp -L \"$source\" \"$1/$destination\"",
            "done < \"$2\"",
        ]),
        mnemonic = "Application",
        progress_message = "Staging %s as an application folder" % app,
    )
    return folder

def _needs(ctx, names, made_from):
    for name in names:
        if not getattr(ctx.attr, name):
            fail("%s is made from %s, so it needs %s" % (ctx.label, made_from, name))

def _refuses(ctx, names, made_from):
    for name in names:
        if getattr(ctx.attr, name):
            fail("%s is made from %s, which takes no %s" % (ctx.label, made_from, name))

_PYTHON_ONLY = ("arguments", "environment", "module", "python")

def _place_outer(ctx, app, placed):
    outer = ctx.actions.declare_file(ctx.label.name + ".outer")
    ctx.actions.expand_template(template = ctx.file._outer, output = outer, is_executable = True, substitutions = {
        "{APP}": app,
    })
    placed.setdefault(app, outer)

def _from_binary(ctx, app):
    _needs(ctx, ("binary", "bundle_id"), "a binary")
    placed, requires = {}, {}
    if _is_python(ctx.attr.binary):
        _needs(ctx, ("module", "python"), "a py_binary")
        python = _python(ctx.attr.python)
        _place_modules(ctx, python, placed, requires, ctx.attr.bundle_python)
        if ctx.attr.bundle_python:
            _place_interpreter(ctx, python, placed)
        else:
            requires[_PYTHON + "/" + python.path] = python.runtime.interpreter
        _place_launchers(ctx, app, python, placed)
        checks = []
    else:
        _refuses(ctx, _PYTHON_ONLY, "a native binary")
        executable = _executable(ctx.attr.binary)
        placed[APPLICATION_LAYOUT.linux + "/" + app] = executable
        _place_runfile_libs(ctx.attr.binary, placed)
        _place_outer(ctx, app, placed)
        checks = [executable]
    _place_libs(ctx.attr.libs, placed)
    _place_helpers(ctx, placed)
    _place_resources(ctx.attr.resources, placed)
    _place_plist(ctx, app, placed)
    return placed, requires, checks

def _from_contents(ctx):
    for name in ("additional_contents", "app", "arguments", "binary", "bundle_id", "environment", "libs", "module", "python", "resources"):
        if getattr(ctx.attr, name):
            fail("%s is made from contents, so %s belongs on the application in contents" % (ctx.label, name))
    apps, placed, requires = [], {}, {}
    for part in ctx.attr.contents:
        info = part[LinuxContentsInfo]
        if info.app:
            apps.append(info.app)
        for path, file in info.placed.items():
            if path in placed and placed[path].path != file.path:
                fail("%s places %s from %s, which another part places from %s" % (
                    part.label,
                    path,
                    file.path,
                    placed[path].path,
                ))
            placed[path] = file
        requires.update(info.requires)
    if len(apps) != 1:
        fail("%s needs exactly one application in contents, has %d" % (ctx.label, len(apps)))
    missing = sorted([path for path, file in requires.items() if path not in placed or placed[path].path != file.path])
    if missing:
        fail("%s: no part places %d files %s needs, e.g. %s" % (ctx.label, len(missing), apps[0], ", ".join(missing[:5])))
    return apps[0], placed

def _linux_application_impl(ctx):
    checks = []
    if ctx.attr.contents:
        app, placed = _from_contents(ctx)
        requires = {}
    else:
        app = ctx.attr.app or ctx.label.name
        placed, requires, checks = _from_binary(ctx, app)
    staged = _folder(ctx, app, placed, requires)
    if ctx.attr.contents:
        parts = [part for content in ctx.attr.contents for part in content[LinuxContentsInfo].parts]
    else:
        parts = [_part(ctx, staged, app)]
    return [
        DefaultInfo(files = depset([staged.folder])),
        LinuxContentsInfo(app = app, placed = placed, requires = requires, parts = parts),
        OutputGroupInfo(_validation = depset(_rpath_check(ctx, checks))),
    ]

linux_application = rule(
    implementation = _linux_application_impl,
    attrs = {
        "additional_contents": attr.label_keyed_string_dict(allow_files = True),
        "app": attr.string(),
        "arguments": attr.string_list(),
        "binary": attr.label(),
        "bundle_id": attr.string(),
        "bundle_python": attr.bool(default = True),
        "contents": attr.label_list(providers = [LinuxContentsInfo]),
        "environment": attr.string_dict(),
        "libs": attr.label_list(),
        "module": attr.string(),
        "python": attr.label(),
        "resources": attr.label_list(allow_files = True),
        "version": attr.string(default = "0.0.0"),
    } | LINUX_TEMPLATES,
)

def _windows_launch(ctx, python):
    lines = ["program\tLibs\\python\\" + python.path.replace("/", "\\")]
    lines += ["argument\t" + argument for argument in ["-m", ctx.attr.module] + ctx.attr.arguments]
    lines += ["environment\t%s\t%s" % (key, value) for key, value in sorted(ctx.attr.environment.items())]
    for line in lines:
        if "\n" in line or line.count("\t") > 2:
            fail("%s: launch values may hold neither tabs nor newlines: %r" % (ctx.label, line))
    launch = ctx.actions.declare_file(ctx.label.name + ".launch")
    ctx.actions.write(launch, "".join([line + "\n" for line in lines]))
    return launch

def _windows_application_impl(ctx):
    _needs(ctx, ("binary", "bundle_id"), "a binary")
    app = ctx.attr.app or ctx.label.name
    launcher = _executable(ctx.attr._launcher)
    placed = {app + ".exe": launcher}
    inner = APPLICATION_LAYOUT.windows + "/" + app
    if _is_python(ctx.attr.binary):
        _needs(ctx, ("module", "python"), "a py_binary")
        python = _python(ctx.attr.python, windows = True)
        _place_modules(ctx, python, placed, {})
        _place_interpreter(ctx, python, placed)
        placed[inner + ".exe"] = launcher
        placed[inner + ".launch"] = _windows_launch(ctx, python)
    else:
        _refuses(ctx, _PYTHON_ONLY, "a native binary")
        placed[inner + ".exe"] = _executable(ctx.attr.binary)
        _place_runfile_libs(ctx.attr.binary, placed)
    _place_libs(ctx.attr.libs, placed, shared_only = True)
    _place_helpers(ctx, placed)
    _place_resources(ctx.attr.resources, placed)
    _place_plist(ctx, app, placed)
    return [DefaultInfo(files = depset([_copy(ctx, app, placed)]))]

windows_application = rule(
    implementation = _windows_application_impl,
    attrs = {
        "additional_contents": attr.label_keyed_string_dict(allow_files = True),
        "app": attr.string(),
        "arguments": attr.string_list(),
        "binary": attr.label(),
        "bundle_id": attr.string(),
        "environment": attr.string_dict(),
        "libs": attr.label_list(),
        "module": attr.string(),
        "python": attr.label(),
        "resources": attr.label_list(allow_files = True),
        "version": attr.string(default = "0.0.0"),
        "_launcher": attr.label(default = Label("//Launcher:windows")),
        "_plist": attr.label(default = Label("//:application.plist.tpl"), allow_single_file = True),
        "_pth": attr.label(default = Label("//:application.windows.pth.tpl"), allow_single_file = True),
    },
)

def _macos_python_application_impl(ctx):
    _needs(ctx, ("binary", "bundle_id"), "a binary")
    if not _is_python(ctx.attr.binary):
        fail("%s wraps a native binary; a native macOS app is a rules_apple macos_application" % ctx.label)
    _needs(ctx, ("module", "python"), "a py_binary")
    app = ctx.attr.app or ctx.label.name
    python = _python(ctx.attr.python)
    placed = {}
    _place_modules(ctx, python, placed, {})
    _place_interpreter(ctx, python, placed)
    placed[APPLICATION_LAYOUT.macos + "/" + app] = _launch_script(ctx, python)
    _place_libs(ctx.attr.libs, placed)
    _place_helpers(ctx, placed)
    _place_resources(ctx.attr.resources, placed)
    _place_plist(ctx, app, placed)
    return [DefaultInfo(files = depset([_copy(ctx, app + ".app", placed)]))]

macos_python_application = rule(
    implementation = _macos_python_application_impl,
    attrs = {
        "additional_contents": attr.label_keyed_string_dict(allow_files = True),
        "app": attr.string(),
        "arguments": attr.string_list(),
        "binary": attr.label(),
        "bundle_id": attr.string(),
        "environment": attr.string_dict(),
        "libs": attr.label_list(),
        "module": attr.string(),
        "python": attr.label(),
        "resources": attr.label_list(allow_files = True),
        "version": attr.string(default = "0.0.0"),
        "_launch": attr.label(default = Label("//:application.launch.tpl"), allow_single_file = True),
        "_plist": attr.label(default = Label("//:application.plist.tpl"), allow_single_file = True),
        "_pth": attr.label(default = Label("//:application.pth.tpl"), allow_single_file = True),
    },
)
