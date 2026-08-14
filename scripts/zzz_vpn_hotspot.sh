#!/system/bin/sh
# Magisk service.d: return immediately. Real work waits for boot.
# Same pattern as block_meituan_volume.sh — never loop in the launcher.
(
  until [ "$(getprop sys.boot_completed)" = "1" ]; do
    sleep 5
  done
  sleep 20
  exec /system/bin/sh /data/local/tmp/vpn-hotspot.sh watch
) >>/data/local/tmp/vpn-hotspot.log 2>&1 &
exit 0
