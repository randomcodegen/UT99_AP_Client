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
    parser.add_argument("--architecture", choices=("x86", "x64"), default="x86")
    args = parser.parse_args()
    dist = ROOT / "dist"
    dist.mkdir(exist_ok=True)
    suffix = "-x64" if args.architecture == "x64" else ""
    system = dist / "x64/System" if suffix else dist / "System"
    native_build = ROOT / (".native-build" + suffix)
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
        "mbedTLS.txt": native_build / "mbedtls-3.6.4/LICENSE",
        "zlib.txt": APCPP / "zlib/LICENSE",
        "UT99-SDK.txt": ROOT / ".deps/sdk/README.md",
    }
    if suffix:
        licenses["UT99-SDK.txt"] = ROOT / ".deps/sdk-469f-rc5/SDKLICENSE.md"
    with ZipFile(dist / f"UT99AP-client-1.0.0{suffix}.zip", "w", ZIP_DEFLATED) as archive:
        for name in ("UT99AP.u", "UT99AP.int", "UT99APNative.u", "UT99APNative.dll"):
            archive.write(system / name, "System/" + name)
        archive.write(ROOT / "README.md", "README.md")
        archive.write(ROOT / "THIRD_PARTY.md", "THIRD_PARTY.md")
        for name, source in licenses.items():
            archive.write(source, "licenses/" + name)
        archive.write(args.world / "docs/setup_en.md", "setup_en.md")
    print(dist / "ut99.apworld")
    with ZipFile(dist / f"UT99AP-native-source-1.0.0{suffix}.zip", "w", ZIP_DEFLATED) as archive:
        for folder in ("native", "UT99AP", "UT99APNative", "APTests", "tests", "tools", "System"):
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
        archive.write(native_build / "UT99APNative.dir/Release/Bridge.obj", "relink/Bridge.obj")
        for name, source in licenses.items():
            archive.write(source, "licenses/" + name)
    print(dist / f"UT99AP-client-1.0.0{suffix}.zip")
    print(dist / f"UT99AP-native-source-1.0.0{suffix}.zip")
