# Variables to provide:
# GYP_MSVS_VERSION = 2017 | 2015
# CONFIGURATION = Debug | Release
# PLATFORM = x86 | x64
# PDFium_BRANCH = master | chromium/3211 | ...
# PDFium_V8 = enabled

# Set-PSDebug -Trace 1

$GYP_MSVS_VERSION=2017
$CONFIGURATION="Release"
$PLATFORM="x64"
$PDFium_BRANCH="chromium/4060"
$PDFium_V8="enabled"

$PWD=Get-Location

# Input
$osVer=(Get-ComputerInfo).OsVersion
$WindowsSDK_DIR="C:\Program Files (x86)\Windows Kits\10\bin\$osVer.0"
$DepotTools_URL="https://storage.googleapis.com/chrome-infra/depot_tools.zip"
$DepotTools_DIR="$PWD\depot_tools"
$PDFium_URL="https://pdfium.googlesource.com/pdfium.git"
$PDFium_SOURCE_DIR="$PWD\pdfium"
$PDFium_BUILD_DIR="$PDFium_SOURCE_DIR\out"
$PDFium_PATCH_DIR="$PWD\patches"
$PDFium_CMAKE_CONFIG="$PWD\PDFiumConfig.cmake"
$PDFium_ARGS="$PWD\args\windows.args.gn"

# Output
$PDFium_STAGING_DIR="$PWD\staging"
$PDFium_INCLUDE_DIR="$PDFium_STAGING_DIR\include"
$PDFium_BIN_DIR="$PDFium_STAGING_DIR\x64\bin"
$PDFium_LIB_DIR="$PDFium_STAGING_DIR\x64\lib"
$PDFium_RES_DIR="$PDFium_STAGING_DIR\x64\res"
$PDFium_ARTIFACT_BASE="$PWD\pdfium-windows-$osVer.0"
if ($PDFium_V8 -eq "enabled") { $PDFium_ARTIFACT_BASE="$PDFium_ARTIFACT_BASE-v8" }
if ($CONFIGURATION -eq "Debug") { $PDFium_ARTIFACT_BASE="$PDFium_ARTIFACT_BASE-debug" }
$PDFium_ARTIFACT="$PDFium_ARTIFACT_BASE.zip"

# Prepare directories
mkdir $PDFium_BUILD_DIR
mkdir $PDFium_STAGING_DIR
mkdir $PDFium_BIN_DIR
mkdir $PDFium_LIB_DIR

# Download depot_tools
(curl -fsSL -o depot_tools.zip $DepotTools_URL) || exit
(7z -bd -y x depot_tools.zip -o"$DepotTools_DIR") || exit
$env:PATH="$DepotTools_DIR;$WindowsSDK_DIR;$env:PATH"
$env:DEPOT_TOOLS_WIN_TOOLCHAIN=0

# check that rc.exe is in PATH
Where-Object rc.exe || exit 1

# Clone
gclient config --unmanaged $PDFium_URL || exit 1
gclient sync || exit 1

# Checkout branch (or ignore if it doesn't exist)
Set-Location $PDFium_SOURCE_DIR
git.exe checkout $PDFium_BRANCH && gclient sync

##LEFT OFF HERE

# Install python packages
Where-Object python
$cmd = "$DepotTools_DIR\python.bat -m pip install pywin32"
Invoke-Expression $cmd || exit 1
# $DepotTools_DIR\python.bat -m pip install pywin32 || exit 1

# Patch
Set-Location $PDFium_SOURCE_DIR
Copy-Item "$PDFium_PATCH_DIR\resources.rc" . || exit 1
git.exe apply -v "$PDFium_PATCH_DIR\shared_library.patch" || exit 1
git.exe apply -v "$PDFium_PATCH_DIR\relative_includes.patch" || exit 1
if ($PDFium_V8 -eq "enabled") { git.exe apply -v "$PDFium_PATCH_DIR\v8_init.patch" || exit 1 }
git.exe -C build apply -v "$PDFium_PATCH_DIR\rc_compiler.patch" || exit 1
git.exe -C build apply -v "$PDFium_PATCH_DIR\pdfiumPrinter.patch" || exit 1

# Configure
Copy-Item $PDFium_ARGS $PDFium_BUILD_DIR\args.gn
if ($CONFIGURATION -eq "Release") { Write-Output is_debug=false >> $PDFium_BUILD_DIR\args.gn }
if ($PLATFORM -eq "x86") { Write-Output target_cpu="x86" >> $PDFium_BUILD_DIR\args.gn }
if ($PDFium_V8 -eq "enabled") { Write-Output pdf_enable_v8=true >> $PDFium_BUILD_DIR\args.gn } 
if ($PDFium_V8 -eq "enabled") { Write-Output pdf_enable_xfa=true >> $PDFium_BUILD_DIR\args.gn }

# Generate Ninja files
gn gen $PDFium_BUILD_DIR || exit 1

# Build
ninja -C $PDFium_BUILD_DIR pdfium || exit 1

# Install
Copy-Item -Force $PDFium_CMAKE_CONFIG $PDFium_STAGING_DIR || exit 1
Copy-Item -Force $PDFium_SOURCE_DIR\LICENSE $PDFium_STAGING_DIR || exit 1
xcopy /S /Y $PDFium_SOURCE_DIR\public $PDFium_INCLUDE_DIR\ || exit 1
Remove-Item $PDFium_INCLUDE_DIR\DEPS
Remove-Item $PDFium_INCLUDE_DIR\README
Remove-Item $PDFium_INCLUDE_DIR\PRESUBMIT.py
Move-Item -Force $PDFium_BUILD_DIR\pdfium.dll.lib $PDFium_LIB_DIR || exit 1
Move-Item -Force $PDFium_BUILD_DIR\pdfium.dll $PDFium_BIN_DIR || exit 1
if ($CONFIGURATION -eq "Debug") { Move-Item -Force $PDFium_BUILD_DIR\pdfium.dll.pdb $PDFium_BIN_DIR }
if ($PDFium_V8 -eq "enabled") {
    mkdir $PDFium_RES_DIR
    Move-Item -Force $PDFium_BUILD_DIR\icudtl.dat $PDFium_RES_DIR
    Move-Item -Force $PDFium_BUILD_DIR\snapshot_blob.bin $PDFium_RES_DIR
}

# Pack
Set-Location $PDFium_STAGING_DIR
7z a $PDFium_ARTIFACT *