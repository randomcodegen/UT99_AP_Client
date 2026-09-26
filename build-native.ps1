param([switch]$Tests, [string]$APCppPath)
$ErrorActionPreference = 'Stop'
$deps = Join-Path $PSScriptRoot '.deps'
$sdkArchive = Join-Path $deps 'sdk.zip'
$sdk = Join-Path $deps 'sdk'
$localAPCpp = Join-Path $PSScriptRoot '../APCpp'
if (!$APCppPath) {
    $APCppPath = if (Test-Path (Join-Path $localAPCpp 'Archipelago.cpp')) { $localAPCpp } else { Join-Path $deps 'APCpp' }
}
$apcpp = (Resolve-Path -LiteralPath $APCppPath -ErrorAction Stop).Path
if (!(Test-Path (Join-Path $apcpp 'Archipelago.cpp'))) { throw "APCpp source missing at $apcpp" }
New-Item -ItemType Directory -Force $deps | Out-Null
if (!(Test-Path "$sdk/Core/Inc/Core.h")) {
    if (!(Test-Path $sdkArchive)) {
        Invoke-WebRequest 'https://github.com/OldUnreal/UnrealTournamentPatches/releases/download/v469e/OldUnreal-UTPatch469e-SDK.zip' -OutFile $sdkArchive
    }
    if ((Get-FileHash $sdkArchive -Algorithm SHA256).Hash -ne 'B213789A18D736BEACDF8BC2740BCC6E031789B806823B9F7EB3A75B2DACEDCC') {
        throw 'Unexpected UT469e SDK archive hash'
    }
    Expand-Archive $sdkArchive $sdk -Force
}
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
$vs = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if (!$vs) { throw 'Install Visual Studio C++ desktop build tools and CMake tools first.' }
$cmake = Join-Path $vs 'Common7/IDE/CommonExtensions/Microsoft/CMake/CMake/bin/cmake.exe'
if (!(Test-Path $cmake)) { $cmake = (Get-Command cmake -ErrorAction Stop).Source }
$testOption = if ($Tests) { 'ON' } else { 'OFF' }
& $cmake -S "$PSScriptRoot/native" -B "$PSScriptRoot/.native-build" -A Win32 "-DUT99AP_BUILD_TESTS=$testOption" "-DAPCPP=$apcpp"
if ($LASTEXITCODE -ne 0) { throw 'Native CMake configuration failed' }
& $cmake --build "$PSScriptRoot/.native-build" --config Release --parallel
if ($LASTEXITCODE -ne 0) { throw 'Native build failed' }
