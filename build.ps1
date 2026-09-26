param([string]$UTPath = 'C:\UnrealTournament', [switch]$Tests, [string]$BuildDirectory = '.build')
$ErrorActionPreference = 'Stop'
if (!(Test-Path "$PSScriptRoot/.native-build/Release/UT99APNative.dll")) {
    throw 'Run ./build-native.ps1 first.'
}
$buildRoot = Join-Path $PSScriptRoot $BuildDirectory
$systemDir = Join-Path $buildRoot 'System'
New-Item -ItemType Directory -Force $systemDir | Out-Null
# Build isolated.
Copy-Item "$UTPath\System\*.dll" $systemDir
Copy-Item "$UTPath\System\UCC.exe" $systemDir
Get-ChildItem -LiteralPath "$UTPath\System" -Filter '*.u' |
    Where-Object { $_.Name -notin @('UT99AP.u', 'UT99APNative.u', 'APTests.u') } |
    Copy-Item -Destination $systemDir
Copy-Item "$UTPath\System\Default.ini" $systemDir
Copy-Item "$UTPath\System\DefUser.ini" $systemDir
if (Test-Path "$UTPath\SystemLocalized\int") {
    Copy-Item "$UTPath\SystemLocalized\int\*.int" $systemDir
}
# Remove stale sources
foreach ($sourceName in @('UT99AP', 'UT99APNative', 'APTests')) {
    $generated = Join-Path $buildRoot "$sourceName/Classes"
    if (Test-Path -LiteralPath $generated) {
        Get-ChildItem -LiteralPath $generated -Filter '*.uc' | Remove-Item
    }
}
Copy-Item "$PSScriptRoot\UT99AP" $buildRoot -Recurse -Force
Copy-Item "$PSScriptRoot\UT99APNative" $buildRoot -Recurse -Force
Copy-Item "$PSScriptRoot\.native-build\Release\UT99APNative.dll" $systemDir
$gameRoot = (Resolve-Path -LiteralPath $UTPath).Path.Replace('\', '/')
@"
[Core.System]
Paths=../System/*.u
Paths=$gameRoot/Maps/*.unr
Paths=$gameRoot/Textures/*.utx
Paths=$gameRoot/Sounds/*.uax
Paths=$gameRoot/Music/*.umx
[Engine.Engine]
Console=Engine.Console
GameEngine=Engine.GameEngine
EditorEngine=Editor.EditorEngine
DefaultGame=Botpack.DeathMatchPlus
DefaultServerGame=Botpack.DeathMatchPlus
Language=int
[Editor.EditorEngine]
EditPackages=Core
EditPackages=Engine
EditPackages=IpDrv
EditPackages=UWindow
EditPackages=UnrealShare
EditPackages=UnrealI
EditPackages=UMenu
EditPackages=Botpack
EditPackages=UTMenu
EditPackages=UT99APNative
EditPackages=UT99AP
"@ | Set-Content "$systemDir\Build.ini" -Encoding ascii
if ($Tests) {
    Copy-Item "$PSScriptRoot\APTests" $buildRoot -Recurse -Force
    Add-Content "$systemDir\Build.ini" 'EditPackages=APTests'
    $testPackage = Join-Path $systemDir 'APTests.u'
    if (Test-Path -LiteralPath $testPackage) { Remove-Item -LiteralPath $testPackage }
}
$package = Join-Path $systemDir 'UT99AP.u'
$nativePackage = Join-Path $systemDir 'UT99APNative.u'
if (Test-Path -LiteralPath $nativePackage) { Remove-Item -LiteralPath $nativePackage }
if (Test-Path -LiteralPath $package) { Remove-Item -LiteralPath $package }
Push-Location $systemDir
try {
    # Target 469e
    (1..16 | ForEach-Object { 'Y' }) | & .\UCC.exe Editor.MakeCommandlet ini=Build.ini -nohomedir
    if ($LASTEXITCODE -ne 0 -or !(Test-Path -LiteralPath $package)) {
        throw "UnrealScript compilation failed; see $systemDir/UCC.log"
    }
} finally { Pop-Location }
New-Item -ItemType Directory -Force "$PSScriptRoot\dist\System" | Out-Null
Copy-Item $package "$PSScriptRoot\dist\System"
Copy-Item $nativePackage "$PSScriptRoot\dist\System"
Copy-Item "$systemDir\UT99APNative.dll" "$PSScriptRoot\dist\System"
Copy-Item "$PSScriptRoot\System\UT99AP.int" "$PSScriptRoot\dist\System"
Write-Output "Built $PSScriptRoot\dist\System\UT99AP.u"
