import argparse
import gzip
import hashlib
import io
import os
import struct
import tarfile

PAYLOAD_PLACEHOLDER = "0" * 64
OFFSET_WIDTH = 12
TRAILER_MAGIC = b"PYAPPWIN"


class Hashing:
    def __init__(self, out):
        self.out = out
        self.digest = hashlib.sha256()

    def write(self, data):
        self.digest.update(data)
        return self.out.write(data)

    def flush(self):
        self.out.flush()


def substituted(path, values):
    with open(path) as template:
        text = template.read()
    for key, value in values.items():
        text = text.replace("{" + key + "}", value)
    return text


def file_sha256(path):
    digest = hashlib.sha256()
    with open(path, "rb") as source:
        for block in iter(lambda: source.read(1 << 20), b""):
            digest.update(block)
    return digest.hexdigest()


def entry(name, size, mode):
    info = tarfile.TarInfo(name)
    info.size = size
    info.mode = mode
    info.mtime = 0
    info.uid = info.gid = 0
    info.uname = info.gname = ""
    return info


def placed(manifest):
    with open(manifest) as listing:
        for line in listing:
            mode, destination, source = line.rstrip("\n").split("\t")
            yield destination, source, int(mode, 8)


def field(text):
    raw = text.encode()
    return struct.pack("<I", len(raw)) + raw


def pack_windows(args):
    with open(args.header, "rb") as stub:
        prefix = stub.read()
    with open(args.out, "wb") as out:
        out.write(prefix)
        hashing = Hashing(out)
        with tarfile.open(fileobj=hashing, mode="w|", format=tarfile.USTAR_FORMAT) as tar:
            for destination, source, mode in sorted(placed(args.manifest), key=lambda placement: placement[0]):
                with open(source, "rb") as data:
                    tar.addfile(entry(destination, os.fstat(data.fileno()).st_size, mode), data)
        size = out.tell() - len(prefix)
        trailer = TRAILER_MAGIC + struct.pack("<QQ", len(prefix), size) + hashing.digest.digest()
        trailer += field(args.name) + field(args.program) + field(args.module)
        out.write(trailer)
        out.write(struct.pack("<I", len(trailer) + 4))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--name", required=True)
    parser.add_argument("--module", required=True)
    parser.add_argument("--program", required=True)
    parser.add_argument("--python", default="")
    parser.add_argument("--bundle", default="", choices=["", "lock", "wheels"])
    parser.add_argument("--lock")
    parser.add_argument("--interpreter", default="")
    parser.add_argument("--header", required=True)
    parser.add_argument("--launcher", default="")
    parser.add_argument("--manifest", required=True)
    parser.add_argument("--out", required=True)
    parser.add_argument("--format", default="unix", choices=["unix", "windows"])
    parser.add_argument("--lib-var", default="")
    parser.add_argument("--interp-infix", default="")
    parser.add_argument("--python-bin", default="")
    parser.add_argument("--uname-s", default="")
    parser.add_argument("--uname-m", default="")
    parser.add_argument("--platform-label", default="")
    parser.add_argument("--sha", default="")
    args = parser.parse_args()

    if args.format == "windows":
        pack_windows(args)
        os.chmod(args.out, 0o755)
        return

    environment = "%s-cpython-%s" % (file_sha256(args.lock), args.python) if args.lock else ""
    launcher = substituted(args.launcher, {
        "NAME": args.name,
        "MODULE": args.module,
        "PYTHON": args.python,
        "ENVIRONMENT": environment,
        "BUNDLE": args.bundle,
        "INTERPRETER": args.interpreter,
        "LIBVAR": args.lib_var,
        "INTERP_INFIX": args.interp_infix,
        "PYTHON_BIN": args.python_bin,
    }).encode()
    values = {
        "NAME": args.name,
        "PROGRAM": args.program,
        "ENVIRONMENT": environment,
        "PAYLOAD": PAYLOAD_PLACEHOLDER,
        "UNAME_S": args.uname_s,
        "UNAME_M": args.uname_m,
        "PLATFORM_LABEL": args.platform_label,
        "SHA": args.sha,
    }
    draft = substituted(args.header, dict(values, OFFSET="0" * OFFSET_WIDTH)).encode()
    offset = str(len(draft) + 1).zfill(OFFSET_WIDTH)

    with open(args.out, "wb") as out:
        out.write(draft)
        hashing = Hashing(out)
        with gzip.GzipFile(filename="", mode="wb", fileobj=hashing, mtime=0, compresslevel=6) as compressed:
            with tarfile.open(fileobj=compressed, mode="w|", format=tarfile.GNU_FORMAT) as tar:
                files = list(placed(args.manifest))
                files.append((args.program, None, 0o755))
                for destination, source, mode in sorted(files, key=lambda placement: placement[0]):
                    if source is None:
                        tar.addfile(entry(destination, len(launcher), mode), io.BytesIO(launcher))
                        continue
                    with open(source, "rb") as data:
                        tar.addfile(entry(destination, os.fstat(data.fileno()).st_size, mode), data)
        header = substituted(args.header, dict(values, OFFSET=offset, PAYLOAD=hashing.digest.hexdigest())).encode()
        if len(header) != len(draft):
            raise SystemExit("the header changed length once its payload hash and offset were filled in")
        out.seek(0)
        out.write(header)
    os.chmod(args.out, 0o755)


if __name__ == "__main__":
    main()
