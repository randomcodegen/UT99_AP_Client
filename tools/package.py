"""Package client and AP world source"""
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile
import argparse
import json

ROOT = Path(__file__).resolve().parents[1]
APCPP = ROOT.parent / "APCpp"
if not (APCPP / "Archipelago.cpp").is_file():
    APCPP = ROOT / ".deps/APCpp"

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--world", type=Path, default=ROOT.parent / "Archipelago_ut99/worlds/ut99")
    args = parser.parse_args()
    dist = ROOT / "dist"
    dist.mkdir(exist_ok=True)
    with ZipFile(dist / "ut99.apworld", "w", ZIP_DEFLATED) as archive:
        for path in sorted(args.world.rglob("*")):
            if path.is_file() and not {"test", "__pycache__"}.intersection(path.parts):
                name = "ut99/" + path.relative_to(args.world).as_posix()
                if path.name == "archipelago.json":
                    manifest = json.loads(path.read_text())
                    manifest.update(compatible_version=7, version=7)
                    archive.writestr(name, json.dumps(manifest, indent=2))
                else:
                    archive.write(path, name)
    licenses = {
        "APCpp-LGPL-2.1.txt": APCPP / "LICENSE",
        "IXWebSocket-BSD.txt": APCPP / "IXWebSocket/LICENSE.txt",
        "JsonCpp.txt": APCPP / "jsoncpp/LICENSE",
        "mbedTLS.txt": ROOT / ".native-build/mbedtls-3.6.4/LICENSE",
        "zlib.txt": APCPP / "zlib/LICENSE",
        "UT99-SDK.txt": ROOT / ".deps/sdk/README.md",
    }
    with ZipFile(dist / "UT99AP-client-0.5.4.zip", "w", ZIP_DEFLATED) as archive:
        for name in ("UT99AP.u", "UT99AP.int", "UT99APNative.u", "UT99APNative.dll"):
            archive.write(dist / "System" / name, "System/" + name)
        archive.write(ROOT / "README.md", "README.md")
        archive.write(ROOT / "THIRD_PARTY.md", "THIRD_PARTY.md")
        for name, source in licenses.items():
            archive.write(source, "licenses/" + name)
        archive.write(args.world / "docs/setup_en.md", "setup_en.md")
        archive.write(ROOT / "examples/UTPlayer.yaml", "UTPlayer.yaml")
    print(dist / "ut99.apworld")
    with ZipFile(dist / "UT99AP-native-source-0.5.4.zip", "w", ZIP_DEFLATED) as archive:
        for folder in ("native", "UT99AP", "UT99APNative", "APTests", "tests", "tools", "System", "examples"):
            for path in sorted((ROOT / folder).rglob("*")):
                if (path.is_file() and not {".git", "__pycache__", ".pytest_cache"}.intersection(path.parts)
                        and path.suffix not in {".pyc", ".lib", ".dll", ".exe"}):
                    archive.write(path, path.relative_to(ROOT).as_posix())
        for path in sorted(APCPP.rglob("*")):
            if (path.is_file() and not {".git", "__pycache__", ".pytest_cache", "test", "tests"}.intersection(path.parts)
                    and path.suffix not in {".pyc", ".lib", ".dll", ".exe", ".ini", ".log", ".env", ".pem", ".key"}):
                archive.write(path, ".deps/APCpp/" + path.relative_to(APCPP).as_posix())
        for name in ("build-native.ps1", "build.ps1", "README.md", "THIRD_PARTY.md"):
            archive.write(ROOT / name, name)
        archive.write(ROOT / ".native-build/UT99APNative.dir/Release/Bridge.obj", "relink/Bridge.obj")
        for name, source in licenses.items():
            archive.write(source, "licenses/" + name)
    print(dist / "UT99AP-client-0.5.4.zip")
    print(dist / "UT99AP-native-source-0.5.4.zip")
