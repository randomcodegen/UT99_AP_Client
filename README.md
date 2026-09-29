# UT99 Archipelago client

Archipelago bot matches in Unreal Tournament 99: Deathmatch, CTF, Domination, and Assault. 
Kills, objectives and pickups are locations.

## Install and play

Choose the client archive that matches your **game executable**: the standard archive is for Windows x86 (tested on 469e), the `-x64` archive is for Windows x64 (tested on 469f RC5).
Each includes its matching `UT99APNative.dll`.

1. Put `ut99.apworld` in custom_worlds and run `Generate Template Options`.
2. Put the .yaml in the `Players` folder and run `Generate` from the Launcher.
3. Copy all four files from zip `System` into UT's `System` folder.
4. Open **Mods > Archipelago**, connect, and select an unlocked arena.

Each arena has win and frag checks. 
CTF, Domination, and Assault add objective checks.
Selected pickups add checks too. 
The menu and HUD show checked / in-logic (total). 

In the UT console, use ap server commands like `!help`, `!hint`, `!hint_location` or `!remaining`.
**Tab** completes commands, item, and location names.

## Console commands

These commands work in the UT console:

| Command | What it does |
| --- | --- |
| `mutate ap allrespawns [0\|1]` | Include ordinary and already-checked pickups in respawn timers |
| `mutate ap connect` | Connect using the saved server and slot settings |
| `mutate ap disconnect` | Disconnect from Archipelago |
| `mutate ap host <address>` | Save the AP server address or URL |
| `mutate ap maps` | List seed maps with unlock and win status |
| `mutate ap minnotify [0\|1\|2]` | Set item notifications: all, useful or higher, or progression only |
| `mutate ap password <password>` | Save the AP room password |
| `mutate ap pickupboxes [0\|1]` | Show or hide pickup bounding boxes |
| `mutate ap port <number>` | Save the AP server port |
| `mutate ap progressionsound [0\|1]` | Play a sound for received progression items |
| `mutate ap respawntimers [0\|1]` | Show or hide pickup respawn countdowns |
| `mutate ap say` | Send an AP server message |
| `mutate ap skillspread [0..7]` | Shift new bots' skill randomly by +/- this value |
| `mutate ap slot <name>` | Save the AP slot name |
| `mutate ap start <map>` | Start an unlocked seed map |
| `mutate ap status` | Show connection status and wins toward the goal |
| `mutate ap timerthroughwalls [0\|1]` | Show respawn timers through walls or require line of sight |

## Build

Requires UT99, Visual Studio C++ tools, CMake, Git, Python, and `../APCpp`.
The default x86 build uses the pinned 469e SDK. Builds stay in `.build` and `dist/System`.

```powershell
python tools/catalog.py
./build-native.ps1
./build.ps1 -UTPath C:\UnrealTournament
```

For 469f RC5 x64, use an x64 game installation and the matching SDK (downloaded automatically):

```powershell
./build-native.ps1 -Architecture x64
./build.ps1 -Architecture x64 -UTPath C:\UT469f-x64
python tools/package.py --architecture x64
```

These builds stay in `.native-build-x64`, `.build-x64`, and `dist/x64/System`.
When testing an extracted patch separately, pass `-GameDataPath C:\UnrealTournament` to `build.ps1` to reuse the full game's assets.

## Test

```powershell
./build-native.ps1 -Tests
./build.ps1 -Tests
python -m pip install pytest websockets==13.1 cryptography
python -m pytest tests -q --basetemp .build/pytest
```

`APTests.u` is for tests only.
For x64 tests, add `-Architecture x64` to both build commands, pass the x64 installation to `build.ps1`, and set `UT99_BUILD_DIRECTORY=.build-x64` and `UT99_NATIVE_BUILD_DIRECTORY=.native-build-x64` before running pytest. 
The startup tests launch the game client and exit automatically.
Run them with other UT clients closed.
Run `python tools/package.py` after building to make release archives.
See `THIRD_PARTY.md` for dependencies and licenses.
