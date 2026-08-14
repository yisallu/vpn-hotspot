# PC helper: LineageOS-style VPN hotspot (fail-open)
param(
  [ValidateSet('start','stop','status','watch','hotspot-on','hotspot-off')]
  [string]$Action = 'start'
)

$ErrorActionPreference = 'Stop'
$Serial = if ($env:ANDROID_SERIAL) { $env:ANDROID_SERIAL } else { '8026ca76' }

function Invoke-Su([string]$Cmd) {
  & adb -s $Serial shell "su -c $Cmd"
}

switch ($Action) {
  'hotspot-on'  { Invoke-Su 'cmd wifi start-softap zi3 wpa2 88888888' }
  'hotspot-off' { Invoke-Su 'cmd wifi stop-softap' }
  'start'       { Invoke-Su 'sh /data/local/tmp/vpn-hotspot-boot.sh' }
  'watch'       { Invoke-Su 'sh /data/local/tmp/vpn-hotspot-boot.sh' }
  'stop'        { Invoke-Su 'sh /data/local/tmp/vpn-hotspot.sh stop' }
  'status'      { Invoke-Su 'sh /data/local/tmp/vpn-hotspot.sh status' }
}
