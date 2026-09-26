"""Extract pickup metadata with UCC (run 'build.ps1 -Tests' first)"""
import argparse
import json
from pathlib import Path
import runpy
import subprocess

ROOT = Path(__file__).resolve().parents[1]
WORLD = ROOT.parent / "Archipelago_ut99/worlds/ut99"


def extract():
    system = ROOT / ".build/System"
    config = (system / "Build.ini").read_text().replace(
        "[Engine.Engine]", "[Engine.Engine]\nNetworkDevice=IpDrv.TcpNetDriver")
    (system / "Catalog.ini").write_text(config)
    result = []
    catalog = runpy.run_path(str(WORLD / "catalog.py"))
    for map_index, name in enumerate(catalog["MAPS"]):
        game = "APAssaultCatalogProbe" if name.startswith("AS-") else "APCatalogProbe"
        process = subprocess.run([
            str(system / "UCC.exe"), "Engine.ServerCommandlet",
            f"{name}?Game=APTests.{game}?Port=0", "ini=Catalog.ini", "-nohomedir", "-lanplay"],
            cwd=system, capture_output=True, timeout=30, creationflags=subprocess.CREATE_NO_WINDOW)
        log = process.stdout.decode(errors="replace")
        assert process.returncode == 0 and "AP CATALOG DONE" in log, log[-4000:]
        pickups = []
        for line in log.splitlines():
            if "AP PICKUP|" not in line:
                continue
            _, actor, item_class, position, radius, height = line.split("|")
            if item_class.lower() not in catalog["PICKUP_CLASS_FAMILY"]:
                continue
            pickups.append({"map": map_index, "actor": actor, "class": item_class,
                            "position": [round(float(v), 3) for v in position.split(",")],
                            "radius": float(radius), "height": float(height)})
        pickups.sort(key=lambda p: (p["class"], p["position"], p["actor"]))
        assert pickups, f"No pickups in {name}"
        result.extend(pickups)
        print(f"{name}: {len(pickups)} pickups", flush=True)
    assert len(result) < 5000, "Increase the pickup offset range before adding more pickups"
    return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    target = WORLD / "pickups.json"
    entries = extract()
    if args.check or target.exists():
        existing = json.loads(target.read_text())
        assert len(existing) == len(entries), "Pickup count changed; preserve released IDs before updating"
        for old, new in zip(existing, entries):
            # Floor settling may differ by a fraction of a unit
            assert old["map"] == new["map"] and old["class"] == new["class"], (old, new)
            assert sum((a - b) ** 2 for a, b in zip(old["position"], new["position"])) < 4, (old, new)
            assert (old["radius"], old["height"]) == (new["radius"], new["height"]), (old, new)
    else:
        target.write_text(json.dumps(entries, indent=2) + "\n", encoding="utf-8")
    print(f"Verified {len(entries)} pickup locations")
