# Copies the app's signing key (as text) to the clipboard, ready to paste into
# the GitHub secret RELEASE_KEYSTORE_BASE64 (repo > Settings > Secrets and
# variables > Actions > New repository secret).
#
#   powershell -File tool\export_signing_key.ps1
#
# This is the key your phones' current RemoteTunes was signed with (Flutter's
# debug key on this PC), so releases built on GitHub install OVER it and keep
# your data. Keep the key private: anyone with it can make updates your phones
# accept. Back it up too: lose it and updates need an uninstall first.
$ErrorActionPreference = 'Stop'
$key = Join-Path $env:USERPROFILE '.android\debug.keystore'
if (-not (Test-Path $key)) { throw "No key found at $key" }
$b64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($key))
Set-Clipboard -Value $b64
Write-Host "Copied ($($b64.Length) characters). Paste it as the value of RELEASE_KEYSTORE_BASE64."
Write-Host "Back up this file somewhere safe too: $key"
