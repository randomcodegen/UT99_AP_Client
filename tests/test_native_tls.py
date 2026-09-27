"""Test shipping Session objects with a test-only trust root."""
import asyncio
import json
import os
from datetime import datetime, timedelta, timezone
from pathlib import Path
import ssl
import subprocess

from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.x509.oid import NameOID
import pytest
import websockets

ROOT = Path(__file__).resolve().parents[1]
PROBE = ROOT / os.environ.get("UT99_NATIVE_BUILD_DIRECTORY", ".native-build") / "Release/NativeSessionProbe.exe"


def certificate(directory):
    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    name = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, "UT99 AP local test")])
    now = datetime.now(timezone.utc)
    cert = (x509.CertificateBuilder().subject_name(name).issuer_name(name)
            .public_key(key.public_key()).serial_number(x509.random_serial_number())
            .not_valid_before(now - timedelta(days=1)).not_valid_after(now + timedelta(days=2))
            .add_extension(x509.BasicConstraints(ca=True, path_length=None), critical=True)
            .add_extension(x509.SubjectAlternativeName([x509.DNSName("localhost")]), critical=False)
            .sign(key, hashes.SHA256()))
    pem = directory / "certificate.pem"
    private = directory / "key.pem"
    pem.write_bytes(cert.public_bytes(serialization.Encoding.PEM))
    private.write_bytes(key.private_bytes(serialization.Encoding.PEM,
                                         serialization.PrivateFormat.PKCS8,
                                         serialization.NoEncryption()))
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.load_cert_chain(pem, private)
    return context, pem


@pytest.mark.parametrize("mode", ["tls", "untrusted", "wrong_hostname", "ws", "ws_keepalive", "fallback", "bare_fallback"])
def test_native_connection(tmp_path, mode):
    asyncio.run(exercise(tmp_path, mode))


async def exercise(directory, mode):
    tls, pem = certificate(directory)
    secure = mode in {"tls", "untrusted", "wrong_hostname"}
    checks = set()
    goal = False
    connections = 0
    connect_packets = 0
    compressed_connections = 0
    commands = []

    async def handler(ws):
        nonlocal connections, connect_packets, compressed_connections, goal
        connections += 1
        compressed_connections += any(type(ext).__name__ == "PerMessageDeflate"
                                      for ext in getattr(ws, "protocol", ws).extensions)
        try:
            await ws.send('[{"cmd":"RoomInfo","seed_name":"native-tls-test"}]')
            async for message in ws:
                import json
                for packet in json.loads(message):
                    if packet["cmd"] == "Connect":
                        connect_packets += 1
                        assert packet["name"] == "NativeTLS"
                        await ws.send('[{"cmd":"Connected","slot":1,"team":0,"slot_data":{},'
                                      '"players":[{"slot":1,"team":0,"name":"NativeTLS","alias":"NativeTLS"}],'
                                      '"checked_locations":[]},{"cmd":"ReceivedItems","index":0,"items":[]}]')
                        await ws.send(json.dumps([{"cmd": "PrintJSON", "data": [
                            {"text": "Hint: "}, {"text": "Unlock", "type": "item_name", "flags": 3},
                            {"text": " at "}, {"text": "DM-Pressure - Win", "type": "location_name"},
                            {"text": " for "}, {"text": "1", "type": "player_id"},
                            {"text": " from "}, {"text": "Friend", "type": "player_name"},
                        ]}]))
                    elif packet["cmd"] == "LocationChecks":
                        checks.update(packet["locations"])
                    elif packet["cmd"] == "Say":
                        commands.append(packet["text"])
                    elif packet["cmd"] == "StatusUpdate":
                        assert packet["status"] == 30
                        goal = True
                        await ws.send('[{"cmd":"RoomUpdate","checked_locations":[19991001]}]')
        except websockets.ConnectionClosed:
            pass

    async with websockets.serve(handler, "127.0.0.1", 0, ssl=tls if secure else None,
                                compression="deflate") as server:
        port = server.sockets[0].getsockname()[1]
        scheme = "ws://" if mode in {"ws", "ws_keepalive"} else "wss://"
        if mode == "bare_fallback": scheme = ""
        host = "127.0.0.1" if mode == "wrong_hostname" else "localhost"
        ca = "SYSTEM" if mode == "untrusted" else str(pem)
        expected = "reject" if mode in {"untrusted", "wrong_hostname"} else "TLS" if secure else "ws"
        args = [str(PROBE), f"{scheme}{host}:{port}", ca, expected]
        if mode == "ws_keepalive": args.append("reattach")
        process = await asyncio.create_subprocess_exec(
            *args,
            cwd=directory, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            creationflags=subprocess.CREATE_NO_WINDOW)
        try:
            output, _ = await asyncio.wait_for(process.communicate(), 25)
        finally:
            if process.returncode is None:
                process.kill()
                await process.wait()
        text = output.decode(errors="replace")
        assert process.returncode == 0 and "NATIVE SESSION PASS" in text, text
        if expected == "reject":
            assert connections == 0 and not checks and not goal
            assert not commands
        else:
            assert compressed_connections == connections and connections >= 1, (
                compressed_connections, connections, connect_packets, text[-4000:])
            if mode not in {"fallback", "bare_fallback"}:
                assert connections == 1
            assert connect_packets == (2 if mode == "ws_keepalive" else 1)
            assert checks == {19991001} and goal
            assert commands == ["!help", '!hint Shock Rifle "Unlock" \\ ü',
                                "!hint_location DM-Oblivion - Pickup MiniAmmo0"]
            packets = [packet for line in text.splitlines() if line.startswith('[{')
                       for packet in json.loads(line)]
            parts = next(p["parts"] for p in packets if p["cmd"] == "NativeChat")
            assert [p["kind"] for p in parts] == [0, 2, 0, 1, 0, 3, 0, 3]
            assert parts[1]["flags"] == 3 and parts[3]["text"] == "DM-Pressure - Win"
            assert parts[5]["self"] and parts[5]["text"] == "NativeTLS"
            assert not parts[7]["self"] and parts[7]["text"] == "Friend"
        if mode in {"fallback", "bare_fallback"}:
            assert "NativeFallback" in text
        if mode == "ws":
            assert "NativeFallback" not in text and "NativeDisconnected" not in text
