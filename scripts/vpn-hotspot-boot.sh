#!/system/bin/sh
# Start the fail-open watcher. Does not force SoftAP on.

# Stop any previous watcher
if [ -f /data/local/tmp/vpn-hotspot.watch.pid ]; then
  old=$(cat /data/local/tmp/vpn-hotspot.watch.pid 2>/dev/null || true)
  [ -n "$old" ] && kill "$old" 2>/dev/null || true
  rm -f /data/local/tmp/vpn-hotspot.watch.pid
fi

/system/bin/toybox setsid /system/bin/sh /data/local/tmp/vpn-hotspot.sh watch \
  >>/data/local/tmp/vpn-hotspot.log 2>&1 < /dev/null &

sleep 1
sh /data/local/tmp/vpn-hotspot.sh status
