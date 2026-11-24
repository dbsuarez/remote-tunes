# Builds the release APKs (smaller and faster than debug), one per CPU type.
#
#   powershell -File tool\build_release.ps1
#
# Uses docs\jamendo.json (git-ignored) if it exists, so the Online tab has your
# Jamendo client ID built in. Without android\key.properties the APK is signed
# with the debug key, so it installs over a debug build and keeps its data.
$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..')
$defines = @()
if (Test-Path 'docs\jamendo.json') { $defines += '--dart-define-from-file=docs\jamendo.json' }
fvm flutter build apk --release --split-per-abi @defines
Get-ChildItem build\app\outputs\flutter-apk\*-release.apk |
  ForEach-Object { '{0}  {1:N1} MB' -f $_.Name, ($_.Length / 1MB) }
Write-Host ''
Write-Host 'Install on a phone:  adb install -r build\app\outputs\flutter-apk\app-arm64-v8a-release.apk'
