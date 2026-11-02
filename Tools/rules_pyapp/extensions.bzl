load(":interpreters.bzl", "INTERPRETERS", "STATIC_INTERPRETERS")

_DEFAULT_INDEX = "https://pypi.org/simple"
_INDEX_OPTIONS = ("--index-url", "-i", "--extra-index-url")
_NEWEST_GLIBC_MINOR = 28
_OLDEST_GLIBC_MINOR = 5
_LEGACY_MANYLINUX = {17: "manylinux2014", 12: "manylinux2010", 5: "manylinux1"}
_NAME_ENDS = ("[", "=", "<", ">", "!", "~", ";", " ", "@")

def _minor(python_version):
    return int(python_version.split(".")[1])

def _linux_platforms():
    platforms = []
    for minor in range(_NEWEST_GLIBC_MINOR, _OLDEST_GLIBC_MINOR - 1, -1):
        platforms.append("manylinux_2_%d_x86_64" % minor)
        if minor in _LEGACY_MANYLINUX:
            platforms.append(_LEGACY_MANYLINUX[minor] + "_x86_64")
    return platforms + ["linux_x86_64"]

def _supported_tags(minor):
    cpython = "cp3%d" % minor
    pythons = ["py3%d" % minor, "py3"] + ["py3%d" % older for older in range(minor - 1, -1, -1)]
    platforms = _linux_platforms()
    ordered = []
    for abi in (cpython, "abi3", "none"):
        ordered += [(cpython, abi, platform) for platform in platforms]
    for older in range(minor - 1, 1, -1):
        ordered += [("cp3%d" % older, "abi3", platform) for platform in platforms]
    for python in pythons:
        ordered += [(python, "none", platform) for platform in platforms]
    ordered.append((cpython, "none", "any"))
    ordered += [(python, "none", "any") for python in pythons]
    ranks = {}
    for rank, tag in enumerate(ordered):
        if tag not in ranks:
            ranks[tag] = rank
    return ranks

def _wheel_rank(filename, ranks):
    if not filename.endswith(".whl"):
        return None
    parts = filename[:-len(".whl")].split("-")
    if len(parts) not in (5, 6):
        return None
    best = None
    for python in parts[-3].split("."):
        for abi in parts[-2].split("."):
            for platform in parts[-1].split("."):
                rank = ranks.get((python, abi, platform))
                if rank != None and (best == None or rank < best):
                    best = rank
    return best

def _normalized(name):
    out = []
    for c in name.lower().elems():
        out.append("-" if c in "._" else c)
    normalized = "".join(out)
    for _ in range(len(normalized)):
        if "--" not in normalized:
            break
        normalized = normalized.replace("--", "-")
    return normalized

def _words(line):
    return [word for word in line.replace("\t", " ").split(" ") if word]

def _option_value(tokens, option):
    if tokens[0] == option:
        return tokens[1] if len(tokens) > 1 else None
    if tokens[0].startswith(option + "="):
        return tokens[0][len(option) + 1:]
    return None

def _parse_lock(label, content, given = []):
    indexes = []
    requirements = []
    for line in content.replace("\\\n", " ").split("\n"):
        line = line.strip()
        if line.startswith("#"):
            continue
        line = line.split(" #")[0].strip()
        if not line:
            continue
        tokens = _words(line)
        if tokens[0].startswith("-"):
            found = [_option_value(tokens, option) for option in _INDEX_OPTIONS]
            found = [value for value in found if value]
            if not found:
                fail("%s: pyapp does not support the lock option `%s`" % (label, line))
            indexes.append(found[0])
            continue
        hashes = [token[len("--hash=sha256:"):] for token in tokens if token.startswith("--hash=sha256:")]
        spec = " ".join([token for token in tokens if not token.startswith("--hash=")])
        requirement, _, marker = spec.partition(";")
        name = requirement
        for end in _NAME_ENDS:
            name = name.split(end)[0]
        name = name.strip()
        if "==" not in requirement or " @ " in requirement or not hashes:
            fail("%s: `%s` must be pinned with `==` and carry sha256 hashes" % (label, spec))
        requirements.append(struct(
            name = name,
            version = requirement.split("==")[1].strip(),
            hashes = hashes,
            marked = bool(marker.strip()),
        ))
    if indexes and given:
        fail("%s names its own indexes, so pyapp.lock takes no indexes" % label)
    return indexes or given or [_DEFAULT_INDEX], requirements

def _origin(url):
    scheme, _, rest = url.partition("://")
    return scheme + "://" + rest.split("/")[0]

def _resolve(page, href):
    if href.startswith("http://") or href.startswith("https://"):
        return href
    if href.startswith("//"):
        return page.partition("://")[0] + ":" + href
    if href.startswith("/"):
        return _origin(page) + href
    base = page.rpartition("/")[0].split("/")
    for segment in href.split("/"):
        if segment == "..":
            base = base[:-1]
        elif segment != ".":
            base.append(segment)
    return "/".join(base)

def _anchors(page, html):
    found = []
    for chunk in html.split("<a ")[1:]:
        start = chunk.find("href=\"")
        if start < 0:
            continue
        href = chunk[start + len("href=\""):].split("\"")[0].replace("&amp;", "&")
        text = chunk.partition(">")[2].partition("</a>")[0].strip()
        url, _, fragment = href.partition("#")
        if not fragment.startswith("sha256="):
            continue
        filename = text or url.rpartition("/")[2].replace("%2B", "+")
        found.append(struct(filename = filename, url = _resolve(page, url), sha256 = fragment[len("sha256="):]))
    return found

def _pick(rctx, indexes, requirement, ranks):
    pinned = {sha: True for sha in requirement.hashes}
    listed = []
    for position, index in enumerate(indexes):
        page = index.rstrip("/") + "/" + _normalized(requirement.name) + "/"
        html = "simple/%d/%s.html" % (position, _normalized(requirement.name))
        if not rctx.download(page, output = html, allow_fail = True).success:
            continue
        listed += [anchor for anchor in _anchors(page, rctx.read(html)) if anchor.sha256 in pinned]
        rctx.delete(html)
    ranked = [(_wheel_rank(anchor.filename, ranks), anchor) for anchor in listed]
    ranked = sorted([entry for entry in ranked if entry[0] != None], key = lambda entry: (entry[0], entry[1].filename))
    if ranked:
        return ranked[0][1]
    if requirement.marked:
        return None
    fail("%s==%s has no wheel for linux x86_64 %s among the files its lock hashes pin (%s)" % (
        requirement.name,
        requirement.version,
        "cp3%d" % _minor(rctx.attr.python_version),
        ", ".join(sorted([anchor.filename for anchor in listed])) or "none found on " + ", ".join(indexes),
    ))

def _pyapp_wheels_impl(rctx):
    indexes, requirements = _parse_lock(rctx.attr.lock, rctx.read(rctx.attr.lock), rctx.attr.indexes)
    ranks = _supported_tags(_minor(rctx.attr.python_version))
    picked = [_pick(rctx, indexes, requirement, ranks) for requirement in requirements]
    pending = [
        rctx.download(wheel.url, output = "wheels/" + wheel.filename, sha256 = wheel.sha256, block = False)
        for wheel in picked
        if wheel
    ]
    interpreter = INTERPRETERS[rctx.attr.python_version]
    pending.append(rctx.download(
        interpreter.url,
        output = "interpreter/" + interpreter.path,
        sha256 = interpreter.sha256,
        block = False,
    ))
    for download in pending:
        download.wait()
    rctx.file("BUILD.bazel", "\n".join([
        "package(default_visibility = [\"//visibility:public\"])",
        "",
        "filegroup(",
        "    name = \"wheels\",",
        "    srcs = glob([\"wheels/*.whl\"]),",
        ")",
        "",
        "exports_files([\"interpreter/%s\"])" % interpreter.path,
        "",
    ]))

_pyapp_wheels = repository_rule(
    implementation = _pyapp_wheels_impl,
    attrs = {
        "indexes": attr.string_list(),
        "lock": attr.label(mandatory = True),
        "python_version": attr.string(mandatory = True),
    },
)

def _pyapp_hub_impl(rctx):
    interpreter = INTERPRETERS[rctx.attr.python_version]
    rctx.file("BUILD.bazel", "\n".join([
        "load(\"%s\", \"pyapp_lock\")" % rctx.attr._rules,
        "",
        "package(default_visibility = [\"//visibility:public\"])",
        "",
        "pyapp_lock(",
        "    name = \"%s\"," % rctx.attr.target,
        "    src = \"%s\"," % rctx.attr.lock,
        "    indexes = %s," % repr(rctx.attr.indexes),
        "    python_version = \"%s\"," % rctx.attr.python_version,
        ")",
        "",
        "pyapp_lock(",
        "    name = \"%s_wheels\"," % rctx.attr.target,
        "    src = \"%s\"," % rctx.attr.lock,
        "    indexes = %s," % repr(rctx.attr.indexes),
        "    interpreter = \"@%s//:interpreter/%s\"," % (rctx.attr.wheels, interpreter.path),
        "    python_version = \"%s\"," % rctx.attr.python_version,
        "    wheels = [\"@%s//:wheels\"]," % rctx.attr.wheels,
        ")",
        "",
    ]))

_pyapp_hub = repository_rule(
    implementation = _pyapp_hub_impl,
    attrs = {
        "indexes": attr.string_list(),
        "lock": attr.label(mandatory = True),
        "python_version": attr.string(mandatory = True),
        "target": attr.string(mandatory = True),
        "wheels": attr.string(mandatory = True),
        "_rules": attr.label(default = Label("//:lock.bzl")),
    },
)

def _pyapp_static_impl(rctx):
    interpreter = STATIC_INTERPRETERS[rctx.attr.python_version]
    rctx.download_and_extract(interpreter.url, sha256 = interpreter.sha256, stripPrefix = "python/install")
    stdlib = "lib/python" + rctx.attr.python_version
    rctx.file("BUILD.bazel", "\n".join([
        "package(default_visibility = [\"//visibility:public\"])",
        "",
        "filegroup(",
        "    name = \"interpreter\",",
        "    srcs = [\"bin/python%s\"] + glob(" % rctx.attr.python_version,
        "        [\"%s/**\"]," % stdlib,
        "        exclude = [",
        "            \"%s/config-*/**\"," % stdlib,
        "            \"%s/site-packages/**\"," % stdlib,
        "            \"%s/test/**\"," % stdlib,
        "        ],",
        "    ),",
        ")",
        "",
    ]))

_pyapp_static = repository_rule(
    implementation = _pyapp_static_impl,
    attrs = {
        "python_version": attr.string(mandatory = True),
    },
)

UV_PLATFORMS = {
    "linux_aarch64": "uv",
    "linux_x86_64": "uv",
    "macos_arm64": "uv",
    "macos_x86_64": "uv",
    "windows_x86_64": "uv.exe",
}

def _pyapp_uv_impl(rctx):
    if not rctx.attr.archive:
        rctx.file("BUILD.bazel", "\n".join([
            "package(default_visibility = [\"//visibility:public\"])",
            "",
            "genrule(",
            "    name = \"uv\",",
            "    outs = [\"uv.missing\"],",
            "    cmd = \"echo 'no uv for %s: the root module names its archive with pyapp.uv' >&2; exit 1\"," % rctx.attr.platform,
            ")",
            "",
        ]))
        return
    rctx.extract(rctx.attr.archive, stripPrefix = rctx.attr.strip_prefix)
    executable = UV_PLATFORMS[rctx.attr.platform]
    lines = ["package(default_visibility = [\"//visibility:public\"])", ""]
    if executable == "uv":
        lines.append("exports_files([\"uv\"])")
    else:
        lines.append("alias(name = \"uv\", actual = \"%s\")" % executable)
    rctx.file("BUILD.bazel", "\n".join(lines) + "\n")

_pyapp_uv = repository_rule(
    implementation = _pyapp_uv_impl,
    attrs = {
        "archive": attr.label(),
        "platform": attr.string(mandatory = True),
        "strip_prefix": attr.string(),
    },
)

_uv = tag_class(
    attrs = {
        "archive": attr.label(mandatory = True),
        "platform": attr.string(mandatory = True, values = sorted(UV_PLATFORMS)),
        "strip_prefix": attr.string(),
    },
)

_lock = tag_class(
    attrs = {
        "indexes": attr.string_list(doc = "The index and then the extra indexes the lock was compiled against, " +
                                           "for a lock that does not name them itself."),
        "name": attr.string(mandatory = True),
        "python_version": attr.string(mandatory = True),
        "src": attr.label(mandatory = True),
    },
)

def _pyapp_impl(mctx):
    archives = {}
    for module in mctx.modules:
        for tag in module.tags.uv:
            if not module.is_root:
                fail("pyapp.uv is the root module's to set; %s set it for %s" % (module.name, tag.platform))
            if tag.platform in archives:
                fail("pyapp.uv names %s twice" % tag.platform)
            archives[tag.platform] = tag
    for platform in UV_PLATFORMS:
        tag = archives.get(platform)
        _pyapp_uv(
            name = "pyapp_uv_" + platform,
            archive = tag.archive if tag else None,
            platform = platform,
            strip_prefix = tag.strip_prefix if tag else "",
        )
    for python_version in STATIC_INTERPRETERS:
        _pyapp_static(
            name = "pyapp_static_" + python_version.replace(".", "_"),
            python_version = python_version,
        )
    for module in mctx.modules:
        for tag in module.tags.lock:
            if tag.python_version not in INTERPRETERS:
                fail("pyapp.lock %s: python_version %s is not one of %s" % (tag.name, tag.python_version, sorted(INTERPRETERS)))
            wheels = tag.name + "_wheels"
            _pyapp_wheels(
                name = wheels,
                indexes = tag.indexes,
                lock = tag.src,
                python_version = tag.python_version,
            )
            _pyapp_hub(
                name = tag.name,
                indexes = tag.indexes,
                target = tag.name,
                lock = tag.src,
                python_version = tag.python_version,
                wheels = wheels,
            )

pyapp = module_extension(
    implementation = _pyapp_impl,
    tag_classes = {"lock": _lock, "uv": _uv},
)
