#!/usr/bin/env python3
"""Exports the browser build and packages it as a private zip.

  python -I tools/web/build_web.py [path/to/godot]

Output: build/web/ (index.html, .wasm, .pck, launcher) and
        build/SWU-Kyber-web.zip  <- contains card art/text: keep it private.
Needs Godot 4.7.2 with export templates installed, and game/ip/ populated
(tools/import_cards.py, convert_art.gd, build_assets.gd).
"""
import shutil
import subprocess
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
GODOT = sys.argv[1] if len(sys.argv) > 1 else r"E:\godot-windows-64-stable\Godot_v4.7.2-stable_win64_console.exe"
OUT = ROOT / "build" / "web"

if not (ROOT / "game" / "ip" / "data" / "cards.json").exists():
    sys.exit("game/ip is empty - import the cards and art first (see README).")
if OUT.exists():
    shutil.rmtree(OUT)
OUT.mkdir(parents=True)
subprocess.run([GODOT, "--headless", "--path", str(ROOT / "game"), "--import"], check=False)
r = subprocess.run([GODOT, "--headless", "--path", str(ROOT / "game"), "--export-release", "Web", str(OUT / "index.html")])
if r.returncode != 0 or not (OUT / "index.pck").exists():
    sys.exit("export failed - are the 4.7.2 export templates installed?")
for f in ("play.py", "Play SWU Kyber.bat"):
    shutil.copy(ROOT / "tools" / "web" / f, OUT / f)
(OUT / "README.txt").write_text(
    "SWU Kyber - browser build (unofficial, non-commercial fan project)\n\n"
    "Windows: double-click 'Play SWU Kyber.bat'.\n"
    "Mac/Linux: run  python3 play.py  in this folder.\n"
    "Then play at http://localhost:8060 (it opens automatically).\n\n"
    "Contains Star Wars: Unlimited card art and text (Lucasfilm Ltd. / Fantasy Flight Games).\n"
    "For personal use only - do not upload or share publicly.\n", encoding="utf-8")
zp = ROOT / "build" / "SWU-Kyber-web.zip"
with zipfile.ZipFile(zp, "w", zipfile.ZIP_DEFLATED) as z:
    for p in OUT.rglob("*"):
        z.write(p, Path("SWU-Kyber-web") / p.relative_to(OUT))
size = sum(p.stat().st_size for p in OUT.rglob("*")) / 1e6
print(f"web build: {OUT}  ({size:.0f} MB)\nzip: {zp}  ({zp.stat().st_size / 1e6:.0f} MB)")
