import asyncio
import json
import os
from pathlib import Path
import subprocess
import uuid

import websockets


SYSTEM = Path(__file__).resolve().parents[1] / os.environ.get("UT99_BUILD_DIRECTORY", ".build") / "System"


def test_map_travel_keeps_connection():
    asyncio.run(_exercise())


async def _exercise():
    connections = 0
    connects = 0
    checks = set()
    storage = {}
    errors = []
    seed = "UT99-travel-" + uuid.uuid4().hex
    slot = {"schema_version": 11, "selected_maps": [0, 1], "starting_map": 0,
            "goal_required": 1, "pickup_catalog_version": 2, "pickup_locations": [],
            "pickup_unlock_mode": 1, "weapon_logic_percentage": 25,
            "frag_check_increment": 1, "match_frag_limit": 20, "bot_skill": 2, "bot_count": 1}
    items = [{"item": 19990000, "player": 1}, {"item": 19990105, "player": 1},
             {"item": 19990209, "player": 1}]

    async def handler(ws):
        nonlocal connections, connects
        connections += 1
        try:
            await ws.send(json.dumps([{"cmd": "RoomInfo", "seed_name": seed}]))
            async for message in ws:
                for packet in json.loads(message):
                    cmd = packet["cmd"]
                    if cmd == "Connect":
                        connects += 1
                        await ws.send(json.dumps([
                            {"cmd": "Connected", "team": 0, "slot": 1, "slot_data": slot,
                             "players": [{"team": 0, "slot": 1, "name": "Travel", "alias": "Travel"}],
                             "checked_locations": sorted(checks)},
                            {"cmd": "ReceivedItems", "index": 0, "items": items},
                        ]))
                    elif cmd == "Sync":
                        await ws.send(json.dumps([{"cmd": "ReceivedItems", "index": 0, "items": items}]))
                    elif cmd == "Get":
                        await ws.send(json.dumps([{"cmd": "Retrieved", "keys": {
                            key: storage.get(key, 0) for key in packet["keys"]}}]))
                    elif cmd == "Set":
                        key = packet["key"]
                        original = storage.get(key, packet.get("default", 0))
                        value = original
                        for operation in packet["operations"]:
                            if operation["operation"] == "max": value = max(value, operation["value"])
                            elif operation["operation"] == "replace": value = operation["value"]
                        storage[key] = value
                        if packet.get("want_reply"):
                            await ws.send(json.dumps([{"cmd": "SetReply", "key": key,
                                                       "original_value": original, "value": value}]))
                    elif cmd == "LocationChecks":
                        new = set(packet["locations"]) - checks
                        checks.update(new)
                        await ws.send(json.dumps([{"cmd": "RoomUpdate", "checked_locations": sorted(checks)}]))
                        if 19991001 in new:
                            items.append({"item": 19990001, "player": 1})
                            await ws.send(json.dumps([{"cmd": "ReceivedItems", "index": 3,
                                                       "items": items[3:]}]))
        except websockets.ConnectionClosed:
            pass
        except Exception as exc:
            errors.append(exc)

    async with websockets.serve(handler, "127.0.0.1", 0, compression="deflate") as server:
        port = server.sockets[0].getsockname()[1]
        (SYSTEM / "UT99AP.ini").write_text(
            f"[UT99AP.APMutator]\nHost=ws://127.0.0.1\nAPPort={port}\n"
            "SlotName=Travel\nPassword=\nbAutoConnect=True\n")
        (SYSTEM / "UT99APProgress.ini").write_text(
            f"[UT99AP.APProgress]\nIdentity={seed}:0:1\n")
        (SYSTEM / "UT99APTravelTest.ini").write_text(
            "[APTests.APTravelDriver]\nVisitCount=0\n")
        config = (SYSTEM / "Build.ini").read_text()
        config = config.replace("[Engine.Engine]", "[Engine.Engine]\nNetworkDevice=IpDrv.TcpNetDriver")
        (SYSTEM / "Travel.ini").write_text(config + "\n[Engine.GameEngine]\nCacheSizeMegs=64\n")
        log = SYSTEM / "travel-output.log"
        with log.open("wb") as output:
            process = subprocess.Popen([
                str(SYSTEM / "UCC.exe"), "Engine.ServerCommandlet",
                "DM-Oblivion?Game=APTests.APTravelGame?APStage=1?Port=0",
                "ini=Travel.ini", "-nohomedir", "-lanplay"], cwd=SYSTEM,
                stdout=output, stderr=subprocess.STDOUT, creationflags=subprocess.CREATE_NO_WINDOW)
            try:
                await asyncio.wait_for(asyncio.to_thread(process.wait), 50)
            finally:
                if process.poll() is None:
                    process.terminate()
                    process.wait(timeout=10)
        text = log.read_text(errors="replace")
        assert not errors, (errors, text[-5000:])
        assert "AP TRAVEL PASS" in text, text[-6000:]
        assert "AP TRAVEL FAIL" not in text and "Accessed None" not in text, text[-6000:]
        assert connections == 1 and connects == 2, (connections, connects, text[-3000:])
        assert checks == {19991001, 19991002}, checks
