param([string]$UTPath = 'C:\UnrealTournament', [switch]$Tests, [string]$BuildDirectory,
    [ValidateSet('x86', 'x64')][string]$Architecture = 'x86', [string]$GameDataPath)
$ErrorActionPreference = 'Stop'
$nativeBuild = '.native-build'
$distSystem = Join-Path $PSScriptRoot 'dist/System'
if ($Architecture -eq 'x64') {
    $nativeBuild = '.native-build-x64'
    $distSystem = Join-Path $PSScriptRoot 'dist/x64/System'
    if (!$BuildDirectory) { $BuildDirectory = '.build-x64' }
}
if (!$BuildDirectory) { $BuildDirectory = '.build' }
if (!$GameDataPath) { $GameDataPath = $UTPath }
if (!(Test-Path "$PSScriptRoot/$nativeBuild/Release/UT99APNative.dll")) {
    throw "Run ./build-native.ps1 -Architecture $Architecture first."
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
Get-ChildItem -LiteralPath "$GameDataPath\System" -Filter '*.u' |
    Where-Object { $_.Name -notin @('UT99AP.u', 'UT99APNative.u', 'APTests.u') -and
        !(Test-Path (Join-Path $systemDir $_.Name)) } |
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
Copy-Item "$PSScriptRoot/$nativeBuild/Release/UT99APNative.dll" $systemDir
$gameRoot = (Resolve-Path -LiteralPath $UTPath).Path.Replace('\', '/')
$dataRoot = (Resolve-Path -LiteralPath $GameDataPath).Path.Replace('\', '/')
@"
[Core.System]
Paths=../System/*.u
Paths=$gameRoot/Maps/*.unr
Paths=$gameRoot/Textures/*.utx
Paths=$gameRoot/Sounds/*.uax
Paths=$gameRoot/Music/*.umx
Paths=$dataRoot/Maps/*.unr
Paths=$dataRoot/Textures/*.utx
Paths=$dataRoot/Sounds/*.uax
Paths=$dataRoot/Music/*.umx
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
    Copy-Item "$UTPath/System/UnrealTournament.exe" $systemDir
    # The client checks these two paths before reading Core.System.Paths.
    New-Item -ItemType Directory -Force "$buildRoot/Maps", "$buildRoot/Textures", "$buildRoot/Help" | Out-Null
    Copy-Item "$GameDataPath/Maps/Entry.unr" "$buildRoot/Maps"
    Copy-Item "$GameDataPath/Textures/Palettes.utx" "$buildRoot/Textures"
    Copy-Item "$GameDataPath/Help/Logo.bmp" "$buildRoot/Help"
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
    (1..16 | ForEach-Object { 'Y' }) | & .\UCC.exe Editor.MakeCommandlet ini=Build.ini -nohomedir
    if ($LASTEXITCODE -ne 0 -or !(Test-Path -LiteralPath $package)) {
        throw "UnrealScript compilation failed; see $systemDir/UCC.log"
    }
} finally { Pop-Location }
New-Item -ItemType Directory -Force $distSystem | Out-Null
Copy-Item $package $distSystem
Copy-Item $nativePackage $distSystem
Copy-Item "$systemDir\UT99APNative.dll" $distSystem
Copy-Item "$PSScriptRoot\System\UT99AP.int" $distSystem
Write-Output "Built $distSystem/UT99AP.u"
