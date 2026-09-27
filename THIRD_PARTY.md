# Native dependencies and source

The Windows x86 and x64 DLLs include the following components:

| Component | Version | License |
| --- | --- | --- |
| APCpp (randomcodegen) | 874b738610686971085c8386cef85829524315e2 + local UT99 changes | LGPL-2.1 |
| IXWebSocket | 8115594483b958c6db809dd3edb1603c3969f591 | BSD-3-Clause |
| JsonCpp | 89e2973c754a9c02a49974d839779b151e95afd6 | MIT / public domain; see license |
| mbedTLS | 3.6.4, archive supplied by APCpp | Apache-2.0 option |
| zlib | 1.4.1.1, bundled with APCpp | zlib |
| UT99 public SDK | OldUnreal 469e (x86), 469f RC5 (x64) | Epic's noncommercial Unreal retail/SDK terms |

Full license texts are in the release's `licenses` directory. UT99's Core.dll and Engine.dll are provided by
the user's game installation and are not redistributed here. No stock game assets are included.

`UT99AP-native-source-1.0.0.zip` (x86) and `UT99AP-native-source-1.0.0-x64.zip` (x64) are the corresponding source distributions. Each includes the patched
APCpp source and its dependency trees, the mbedTLS source archive, the client/bridge/build scripts,
and `relink/Bridge.obj`. You may modify/relink the LGPL component for your own use and debug those
modifications. The simplest way is to rebuild with `build-native.ps1`; it downloads the public UT SDK
if needed. Add `-Architecture x64` for the x64 build. The bridge object is also provided for relinking without recompiling the Unreal-facing
part. Use the SDK's Core.lib and Engine.lib import libraries and the libraries/flags in native/CMakeLists.txt.
Distribute the corresponding source ZIP and this notice alongside the binary release.

The local APCpp checkout adds queued packet notifications and explicit URL schemes, preserves TLS-to-ws
fallback, handles batched messages without losing later commands, exposes Sync, clears stale data-package
state at shutdown. WebSocket compression uses APCpp's existing IXWebSocket support with bundled static
zlib. The game's inventory validation remains UnrealScript.

