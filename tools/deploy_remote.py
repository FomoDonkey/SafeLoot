"""Deploys SafeLoot to another Windows PC over SSH and verifies every file.

Usage:  python tools/deploy_remote.py --yes      (without --yes it only shows what it would do)
The target comes from tools/remote.local.json (not in git: it holds your own PC's address), e.g.
    {"remote": "user@192.168.1.50", "addons": "D:/Games/World of Warcraft/_forever_/Interface/AddOns"}
or from the environment variables SAFELOOT_REMOTE and SAFELOOT_REMOTE_ADDONS.
Steps: build a zip of the runtime files (same selection as install.py) -> scp zip + PowerShell script -> unzip into
AddOns/SafeLoot (replacing the old copy) -> compare SHA256 of every file with the local zip. Refuses to run while
WoW is open on the remote PC (a running client would not see the update anyway).
"""
import hashlib
import os
import subprocess
import sys
import tempfile
import zipfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import install  # noqa: E402  (shares the list of runtime files)

ROOT = install.ROOT
import json  # noqa: E402

_LOCAL = os.path.join(os.path.dirname(os.path.abspath(__file__)), "remote.local.json")
_CONFIG = json.load(open(_LOCAL, encoding="utf-8")) if os.path.exists(_LOCAL) else {}
REMOTE = os.environ.get("SAFELOOT_REMOTE", _CONFIG.get("remote"))
ADDONS = os.environ.get("SAFELOOT_REMOTE_ADDONS", _CONFIG.get("addons"))

PS1 = r"""
$ErrorActionPreference = 'Stop'
$addons = '__ADDONS__'
$zip = Join-Path $HOME 'SafeLoot-deploy.zip'
if (-not (Test-Path $addons)) { throw "AddOns folder not found: $addons" }
if (Get-Process Wow -ErrorAction SilentlyContinue) { Write-Output 'WOW_RUNNING'; Remove-Item -Force $zip; exit 3 }
$dest = Join-Path $addons 'SafeLoot'
if (Test-Path $dest) { Remove-Item -Recurse -Force $dest }
Expand-Archive -Path $zip -DestinationPath $addons -Force
Get-ChildItem -Path $dest -Recurse -File | ForEach-Object {
  $rel = $_.FullName.Substring($dest.Length + 1).Replace([string][char]92, '/')
  Write-Output ((Get-FileHash -Algorithm SHA256 -Path $_.FullName).Hash.ToLower() + ' ' + $rel)
}
Remove-Item -Force $zip
"""


def version():
    for line in open(os.path.join(ROOT, "SafeLoot.toc"), encoding="utf-8"):
        if line.startswith("## Version:"):
            return line.split(":", 1)[1].strip()
    return "dev"


def main():
    # safety: it changes another PC, so it never runs by accident (e.g. "--help" used to deploy)
    if "--yes" not in sys.argv:
        print(__doc__)
        print(f"Target: {REMOTE or '(none)'} -> {ADDONS or '(none)'}")
        print("Nothing was done. Run again with --yes to deploy.")
        return 0
    if not REMOTE or not ADDONS:
        print("No target: create tools/remote.local.json (see the docstring) or set SAFELOOT_REMOTE/_ADDONS.")
        return 2
    files = install.files()
    tmp = tempfile.mkdtemp()
    zip_path = os.path.join(tmp, "SafeLoot-deploy.zip")
    local = {}
    with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as z:
        for rel in files:
            data = open(os.path.join(ROOT, rel), "rb").read()
            arc = "SafeLoot/" + rel.replace(os.sep, "/")
            z.writestr(arc, data)
            local[rel.replace(os.sep, "/")] = hashlib.sha256(data).hexdigest()
    ps1_path = os.path.join(tmp, "safeloot_deploy.ps1")
    with open(ps1_path, "w", encoding="utf-8") as f:
        f.write(PS1.replace("__ADDONS__", ADDONS.replace("/", "\\")))
    subprocess.run(["scp", "-q", "-o", "BatchMode=yes", zip_path, ps1_path, REMOTE + ":"], check=True)
    result = subprocess.run(
        ["ssh", "-o", "BatchMode=yes", REMOTE,
         "powershell -NoProfile -ExecutionPolicy Bypass -File safeloot_deploy.ps1; Remove-Item safeloot_deploy.ps1"],
        capture_output=True, text=True, encoding="utf-8", errors="replace")
    if "WOW_RUNNING" in result.stdout:
        print("WoW is running on the remote PC: close it and run again.")
        return 3
    remote = {}
    for line in result.stdout.splitlines():
        parts = line.strip().split(" ", 1)
        if len(parts) == 2 and len(parts[0]) == 64:
            remote[parts[1]] = parts[0]
    missing = sorted(f for f in local if f not in remote)
    mismatched = sorted(f for f in local if f in remote and remote[f] != local[f])
    extra = sorted(f for f in remote if f not in local)
    if missing or mismatched or extra or result.returncode != 0:
        print("Deploy FAILED", {"missing": missing, "mismatched": mismatched, "extra": extra})
        print(result.stdout[-1500:], result.stderr[-1500:])
        return 1
    print(f"SafeLoot {version()} deployed to {REMOTE} ({len(local)} files verified byte for byte)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
