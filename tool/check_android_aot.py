#!/usr/bin/env python3
"""Reject APK/AAB files whose Dart AOT code differs from Flutter's compiler output.

Android strips debug information, so compare the executable and constant-data
ELF sections rather than the hash of the entire native library.
"""

import argparse
from pathlib import Path
import struct
from zipfile import ZipFile


def aot_sections(data: bytes) -> dict[str, bytes]:
    if data[:4] != b"\x7fELF" or data[5] != 1 or data[4] not in (1, 2):
        raise ValueError("Expected a little-endian ELF library")
    wide = data[4] == 2
    header = struct.unpack_from("<16sHHIQQQIHHHHHH" if wide else "<16sHHIIIIIHHHHHH", data)
    section_offset, section_size, count, names_index = header[6], header[11], header[12], header[13]
    sections = [
        struct.unpack_from("<IIQQQQIIQQ" if wide else "<IIIIIIIIII", data, section_offset + i * section_size)
        for i in range(count)
    ]
    names_header = sections[names_index]
    names = data[names_header[4]:names_header[4] + names_header[5]]
    result = {}
    for section in sections:
        start = section[0]
        name = names[start:names.index(b"\0", start)].decode("ascii")
        if name in (".text", ".rodata"):
            result[name] = data[section[4]:section[4] + section[5]]
    if result.keys() != {".text", ".rodata"} or not all(result.values()):
        raise ValueError("Dart AOT .text/.rodata sections are missing or empty")
    return result


def check(artifact: Path, build_dir: Path, flavor: str) -> None:
    with ZipFile(artifact) as archive:
        libs = [name for name in archive.namelist() if name.endswith("/libapp.so")]
        if not libs:
            raise ValueError("No Dart AOT libraries found in release artifact")
        for name in libs:
            abi = name.split("/")[-2]
            compiled = build_dir / "app/intermediates/flutter" / f"{flavor}Release" / abi / "app.so"
            expected = aot_sections(compiled.read_bytes())
            actual = aot_sections(archive.read(name))
            if expected != actual:
                raise ValueError(f"STALE AOT CODE: {name} differs from {compiled}. Do not distribute this build.")
            print(f"OK: {abi} — packaged Dart code matches compiler output")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("artifact", type=Path)
    parser.add_argument("--flavor", choices=("play", "rustore"), default="rustore")
    parser.add_argument("--build-dir", type=Path, default=Path(__file__).resolve().parents[1] / "build")
    args = parser.parse_args()
    try:
        check(args.artifact, args.build_dir, args.flavor)
    except (ValueError, OSError, IndexError, struct.error) as error:
        parser.exit(1, f"Release verification failed: {error}\n")
