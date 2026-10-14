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
print(f"APK: {OUT} ({OUT.stat().st_size / 1e6:.0f} MB)")
