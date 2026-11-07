#!/usr/bin/env python3
"""Build the release zips for VendorFinder.

Outputs (in --out, default ./dist):
  VendorFinder-<version>.zip          only the addon
  VendorFinder-<version>-bundle.zip   addon + Questie + QuestieDB (Forever-only files)

Questie and QuestieDB are GPL-3.0 (https://github.com/Questie). The bundle keeps their
licenses and only trims files that the Forever client would never load (other flavors,
tests, docs). Pin the commits in QUESTIE_REF / QUESTIEDB_REF to a known-good state.
"""
import argparse
import os
import re
import shutil
import subprocess
import sys
import tempfile
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ADDON_DIR = os.path.join(ROOT, "VendorFinder")

QUESTIE_REPO = "https://github.com/Questie/Questie.git"
QUESTIEDB_REPO = "https://github.com/Questie/QuestieDB.git"
# Known-good commits (2026-11-06). Bump deliberately after testing in-game.
QUESTIE_REF = "e7cd308ee5493be26b245c68f67a2423a4b4abcb"
QUESTIEDB_REF = "21be34023b72cf2ec3027cb9a61a8b72a1910857"

QUESTIE_SKIP_DIRS = {".git", ".github", ".vscode", ".dockerfiles", ".types",
                     "ExternalScripts(DONOTINCLUDEINRELEASE)", "docs", "test", "cli"}
QUESTIE_KEEP_TOCS = {"Questie_Forever.toc", "Questie_Camelot.toc"}


def run(cmd, cwd=None):
    print("+", " ".join(cmd), flush=True)
    subprocess.check_call(cmd, cwd=cwd)


def clone(repo, ref, dest):
    run(["git", "init", "-q", dest])
    run(["git", "remote", "add", "origin", repo], cwd=dest)
    run(["git", "fetch", "-q", "--depth", "1", "origin", ref], cwd=dest)
    run(["git", "checkout", "-q", "FETCH_HEAD"], cwd=dest)


def addon_version():
    with open(os.path.join(ADDON_DIR, "VendorFinder.toc"), encoding="utf-8") as f:
        for line in f:
            m = re.match(r"##\s*Version:\s*(\S+)", line)
            if m:
                return m.group(1)
    raise SystemExit("no ## Version in VendorFinder.toc")


def questie_files(src):
    """Release-like file set for Questie: everything but tests, docs and other flavors."""
    out = []
    for root, dirs, files in os.walk(src):
        rel = os.path.relpath(root, src)
        dirs[:] = [d for d in dirs if d not in QUESTIE_SKIP_DIRS]
        for f in files:
            if f.startswith("."):
                continue
            if f.endswith((".test.lua", ".test.py", ".py", ".sh")):
                continue
            if f.endswith(".md") and f not in ("LICENSE.md", "gpl-3.0.md"):
                continue
            if rel == "." and f.endswith(".toc") and f not in QUESTIE_KEEP_TOCS:
                continue
            if rel == "." and f in ("setupTests.lua", ".pkgmeta"):
                continue
            out.append(os.path.normpath(os.path.join(rel, f)))
    # The Forever client may pick either suffix; a plain Questie.toc covers an unknown one.
    return out


def questiedb_files(src):
    """Only what QuestieDB.toc loads on Forever, plus licenses and the icon."""
    keep = {"QuestieDB.toc", "LICENSE.md", "gpl-3.0.md", "icons/QuestieTDB_64x64.png"}
    with open(os.path.join(src, "QuestieDB.toc"), encoding="utf-8") as f:
        for line in f:
            s = line.strip()
            if not s or s.startswith("#"):
                continue
            # Lines gated to legacy game types never load on Forever.
            if "AllowLoadGameType" in s:
                continue
            path = re.split(r"\s*\[", s)[0].strip().replace("\\", "/")
            keep.add(path)
    return sorted(p for p in keep if os.path.exists(os.path.join(src, p)))


def add_tree(zf, src_root, files, prefix):
    for rel in sorted(files):
        zf.write(os.path.join(src_root, rel), os.path.join(prefix, rel))


def add_dir(zf, src_dir, prefix):
    for root, _, files in os.walk(src_dir):
        for f in sorted(files):
            full = os.path.join(root, f)
            zf.write(full, os.path.join(prefix, os.path.relpath(full, src_dir)))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=os.path.join(ROOT, "dist"))
    ap.add_argument("--no-bundle", action="store_true", help="skip the Questie bundle")
    args = ap.parse_args()

    version = addon_version()
    os.makedirs(args.out, exist_ok=True)

    plain = os.path.join(args.out, f"VendorFinder-{version}.zip")
    with zipfile.ZipFile(plain, "w", zipfile.ZIP_DEFLATED) as zf:
        add_dir(zf, ADDON_DIR, "VendorFinder")
    print("wrote", plain)

    if args.no_bundle:
        return

    work = tempfile.mkdtemp(prefix="vf-bundle-")
    try:
        q = os.path.join(work, "Questie")
        qdb = os.path.join(work, "QuestieDB")
        clone(QUESTIE_REPO, QUESTIE_REF, q)
        clone(QUESTIEDB_REPO, QUESTIEDB_REF, qdb)

        bundle = os.path.join(args.out, f"VendorFinder-{version}-bundle.zip")
        with zipfile.ZipFile(bundle, "w", zipfile.ZIP_DEFLATED) as zf:
            add_dir(zf, ADDON_DIR, "VendorFinder")
            qfiles = questie_files(q)
            add_tree(zf, q, qfiles, "Questie")
            # Fallback toc for a client whose suffix we don't know.
            zf.write(os.path.join(q, "Questie_Forever.toc"), "Questie/Questie.toc")
            dfiles = questiedb_files(qdb)
            add_tree(zf, qdb, dfiles, "QuestieDB")
            for suffix in ("Forever", "Camelot"):
                zf.write(os.path.join(qdb, "QuestieDB.toc"), f"QuestieDB/QuestieDB_{suffix}.toc")
            zf.writestr("BUNDLE.txt",
                        f"VendorFinder {version}\n"
                        f"Questie   {QUESTIE_REF} (GPL-3.0, https://github.com/Questie/Questie)\n"
                        f"QuestieDB {QUESTIEDB_REF} (GPL-3.0, https://github.com/Questie/QuestieDB, source mode)\n"
                        "Unzip all three folders into World of Warcraft/_forever_/Interface/AddOns/\n")
        print("wrote", bundle, f"({len(qfiles)} Questie files, {len(dfiles)} QuestieDB files)")
    finally:
        shutil.rmtree(work, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
