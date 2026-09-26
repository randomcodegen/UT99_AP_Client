"""set AP_SERVER_SEED to a two-slot demo ZIP"""
import asyncio
from functools import partial
import os
from pathlib import Path
import subprocess
import sys
from copy import deepcopy

import pytest
import websockets

ROOT = Path(__file__).resolve().parents[1]
AP_ROOT = ROOT.parent / "Archipelago_ut99"
SYSTEM = ROOT / os.environ.get("UT99_BUILD_DIRECTORY", ".build") / "System"


@pytest.mark.skipif(not os.environ.get("AP_SERVER_SEED"), reason="Set AP_SERVER_SEED to run against real MultiServer")
@pytest.mark.parametrize("two_player,minnotify", [(False, 0), (True, 0), (True, 2)])
def test_real_archipelago_server(two_player, minnotify):
    sys.path.insert(0, str(AP_ROOT))
    os.environ["AP_TEST_WORLDS"] = "ut99"
    os.environ["SKIP_REQUIREMENTS_UPDATE"] = "1"
    from MultiServer import Context, server as ap_server
    from worlds.ut99.catalog import MAPS, LOCATION_BASE, PICKUPS, PICKUP_BASE, ITEM_NAME_TO_ID

    async def run():
        import worlds
        original_package = deepcopy(worlds.network_data_package)
        try:
            ctx = Context("127.0.0.1", 0, "", "", 1, 10, False)
        finally:
            worlds.network_data_package = original_package
        ctx.load(os.environ["AP_SERVER_SEED"])
        assert ctx.slot_data[1]["schema_version"] == 11, "Generate a new schema-11 seed"
        start = ctx.slot_data[1]["starting_map"]
        expected = LOCATION_BASE + start * 101 + 1
        if two_player:
            # Force a real outgoing item message
            ctx.locations[1][expected] = (ITEM_NAME_TO_ID["Shock Rifle Unlock"], 2, 2)
        async with websockets.serve(partial(ap_server, ctx=ctx), "127.0.0.1", 0) as server:
            port = server.sockets[0].getsockname()[1]
            (SYSTEM / "UT99AP.ini").write_text(
                f"[UT99AP.APMutator]\nHost=127.0.0.1\nAPPort={port}\n"
                f"MinNotify={minnotify}\n"
                f"SlotName={ctx.player_names[0, 1]}\nPassword=\nbAutoConnect=True\n")
            (SYSTEM / "UT99APProgress.ini").write_text("[UT99AP.APProgress]\n")
            config = (SYSTEM / "Build.ini").read_text().replace(
                "[Engine.Engine]", "[Engine.Engine]\nNetworkDevice=IpDrv.TcpNetDriver")
            (SYSTEM / "RealServer.ini").write_text(config)
            log = SYSTEM / "real-server-output.log"
            with log.open("wb") as output:
                process = subprocess.Popen([
                    str(SYSTEM / "UCC.exe"), "Engine.ServerCommandlet",
                    f"{MAPS[start]}?Game=APTests.APProbeGame?APStage=1?Port=0",
                    "ini=RealServer.ini", "-nohomedir", "-lanplay"], cwd=SYSTEM,
                    stdout=output, stderr=subprocess.STDOUT, creationflags=subprocess.CREATE_NO_WINDOW)
                try:
                    await asyncio.wait_for(asyncio.to_thread(process.wait), 35)
                finally:
                    if process.poll() is None:
                        process.terminate()
                        process.wait(timeout=10)
            text = log.read_text(errors="replace")
            assert "AP REAL SERVER PASS" in text, text[-6000:]
            assert "AP: !hint_location [location]" in text, text[-6000:]
            assert expected in ctx.location_checks[0, 1]
            assert any(key.endswith(f"UT99Frags{start}") and value >= ctx.slot_data[1]["frag_check_increment"]
                       for key, value in ctx.stored_data.items())
            assert "AP: Received " in text
            assert " from Server" in text
            if two_player:
                assert ("AP: Shock Rifle Unlock was sent to UTPlayer2" in text) == (minnotify < 2), text[-6000:]
            if ctx.slot_data[1]["schema_version"] >= 3:
                checked_pickups = [i for i, p in enumerate(PICKUPS)
                                   if p["map"] == start and PICKUP_BASE + i in ctx.location_checks[0, 1]]
                assert len(checked_pickups) == 1
                pickup = checked_pickups[0]
                flags = ctx.locations[1][PICKUP_BASE + pickup][2]
                assert f"AP REAL PICKUP {pickup} FLAGS {flags}" in text
            assert "Accessed None" not in text, text[-6000:]

    asyncio.run(run())
