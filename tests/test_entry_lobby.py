from pathlib import Path
import os
import subprocess

import pytest


SYSTEM = Path(__file__).resolve().parents[1] / os.environ.get("UT99_BUILD_DIRECTORY", ".build") / "System"


@pytest.mark.parametrize("map_name", ["Entry", "DM-Oblivion"])
def test_entry_lobby(map_name):
    config = (SYSTEM / "Build.ini").read_text().replace(
        "[Engine.Engine]", "[Engine.Engine]\nNetworkDevice=IpDrv.TcpNetDriver")
    (SYSTEM / "EntryTest.ini").write_text(config)
    result = subprocess.run([
        str(SYSTEM / "UCC.exe"), "Engine.ServerCommandlet",
        f"{map_name}?Game=APTests.APEntryProbeGame?Port=0",
        "ini=EntryTest.ini", "-nohomedir", "-lanplay",
    ], cwd=SYSTEM, capture_output=True, timeout=15)
    output = result.stdout.decode(errors="replace")
    assert result.returncode == 0 and "AP ENTRY PASS" in output and "Accessed None" not in output, output[-3000:]
