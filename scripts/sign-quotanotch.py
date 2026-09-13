#!/usr/bin/env python3
"""Ad-hoc sign loose Mach-O helpers and nested bundles before their containers."""
import os
from pathlib import Path
import plistlib
import subprocess
import sys


def sign(path):
    subprocess.run(["codesign", "--force", "--sign", "-", "--timestamp=none", str(path)], check=True)


def main():
    app = Path(sys.argv[1]).resolve(strict=True)
    if app.suffix != ".app":
        raise SystemExit("Expected an app bundle")
    bundles = [app]
    files = []
    for directory, directories, names in os.walk(app, followlinks=False):
        for name in directories:
            path = Path(directory, name)
            if not path.is_symlink() and path.suffix in {".framework", ".xpc", ".app"}:
                bundles.append(path)
        files.extend(Path(directory, name) for name in names)

    # Signing a bundle's primary executable can implicitly sign its containing bundle.
    # Defer these executables to the bundle pass, after all embedded code is signed.
    primary_executables = set()
    for bundle in bundles:
        for relative in ["Contents/Info.plist", "Resources/Info.plist", "Info.plist",
                         "Versions/Current/Resources/Info.plist"]:
            info = bundle / relative
            if not info.is_file():
                continue
            with info.open("rb") as stream:
                executable = plistlib.load(stream).get("CFBundleExecutable")
            if executable:
                for candidate in [bundle / "Contents/MacOS" / executable, bundle / executable]:
                    if candidate.is_file():
                        primary_executables.add(candidate.resolve())
            break

    for path in files:
        if path.is_symlink() or path.resolve() in primary_executables:
            continue
        kind = subprocess.check_output(["file", "-b", str(path)], text=True)
        if "Mach-O" in kind:
            sign(path)
    for bundle in sorted(bundles, key=lambda path: len(path.parts), reverse=True):
        sign(bundle)


if __name__ == "__main__":
    main()
