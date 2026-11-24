"""Development install: copies the addon's runtime files into WoW: Forever's AddOns folder and verifies every
file byte for byte (same idea as BlazonGuild's install-game.mjs).

Usage:  python tools/install.py            (default path: C:/Program Files (x86)/World of Warcraft/_forever_)
        WOW_FOREVER_DIR=D:/Games/WoW/_forever_ python tools/install.py
Only TOC, XML, the Lua folders and the in-game images are copied: tests/, docs/ and tools/ never reach the game. Two add-ons are
installed: SafeLoot (MIT) and SafeLoot_LootData (GPL-2.0 loot tables, optional).
"""
import hashlib
import os
import shutil
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GAME = os.environ.get("WOW_FOREVER_DIR", "C:/Program Files (x86)/World of Warcraft/_forever_")
DEST = os.path.join(GAME, "Interface", "AddOns", "SafeLoot")
RUNTIME_DIRS = ["Core", "Data", "Locales", "Logic", "Media", "Modules", "UI"]
RUNTIME_FILES = ["SafeLoot.toc", "Bindings.xml", "LICENSE"]


PACK = "SafeLoot_LootData"


def pack_files():
    """Files of the optional data add-on, relative to the project root."""
    base = os.path.join(ROOT, PACK)
    return sorted(os.path.join(PACK, n) for n in os.listdir(base)) if os.path.isdir(base) else []


def files():
    out = [f for f in RUNTIME_FILES if os.path.exists(os.path.join(ROOT, f))]
    for d in RUNTIME_DIRS:
        for base, _, names in os.walk(os.path.join(ROOT, d)):
            for n in names:
                if n.endswith((".lua", ".xml", ".tga")):
                    out.append(os.path.relpath(os.path.join(base, n), ROOT))
    out = sorted(out)
    # every file the TOC loads must travel (a new folder forgotten here once left the game without its data)
    have = {f.replace(os.sep, "/") for f in out}
    with open(os.path.join(ROOT, "SafeLoot.toc"), encoding="utf-8") as toc:
        listed = [l.strip().replace(chr(92), "/") for l in toc if l.strip() and not l.startswith("#")]
    missing = [f for f in listed if f not in have]
    if missing:
        raise SystemExit("The TOC lists files that would not be installed: " + ", ".join(missing))
    return out


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
    addons = os.path.dirname(DEST)
    if os.path.isdir(os.path.join(addons, PACK)):
        shutil.rmtree(os.path.join(addons, PACK))
    for rel in pack_files():
        os.makedirs(os.path.join(addons, PACK), exist_ok=True)
        shutil.copy2(os.path.join(ROOT, rel), os.path.join(addons, rel))
        if digest(os.path.join(ROOT, rel)) != digest(os.path.join(addons, rel)):
            bad.append(rel)
    if bad:
        print("Incomplete copy:", bad)
        return 1
    print(f"{PACK} installed ({len(pack_files())} files verified)")
    print(f"SafeLoot installed in {DEST} ({len(copied)} files verified)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
