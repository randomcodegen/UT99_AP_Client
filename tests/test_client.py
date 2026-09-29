"""Test compiled UnrealScript in the installed UT469 runtime

First run build.ps1 -Tests"""
import asyncio
import json
import os
from pathlib import Path
import subprocess
import uuid

import websockets
import pytest

ROOT = Path(__file__).resolve().parents[1]
SYSTEM = ROOT / os.environ.get("UT99_BUILD_DIRECTORY", ".build") / "System"


def test_native_dll_load():
    result = subprocess.run([str(SYSTEM / "UCC.exe"), "APTests.APNativeSmokeCommandlet",
                             "ini=Build.ini", "-nohomedir"], cwd=SYSTEM,
                            capture_output=True, timeout=30)
    assert result.returncode == 0 and b"AP NATIVE LOAD PASS" in result.stdout, result.stdout


def test_compiled_json():
    result = subprocess.run([str(SYSTEM / "UCC.exe"), "APTests.APSelfTestCommandlet",
                             "ini=Build.ini", "-nohomedir"], cwd=SYSTEM,
                            capture_output=True, timeout=30)
    assert b"AP SELFTEST PASS" in result.stdout, result.stdout.decode(errors="replace")


@pytest.mark.parametrize("scheme,increment,limit,minnotify,burst", [
    ("", 2, 8, 0, 0), ("ws://", 2, 8, 0, 0), ("wss://", 2, 8, 0, 0),
    ("ws://", 1, 20, 0, 0), ("ws://", 3, 20, 0, 0), ("ws://", 1, 100, 0, 0),
    ("ws://", 1, 20, 1, 0), ("ws://", 1, 20, 2, 0),
    ("ws://", 1, 20, 2, 256),
])
def test_runtime_connection_gameplay_and_reconnect(scheme, increment, limit, minnotify, burst):
    asyncio.run(exercise_client(scheme, increment, limit, minnotify, burst))


async def exercise_client(scheme, increment, limit, minnotify, burst):
    connections = 0
    first_connection_connects = 0
    commands = []
    saw_checks = set()
    goal_received = asyncio.Event()
    reconnected = asyncio.Event()
    seed = "UT99-test-" + uuid.uuid4().hex
    errors = []
    resynced = asyncio.Event()
    storage = {}
    frag_sets = []
    death_link_updates = []
    death_links_sent = []
    released = False
    slot = {"schema_version": 11, "selected_maps": [0, 1], "starting_map": 0,
            "goal_required": 1, "frag_check_increment": increment, "match_frag_limit": limit,
            "bot_skill": 2, "bot_count": 1, "pickup_catalog_version": 2,
            "pickup_locations": [19996000, 19996002, 19996015, 19996020],
            "pickup_unlock_mode": 1, "weapon_logic_percentage": 25, "death_link": True}
    extra_unlocks = [19990418, 19990419, 19990420]
    scouted = set()

    async def handler(ws):
        nonlocal connections, first_connection_connects, released
        try:
            connections += 1
            assert any(type(ext).__name__ == "PerMessageDeflate"
                       for ext in getattr(ws, "protocol", ws).extensions)
            await ws.send(json.dumps([{"cmd": "RoomInfo", "seed_name": seed}]))
            connect = json.loads(await asyncio.wait_for(ws.recv(), 15))[0]
            assert connect["cmd"] == "Connect" and connect["items_handling"] == 7
            if connections == 1: first_connection_connects += 1
            assert connect["name"] == 'Tester "\\ ü'
            items = [{"item": 19990000, "player": 2, "flags": 3, "location": 19991001},
                     {"item": 19990105, "player": 2, "flags": 1},
                     {"item": 19990105, "player": 0, "flags": 1, "location": -2},
                     {"item": 19990209, "player": 2, "flags": 0}]
            items.extend({"item": item, "player": 2} for item in extra_unlocks)
            if released:
                items.extend({"item": 19990201, "player": 2} for _ in range(burst))
            if connections > 1:
                items.append({"item": 19990001, "player": 2})
            packet = json.dumps([
                {"cmd": "Connected", "team": 0, "slot": 1, "slot_data": slot,
                 "players": [{"team": 0, "slot": 2, "alias": "Friend", "name": "Friend"}],
                 "slot_info": {"2": {"game": "Unreal Tournament 99"}},
                 "checked_locations": list(saw_checks)},
                {"cmd": "DataPackage", "data": {"games": {"Unreal Tournament 99": {
                    "location_name_to_id": {"DM-Oblivion - Frag Milestone 1": 19991001},
                    "item_name_to_id": {}}}}},
                {"cmd": "ReceivedItems", "index": 0, "items": items},
                # Skip an index so the client must request full Sync
                {"cmd": "ReceivedItems", "index": 50, "items": []},
                {"cmd": "PrintJSON", "data": [{"text": "Test server chat\nwith controls"}]},
            ])
            # Fragment JSON
            await ws.send([packet[:37], packet[37:113], packet[113:]])
            if connections == 1:
                pong = await ws.ping(b"\x00\xff\x80ping")
                await asyncio.wait_for(pong, 10)
            if connections > 1:
                reconnected.set()
            async for message in ws:
                for command in json.loads(message):
                    if command["cmd"] == "Connect":
                        if connections == 1: first_connection_connects += 1
                        await ws.send(json.dumps([
                            {"cmd": "Connected", "team": 0, "slot": 1, "slot_data": slot,
                             "players": [{"team": 0, "slot": 2, "alias": "Friend", "name": "Friend"}],
                             "slot_info": {"2": {"game": "Unreal Tournament 99"}},
                             "checked_locations": list(saw_checks)},
                            {"cmd": "ReceivedItems", "index": 0, "items": items},
                        ]))
                    if command["cmd"] == "Sync":
                        await ws.send(json.dumps([
                            {"cmd": "ReceivedItems", "index": 0, "items": items},
                            {"cmd": "ReceivedItems", "index": 1, "items": items[1:]},
                        ]))
                        resynced.set()
                    if command["cmd"] == "ConnectUpdate":
                        death_link_updates.append(command.get("tags", []))
                    if command["cmd"] == "Bounce" and "DeathLink" in command.get("tags", []):
                        death_links_sent.append(command)
                    if command["cmd"] == "Get":
                        values = {}
                        for key in command["keys"]:
                            values[key] = storage.setdefault(
                            key, 3 if key.endswith("UT99Frags1") else
                                4 if key.endswith("UT99Frags2") else 0)
                        await ws.send(json.dumps([{"cmd": "Retrieved", "keys": values}]))
                    if command["cmd"] == "Set":
                        key = command["key"]
                        if "UT99Frags" not in key:
                            continue
                        assert command.get("want_reply") is True
                        assert command.get("default") == 0
                        assert command["operations"] and all(
                            operation["operation"] == "max" and isinstance(operation["value"], int)
                            for operation in command["operations"])
                        original = storage.get(key, command["default"])
                        value = original
                        for operation in command["operations"]:
                            value = max(value, operation["value"])
                        storage[key] = value
                        frag_sets.append((key, value))
                        await ws.send(json.dumps([{
                            "cmd": "SetReply", "key": key,
                            "original_value": original, "value": value,
                        }]))
                    if command["cmd"] == "LocationChecks":
                        saw_checks.update(command["locations"])
                    if command["cmd"] == "Say":
                        commands.append(command["text"])
                    if command["cmd"] == "LocationScouts":
                        assert command.get("create_as_hint", 0) == 0
                        scouted.update(command["locations"])
                        await ws.send(json.dumps([{"cmd": "LocationInfo", "locations": [
                            {"location": location, "item": 19990201, "player": 1,
                             "flags": (0, 2, 1)[(location - 19996000) % 3]}
                            for location in command["locations"]]}]))
                    if command["cmd"] == "StatusUpdate":
                        assert command["status"] == 30
                        goal_received.set()
                if connections == 1 and goal_received.is_set():
                    released = True
                    if burst:
                        await ws.send(json.dumps([{"cmd": "ReceivedItems", "index": len(items),
                                                  "items": [{"item": 19990201, "player": 2}
                                                            for _ in range(burst)]}]))
                        await asyncio.sleep(3)
                    await ws.close()
                    return
        except websockets.ConnectionClosed:
            pass
        except Exception as exc:
            errors.append(exc)

    async with websockets.serve(handler, "127.0.0.1", 0, compression="deflate") as server:
        port = server.sockets[0].getsockname()[1]
        (SYSTEM / "UT99AP.ini").write_text(
            f'[UT99AP.APMutator]\nHost={scheme}127.0.0.1:{port}/\nAPPort=1\n'
            f'MinNotify={minnotify}\n'
            'SlotName=Tester "\\ ü\nPassword=\nbAutoConnect=True\n', encoding="utf-8-sig")
        (SYSTEM / "UT99APProgress.ini").write_text(
            f"[UT99AP.APProgress]\nIdentity={seed}:0:1\n")
        config = (SYSTEM / "Build.ini").read_text()
        config += "\n[Engine.GameEngine]\nCacheSizeMegs=64\n"
        config = config.replace("[Engine.Engine]", "[Engine.Engine]\nNetworkDevice=IpDrv.TcpNetDriver")
        (SYSTEM / "Test.ini").write_text(config)
        log = SYSTEM / "integration-output.log"
        with log.open("wb") as output:
            process = subprocess.Popen([
                str(SYSTEM / "UCC.exe"), "Engine.ServerCommandlet",
                f"DM-Oblivion?Game=APTests.APTestGame?APStage=1?APBurst={burst}?Difficulty=2?Port=0",
                "ini=Test.ini", "-nohomedir", "-lanplay"], cwd=SYSTEM, stdout=output,
                stderr=subprocess.STDOUT, creationflags=subprocess.CREATE_NO_WINDOW)
            try:
                await asyncio.wait_for(asyncio.to_thread(process.wait), 60)
            finally:
                if process.poll() is None:
                    process.terminate()
                    process.wait(timeout=10)
        text = log.read_text(errors="replace")
        assert not errors, (errors, text[-6000:])
        assert commands == ["!help"], text[-6000:]
        assert "AP INTEGRATION PASS" in text, (scouted, resynced.is_set(), text[-9000:])
        assert "AP: Test server chat with controls" in text
        assert text.count("] Received ") == 6 + (minnotify == 0), text[-9000:]
        assert ("Received +2 Flak Shells from Friend" in text) == (minnotify == 0)
        assert "Received Flak Cannon Unlock from Friend" in text
        assert "Received Shock Rifle Unlock from Server" not in text
        assert text.count("Received DM-Oblivion Unlock from Friend") == 1
        assert "Received DM-Oblivion Unlock from Friend at DM-Oblivion - Frag Milestone 1" in text
        assert text.count("Received DM-Stalwart Unlock from Friend") == 1
        assert "AP: Checked " not in text
        assert not any(marker in text for marker in ("Accessed None", "Runaway", "AP INTEGRATION FAIL")), text[-9000:]
        assert goal_received.is_set() and reconnected.is_set() and resynced.is_set(), text[-6000:]
        assert first_connection_connects == 2, text[-6000:]
        assert death_link_updates and all("DeathLink" in tags for tags in death_link_updates), text[-6000:]
        assert death_links_sent, text[-6000:]
        assert any(key.endswith("UT99Frags0") and value == limit for key, value in frag_sets)
        assert sum("UT99Frags" in key for key in storage) == 82
        assert any(key.endswith("UT99Frags1") and value == 3 for key, value in storage.items())
        assert not any(key.endswith("UT99Frags1") for key, value in frag_sets)
        assert not any(key.endswith("UT99Frags2") for key, value in frag_sets)
        expected = {19991000} | {
            19991000 + step
            for step in range(1, limit // increment + 1)
        }
        pickup_checks = {19996000, 19996002}
        expected.update(pickup_checks)
        assert scouted == pickup_checks
        assert saw_checks == expected
        progress_ini = (SYSTEM / "UT99APProgress.ini").read_text()
        assert "Checked[" not in progress_ini and len(progress_ini) < 4096
