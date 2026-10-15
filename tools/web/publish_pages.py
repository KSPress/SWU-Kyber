#!/usr/bin/env python3
"""Publishes build/web to GitHub Pages (branch gh-pages of this repo's origin).

  python -I tools/web/build_web.py      # build first
  python -I tools/web/publish_pages.py

The gh-pages branch holds only the built site, as a single commit that is
replaced on every publish (no history of old builds piles up in the repo).
One-time setup on GitHub: Settings -> Pages -> Source: "Deploy from a branch",
branch gh-pages, folder / (root).
The site then lives at https://<owner>.github.io/<repo>/ and installed copies
(home-screen apps) pick up each new publish on their next launch.
"""
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SITE = ROOT / "build" / "web"
STAGE = ROOT / "build" / "pages"
LOCAL_ONLY = {"play.py", "Play SWU Kyber.bat", "Play on Phone (same Wi-Fi).bat", "README.txt"}

if not (SITE / "index.html").exists():
    sys.exit("build/web is missing - run tools/web/build_web.py first")
if (SITE / "art").exists():
    sys.exit("build/web/art exists (card art files) - the public site must load art from the "
             "official server instead; run tools/web/build_art_map.py and rebuild")
remote = subprocess.run(["git", "-C", str(ROOT), "remote", "get-url", "origin"],
                        capture_output=True, text=True, check=True).stdout.strip()
if STAGE.exists():
    shutil.rmtree(STAGE, onerror=lambda f, p, _: (Path(p).chmod(0o700), f(p)))
shutil.copytree(SITE, STAGE, ignore=lambda d, names: [n for n in names if n in LOCAL_ONLY])
(STAGE / "README.md").write_text(
    "# SWU Kyber - web app build\n\nBuilt site for GitHub Pages. Source: the `main` branch.\n\n"
    "Unofficial, non-commercial fan project. Not affiliated with Disney, Lucasfilm or Fantasy Flight Games. "
    "Star Wars characters, cards, logos and art are property of Disney and/or Fantasy Flight Games.\n",
    encoding="utf-8")
rev = subprocess.run(["git", "-C", str(ROOT), "rev-parse", "--short", "HEAD"],
                     capture_output=True, text=True).stdout.strip()


def git(*a):
    subprocess.run(["git", "-C", str(STAGE), *a], check=True)


git("init", "-q", "-b", "gh-pages")
git("add", "-A")
git("-c", "core.autocrlf=false", "commit", "-q", "-m", f"Web app build from {rev}")
git("push", "-q", "--force", remote, "gh-pages")
owner_repo = remote.rstrip("/").removesuffix(".git").split("github.com/")[-1]
owner, repo = owner_repo.split("/", 1)
print(f"published -> https://{owner.lower()}.github.io/{repo}/")
