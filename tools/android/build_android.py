#!/usr/bin/env python3
"""Builds the signed Android app: build/android/swu_kyber.apk (private: contains card art).

  python -I tools/android/build_android.py [path/to/godot]

Expects the local toolchain in tools/android-sdk/ (git-ignored):
  jdk17/                      Eclipse Temurin JDK 17
  sdk/                        Android SDK with platform-tools + build-tools (apksigner)
  kyber-release.keystore      signing key  (keep it! updates must be signed with the same key)
  release-keystore.pass       its password
Godot's editor settings must point export/android/java_sdk_path and
android_sdk_path at those folders.
"""
import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
TC = ROOT / "tools" / "android-sdk"
GODOT = sys.argv[1] if len(sys.argv) > 1 else r"E:\godot-windows-64-stable\Godot_v4.7.2-stable_win64_console.exe"
OUT = ROOT / "build" / "android" / "swu_kyber.apk"

for need in ("jdk17", "sdk", "kyber-release.keystore", "release-keystore.pass"):
    if not (TC / need).exists():
        sys.exit(f"missing tools/android-sdk/{need} - see the docstring")
OUT.parent.mkdir(parents=True, exist_ok=True)
env = dict(os.environ,
           JAVA_HOME=str(TC / "jdk17"),
           GODOT_ANDROID_KEYSTORE_RELEASE_PATH=str(TC / "kyber-release.keystore"),
           GODOT_ANDROID_KEYSTORE_RELEASE_USER="kyber",
           GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD=(TC / "release-keystore.pass").read_text().strip())
r = subprocess.run([GODOT, "--headless", "--path", str(ROOT / "game"), "--export-release", "Android", str(OUT)], env=env)
if r.returncode != 0 or not OUT.exists():
    sys.exit("Android export failed")

# --- Godot 4.7.2 export bug: the APK keeps a resource reference to
# res/mipmap-anydpi-v26/themed_icon.xml but drops the file, so Android refuses
# the package ("There's a problem with the app file"). Restore any resource the
# template has but the export lost, then re-align and re-sign.
import shutil
import zipfile

TEMPLATE = Path(os.environ.get("APPDATA", "")) / "Godot" / "export_templates" / "4.7.2.stable" / "android_release.apk"
BT = sorted((TC / "sdk" / "build-tools").iterdir())[-1]
with zipfile.ZipFile(TEMPLATE) as t, zipfile.ZipFile(OUT) as a:
    have = set(a.namelist())
    missing = [i for i in t.infolist() if i.filename.startswith("res/") and i.filename not in have]
if missing:
    tmp = OUT.with_suffix(".fixed.apk")
    with zipfile.ZipFile(OUT) as a, zipfile.ZipFile(tmp, "w") as out, zipfile.ZipFile(TEMPLATE) as t:
        for info in a.infolist():
            if info.filename.startswith("META-INF/"):
                continue  # old signature: re-signed below
            out.writestr(info, a.read(info.filename), compress_type=info.compress_type)
        for info in missing:
            out.writestr(info, t.read(info.filename), compress_type=info.compress_type)
            print("restored", info.filename)
    aligned = OUT.with_suffix(".aligned.apk")
    subprocess.run([str(BT / "zipalign.exe"), "-P", "16", "-f", "4", str(tmp), str(aligned)], check=True)
    tmp.unlink()
    shutil.move(aligned, OUT)
    subprocess.run([str(BT / "apksigner.bat"), "sign", "--ks", env["GODOT_ANDROID_KEYSTORE_RELEASE_PATH"],
                    "--ks-key-alias", "kyber", "--ks-pass", "env:GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD",
                    "--key-pass", "env:GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD", str(OUT)], env=env, check=True)
subprocess.run([str(BT / "apksigner.bat"), "verify", str(OUT)], env=env, check=True)
subprocess.run([str(BT / "zipalign.exe"), "-c", "-P", "16", "4", str(OUT)], check=True)
badging = subprocess.run([str(BT / "aapt2.exe"), "dump", "badging", str(OUT)], capture_output=True, text=True)
if "no such path exists" in badging.stderr or badging.returncode != 0:
    sys.exit("APK still has broken resources: " + badging.stderr)
print(f"APK: {OUT} ({OUT.stat().st_size / 1e6:.0f} MB)")
