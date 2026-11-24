"""Development install: copies the addon's runtime files into WoW: Forever's AddOns folder and verifies every
file byte for byte (same idea as BlazonGuild's install-game.mjs).

Usage:  python tools/install.py            (default path: C:/Program Files (x86)/World of Warcraft/_forever_)
        WOW_FOREVER_DIR=D:/Games/WoW/_forever_ python tools/install.py
Only TOC, XML and the Lua folders are copied: tests/, docs/ and tools/ never reach the game.
"""
import hashlib
import os
import shutil
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GAME = os.environ.get("WOW_FOREVER_DIR", "C:/Program Files (x86)/World of Warcraft/_forever_")
DEST = os.path.join(GAME, "Interface", "AddOns", "SafeLoot")
RUNTIME_DIRS = ["Core", "Locales", "Logic", "Modules", "UI"]
RUNTIME_FILES = ["SafeLoot.toc", "Bindings.xml", "LICENSE"]


def files():
    out = [f for f in RUNTIME_FILES if os.path.exists(os.path.join(ROOT, f))]
    for d in RUNTIME_DIRS:
        for base, _, names in os.walk(os.path.join(ROOT, d)):
            for n in names:
                if n.endswith(".lua") or n.endswith(".xml"):
                    out.append(os.path.relpath(os.path.join(base, n), ROOT))
    return sorted(out)


def digest(path):
    with open(path, "rb") as f:
        return hashlib.sha256(f.read()).hexdigest()


def main():
    if not os.path.isdir(os.path.join(GAME, "Interface", "AddOns")):
        print(f"AddOns folder not found under {GAME}. Set WOW_FOREVER_DIR.")
        return 1
    if os.path.isdir(DEST):
        shutil.rmtree(DEST)  # remove files deleted from the project
    copied = files()
    for rel in copied:
        target = os.path.join(DEST, rel)
        os.makedirs(os.path.dirname(target), exist_ok=True)
        shutil.copy2(os.path.join(ROOT, rel), target)
    bad = [rel for rel in copied if digest(os.path.join(ROOT, rel)) != digest(os.path.join(DEST, rel))]
    if bad:
        print("Incomplete copy:", bad)
        return 1
    print(f"SafeLoot installed in {DEST} ({len(copied)} files verified)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
