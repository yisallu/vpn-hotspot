# Push scripts to the phone, install Magisk boot hook, start watcher.
param(
  [switch]$NoStart
)

$ErrorActionPreference = 'Stop'
$Serial = if ($env:ANDROID_SERIAL) { $env:ANDROID_SERIAL } else { '8026ca76' }
$Root = $PSScriptRoot
$Utf8 = New-Object System.Text.UTF8Encoding $false

function Convert-ToUnixLf([string]$Path) {
  $t = [IO.File]::ReadAllText($Path) -replace "`r`n", "`n" -replace "`r", "`n"
  [IO.File]::WriteAllText($Path, $t, $Utf8)
}

$sh = @(
  'vpn-hotspot.sh',
  'vpn-hotspot-boot.sh',
  'zzz_vpn_hotspot.sh'
)

foreach ($f in $sh) {
  $src = Join-Path $Root "scripts\$f"
  Convert-ToUnixLf $src
  & adb -s $Serial push $src "/data/local/tmp/$f"
  if ($LASTEXITCODE -ne 0) { throw "adb push failed: $f" }
}

$remote = @'
chmod 755 /data/local/tmp/vpn-hotspot.sh /data/local/tmp/vpn-hotspot-boot.sh /data/local/tmp/zzz_vpn_hotspot.sh
cp /data/local/tmp/zzz_vpn_hotspot.sh /data/adb/service.d/zzz_vpn_hotspot.sh
chmod 755 /data/adb/service.d/zzz_vpn_hotspot.sh
'@

if (-not $NoStart) {
  $remote += "`nsh /data/local/tmp/vpn-hotspot-boot.sh`n"
}

# One remote script avoids PowerShell eating su -c quotes.
$tmp = Join-Path $env:TEMP 'vpn-hotspot-install-remote.sh'
$remoteUnix = $remote -replace "`r`n", "`n" -replace "`r", "`n"
[IO.File]::WriteAllText($tmp, $remoteUnix, $Utf8)
& adb -s $Serial push $tmp /data/local/tmp/vpn-hotspot-install-remote.sh
& adb -s $Serial shell "su -c 'sh /data/local/tmp/vpn-hotspot-install-remote.sh'"
