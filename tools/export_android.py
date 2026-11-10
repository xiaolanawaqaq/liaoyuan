#!/usr/bin/env python3
"""Export Android without storing signing credentials in the project."""

import argparse
import json
import os
from pathlib import Path
import subprocess


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--credentials", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--log", type=Path, required=True)
    args = parser.parse_args()
    credentials = json.loads(args.credentials.read_text())
    output = args.output.resolve()
    if output.exists():
        raise SystemExit("Output exists; choose another filename to preserve that APK.")
    output.parent.mkdir(parents=True, exist_ok=True)
    project = Path(__file__).resolve().parents[1]
    env = os.environ.copy()
    env.update({
        "JAVA_HOME": "/usr/lib/jvm/java-17-openjdk-amd64",
        "ANDROID_HOME": "/root/android-sdk",
        "ANDROID_SDK_ROOT": "/root/android-sdk",
        "GODOT_SILENCE_ROOT_WARNING": "1",
        "GODOT_ANDROID_KEYSTORE_RELEASE_PATH": credentials["keystore"],
        "GODOT_ANDROID_KEYSTORE_RELEASE_USER": credentials["alias"],
        "GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD": credentials["password"],
    })
    args.log.parent.mkdir(parents=True, exist_ok=True)
    # Gradle output can include signing parameters, so logs stay private.
    fd = os.open(str(args.log), os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, "w") as log:
        result = subprocess.run([
            "godot", "--headless", "--path", str(project),
            "--export-release", "Android", str(output),
        ], env=env, stdout=log, stderr=subprocess.STDOUT, timeout=1200)
    if result.returncode:
        raise SystemExit(f"Export failed (exit {result.returncode}); inspect the private log.")
    if not output.is_file() or output.stat().st_size < 1024:
        raise SystemExit("Export returned success without a valid output file.")
    print(f"Exported {output} ({output.stat().st_size} bytes)")


if __name__ == "__main__":
    main()
