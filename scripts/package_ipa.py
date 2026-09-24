#!/usr/bin/env python3
"""Package only unsigned, thin arm64 iPhoneOS apps. No signing credentials needed."""
import argparse
import os
from pathlib import Path
import plistlib
import struct
import tempfile
import zipfile


def validate_macho(path, executable=False):
    data = path.read_bytes()
    if len(data) < 32:
        raise ValueError(f"Truncated Mach-O: {path}")
    magic, cpu, _, kind, count, size, _, _ = struct.unpack_from("<8I", data)
    if magic != 0xFEEDFACF or cpu != 0x0100000C or (executable and kind != 2):
        raise ValueError(f"Expected thin arm64 Mach-O {'executable' if executable else ''}: {path}")
    end = 32 + size
    if end > len(data) or count > size // 8:
        raise ValueError(f"Truncated load commands: {path}")
    offset, platform = 32, None
    for _ in range(count):
        if offset + 8 > end:
            raise ValueError("Missing load command")
        command, length = struct.unpack_from("<2I", data, offset)
        if length < 8 or offset + length > end:
            raise ValueError("Invalid load command size")
        if command == 0x1D:
            raise ValueError(f"Code signature present; expected unsigned build: {path}")
        if command == 0x32:
            if length < 24:
                raise ValueError("Invalid build-version command")
            platform = struct.unpack_from("<I", data, offset + 8)[0]
        # All non-system dependencies must be embedded under Frameworks.
        if command in (0xC, 0x80000018, 0x8000001F, 0x20):
            if length < 24:
                raise ValueError("Invalid dylib command")
            start = struct.unpack_from("<I", data, offset + 8)[0]
            if start < 24 or start >= length:
                raise ValueError("Invalid dylib name offset")
            name = data[offset + start:offset + length].split(b"\0", 1)[0].decode("utf-8")
            if not name.startswith(("/System/Library/", "/usr/lib/")):
                raise ValueError(f"Unexpected non-system dynamic dependency: {name}; use static linkage")
        offset += length
    if offset != end or platform != 2:
        raise ValueError(f"Expected iOS device platform (not simulator): {path}")


def package(app, output):
    app, output = Path(app), Path(output)
    if not app.is_dir() or app.suffix != ".app" or app.is_symlink():
        raise ValueError("Input must be a real .app directory")
    files = sorted(app.rglob("*"))
    if any(p.is_symlink() for p in files):
        raise ValueError("Symlinks are not allowed in this static-link app")
    if any(p.name in ("_CodeSignature", "embedded.mobileprovision") for p in files):
        raise ValueError("Signing material found in unsigned app")
    try:
        info = plistlib.loads((app / "Info.plist").read_bytes())
    except (OSError, plistlib.InvalidFileException) as exc:
        raise ValueError("Missing or invalid Info.plist") from exc
    name = info.get("CFBundleExecutable", "")
    if not name or Path(name).name != name or name in (".", ".."):
        raise ValueError("Invalid CFBundleExecutable")
    if info.get("CFBundleSupportedPlatforms") != ["iPhoneOS"] or info.get("CFBundlePackageType") != "APPL":
        raise ValueError("Expected iPhoneOS app bundle")
    binary = app / name
    if not binary.is_file() or not (binary.stat().st_mode & 0o111):
        raise ValueError("Missing executable or execute permission")
    validate_macho(binary, executable=True)
    for file in files:
        if file.is_file() and file != binary:
            with file.open("rb") as stream:
                magic = stream.read(4)
            if magic in (b"\xcf\xfa\xed\xfe", b"\xca\xfe\xba\xbe", b"\xbe\xba\xfe\xca"):
                validate_macho(file)
    output.parent.mkdir(parents=True, exist_ok=True)
    if output.resolve().is_relative_to(app.resolve()):
        raise ValueError("IPA output must be outside the app")
    fd, temporary = tempfile.mkstemp(suffix=".ipa", dir=output.parent)
    os.close(fd)
    try:
        with zipfile.ZipFile(temporary, "w", zipfile.ZIP_DEFLATED) as archive:
            for file in files:
                if file.is_file():
                    archive.write(file, Path("Payload") / app.name / file.relative_to(app))
        with zipfile.ZipFile(temporary) as archive:
            if archive.testzip() is not None:
                raise ValueError("IPA checksum verification failed")
        os.replace(temporary, output)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    package(args.app, args.output)
    print(f"Validated unsigned IPA: {args.output}")
