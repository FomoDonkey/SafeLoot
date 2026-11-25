"""Builds dist/SafeLoot-<version>.zip for CurseForge / Wago: the two add-on folders, ready to unzip into AddOns.

    python tools/package.py

Refuses to build if the versions of the two TOC files differ or a file listed in a TOC is missing; then opens the zip
again and checks it byte for byte.
"""
import hashlib
import os
import re
import sys
import zipfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import install  # noqa: E402

ROOT = install.ROOT


def version(toc):
    text = open(os.path.join(ROOT, toc), encoding="utf-8").read()
    return re.search(r"^## Version:\s*(\S+)", text, re.M).group(1)


def main():
    v = version("SafeLoot.toc")
    if version(os.path.join(install.PACK, install.PACK + ".toc")) != v:
        print("The two add-ons have different versions.")
        return 1
    entries = {"SafeLoot/" + f.replace(os.sep, "/"): f for f in install.files()}
    entries.update({f.replace(os.sep, "/"): f for f in install.pack_files()})
    os.makedirs(os.path.join(ROOT, "dist"), exist_ok=True)
    path = os.path.join(ROOT, "dist", "SafeLoot-%s.zip" % v)
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as z:
        for arc in sorted(entries):
            z.write(os.path.join(ROOT, entries[arc]), arc)
    with zipfile.ZipFile(path) as z:
        names = z.namelist()
        bad = [n for n in names if hashlib.sha256(z.read(n)).digest() !=
               hashlib.sha256(open(os.path.join(ROOT, entries[n]), "rb").read()).digest()]
    if bad or sorted(names) != sorted(entries):
        print("The zip does not match the project:", bad)
        return 1
    print("%s (%d files, %d KB)" % (path, len(names), os.path.getsize(path) // 1024))
    return 0


if __name__ == "__main__":
    sys.exit(main())
