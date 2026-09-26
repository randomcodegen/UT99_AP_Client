from pathlib import Path
import os
import subprocess

import pytest


SYSTEM = Path(__file__).resolve().parents[1] / os.environ.get("UT99_BUILD_DIRECTORY", ".build") / "System"


@pytest.mark.parametrize("map_name,game", [
    ("CTF-Coret", "APModeProbeCTF"),
    ("DOM-Condemned", "APModeProbeDomination"),
    ("AS-Frigate", "APModeProbeAssault"),
    ("AS-Guardia", "APModeProbeAssault"),
    ("AS-HiSpeed", "APModeProbeAssault"),
    ("AS-Mazon", "APModeProbeAssault"),
    ("AS-OceanFloor", "APModeProbeAssault"),
    ("AS-Overlord", "APModeProbeAssault"),
    ("AS-Rook", "APModeProbeAssault"),
])
def test_mode_checks(map_name, game):
    config = (SYSTEM / "Build.ini").read_text().replace(
        "[Engine.Engine]", "[Engine.Engine]\nNetworkDevice=IpDrv.TcpNetDriver")
    (SYSTEM / "ModeTest.ini").write_text(config)
    result = subprocess.run([
        str(SYSTEM / "UCC.exe"), "Engine.ServerCommandlet",
        f"{map_name}?Game=APTests.{game}?APStage=1?Port=0",
        "ini=ModeTest.ini", "-nohomedir", "-lanplay",
    ], cwd=SYSTEM, capture_output=True, timeout=30)
    output = result.stdout.decode(errors="replace")
    assert result.returncode == 0 and f"AP MODE PASS: {map_name}" in output, output[-3000:]
