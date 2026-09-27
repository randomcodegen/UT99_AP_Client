"""Run the client menu and offline Practice Match startup, then exit."""
from pathlib import Path
import os
import subprocess

import pytest


SYSTEM = Path(__file__).resolve().parents[1] / os.environ.get("UT99_BUILD_DIRECTORY", ".build") / "System"


@pytest.mark.parametrize("map_name,game", [
    ("CityIntro", "Botpack.UTIntro"),
    ("DM-Agony", "Botpack.DeathMatchPlus"),
    ("DM-Agony", "UT99AP.APDeathMatch"),
])
def test_offline_menu_startup(map_name, game):
    if not (SYSTEM / "UnrealTournament.exe").exists():
        pytest.skip("Copy the matching UnrealTournament.exe into the build's System folder")
    config = (SYSTEM / "Build.ini").read_text().replace(
        "Console=Engine.Console", "Console=APTests.APStartupConsole")
    config += """
[FirstRun]
FirstRun=469
[URL]
Class=Botpack.TMale1
[UWindow.WindowConsole]
RootWindow=UMenu.UMenuRootWindow
[UWindow.UWindowRootWindow]
LookAndFeelClass=UMenu.UMenuBlueLookAndFeel
[Engine.Engine]
ViewportManager=WinDrv.WindowsClient
Render=Render.Render
Input=Engine.Input
Canvas=Engine.Canvas
GameRenderDevice=SoftDrv.SoftwareRenderDevice
WindowedRenderDevice=SoftDrv.SoftwareRenderDevice
[WinDrv.WindowsClient]
StartupFullscreen=False
WindowedViewportX=640
WindowedViewportY=480
[Engine.GameEngine]
UseSound=False
"""
    (SYSTEM / "StartupTest.ini").write_text(config)
    (SYSTEM / "UT99AP.ini").write_text("[UT99AP.APMutator]\nbAutoConnect=False\nSlotName=\n")
    startup = subprocess.STARTUPINFO()
    startup.dwFlags |= subprocess.STARTF_USESHOWWINDOW
    startup.wShowWindow = 0
    result = subprocess.run([
        str(SYSTEM / "UnrealTournament.exe"), f"{map_name}?Game={game}?MinPlayers=0",
        "ini=StartupTest.ini", "userini=StartupUser.ini", "log=StartupTest.log",
        "-nohomedir", "-nosound", "-windowed", "-unattended",
    ], cwd=SYSTEM, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        timeout=30, startupinfo=startup)
    output = (SYSTEM / "StartupTest.log").read_text(errors="replace")
    assert result.returncode == 0 and f"AP STARTUP PASS: {game}" in output, output[-5000:]
    assert "AP STARTUP FAIL" not in output and "Accessed None" not in output, output[-5000:]
