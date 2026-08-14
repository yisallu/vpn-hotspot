#!/system/bin/sh
# LineageOS-style "share VPN over hotspot", fail-open.
#
# - No VPN  -> do not touch Android tethering (cellular / STA wifi).
# - VPN up  -> hotspot clients go out tunX.
# - VPN down -> strip our rules FIRST so clients keep using the system upstream.
# - Never start/stop the hotspot. Never blackhole a missing tun.
#
# Usage: vpn-hotspot.sh start|stop|status|watch|sync

PREF=20500
TABLE=2048
INTERVAL=3
LOCK=/data/local/tmp/vpn-hotspot.watch.pid
STATE=/data/local/tmp/vpn-hotspot.state
LOG=/data/local/tmp/vpn-hotspot.log

log() {
  echo "[vpn-hotspot $(date '+%H:%M:%S')] $*"
}

detect_ap() {
  AP=""
  AP_NET=""
  # Only SoftAP ifaces. Never wlan0/wlan1 — those are STA.
  for i in wlan2 ap0 softap0; do
    ip link show "$i" >/dev/null 2>&1 || continue
    ip -o -4 addr show dev "$i" 2>/dev/null | grep -q "inet " || continue
    AP=$i
    AP_NET=$(ip route show dev "$AP" proto kernel 2>/dev/null | awk '{print $1; exit}')
    [ -n "$AP_NET" ] || AP_NET=$(ip -o -4 addr show dev "$AP" | awk '{print $4; exit}')
    [ -n "$AP_NET" ] && return 0
  done
  return 1
}

detect_tun() {
  TUN=""
  for i in tun0 tun1 tun2; do
    ip link show "$i" >/dev/null 2>&1 || continue
    ip -o -4 addr show dev "$i" 2>/dev/null | grep -q "inet " || continue
    TUN=$i
    return 0
  done
  return 1
}

detect_vpn_dns() {
  VPN_DNS=""
  TUN_IP=$(ip -o -4 addr show dev "$TUN" 2>/dev/null | awk '{print $4; exit}' | cut -d/ -f1)
  case "$TUN_IP" in
    *.1) VPN_DNS=${TUN_IP%.*}.2 ;;
  esac
  [ -n "$VPN_DNS" ] || VPN_DNS=1.1.1.1
}

vpn_rule_present() {
  ip rule show pref "$PREF" 2>/dev/null | grep -q .
}

# Tear down MUST delete the policy rule first. An empty table 2048 is a blackhole.
remove() {
  ip rule del pref "$PREF" 2>/dev/null || true
  ip route flush table "$TABLE" 2>/dev/null || true

  old_ap=""
  old_tun=""
  old_dns=""
  if [ -f "$STATE" ]; then
    # state: AP TUN DNS
    old_ap=$(awk '{print $1}' "$STATE")
    old_tun=$(awk '{print $2}' "$STATE")
    old_dns=$(awk '{print $3}' "$STATE")
  fi

  for ap in $old_ap wlan2 ap0 softap0; do
    [ -n "$ap" ] || continue
    for tun in $old_tun tun0 tun1 tun2; do
      [ -n "$tun" ] || continue
      iptables -D tetherctrl_FORWARD -i "$tun" -o "$ap" -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || true
      iptables -D tetherctrl_FORWARD -i "$ap" -o "$tun" -m state --state INVALID -j DROP 2>/dev/null || true
      iptables -D tetherctrl_FORWARD -i "$ap" -o "$tun" -j ACCEPT 2>/dev/null || true
      iptables -t nat -D tetherctrl_nat_POSTROUTING -o "$tun" -j MASQUERADE 2>/dev/null || true
    done
    for dns in $old_dns 10.20.0.2 1.1.1.1 8.8.8.8; do
      [ -n "$dns" ] || continue
      iptables -t nat -D PREROUTING -i "$ap" -p udp --dport 53 -j DNAT --to-destination "$dns" 2>/dev/null || true
      iptables -t nat -D PREROUTING -i "$ap" -p tcp --dport 53 -j DNAT --to-destination "$dns" 2>/dev/null || true
    done
    ip6tables -D tetherctrl_FORWARD -i "$ap" -j DROP 2>/dev/null || true
    ip6tables -D tetherctrl_FORWARD -o "$ap" -j DROP 2>/dev/null || true
    echo 0 > /proc/sys/net/ipv6/conf/"$ap"/disable_ipv6 2>/dev/null || true
  done

  settings put global tether_offload_disabled 0 2>/dev/null || true
  rm -f "$STATE"
  log "fallback: system tethering (no VPN share)"
}

apply() {
  detect_ap || { log "skip apply: no SoftAP"; return 1; }
  detect_tun || { log "skip apply: no tun"; return 1; }
  detect_vpn_dns

  echo 1 > /proc/sys/net/ipv4/ip_forward
  echo 1 > /proc/sys/net/ipv4/conf/all/forwarding 2>/dev/null || true
  echo 1 > /proc/sys/net/ipv4/conf/"$AP"/forwarding 2>/dev/null || true
  echo 1 > /proc/sys/net/ipv4/conf/"$TUN"/forwarding 2>/dev/null || true
  echo 2 > /proc/sys/net/ipv4/conf/"$AP"/rp_filter 2>/dev/null || true
  echo 2 > /proc/sys/net/ipv4/conf/"$TUN"/rp_filter 2>/dev/null || true

  # Build the VPN table first. Do NOT install the ip rule until forwarding is ready.
  ip route replace default dev "$TUN" table "$TABLE"
  ip route replace "$AP_NET" dev "$AP" table "$TABLE"

  iptables -C tetherctrl_FORWARD -i "$TUN" -o "$AP" -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || \
    iptables -I tetherctrl_FORWARD 1 -i "$TUN" -o "$AP" -m state --state RELATED,ESTABLISHED -j ACCEPT
  iptables -C tetherctrl_FORWARD -i "$AP" -o "$TUN" -m state --state INVALID -j DROP 2>/dev/null || \
    iptables -I tetherctrl_FORWARD 2 -i "$AP" -o "$TUN" -m state --state INVALID -j DROP
  iptables -C tetherctrl_FORWARD -i "$AP" -o "$TUN" -j ACCEPT 2>/dev/null || \
    iptables -I tetherctrl_FORWARD 3 -i "$AP" -o "$TUN" -j ACCEPT

  iptables -t nat -C tetherctrl_nat_POSTROUTING -o "$TUN" -j MASQUERADE 2>/dev/null || \
    iptables -t nat -I tetherctrl_nat_POSTROUTING -o "$TUN" -j MASQUERADE

  iptables -t nat -C PREROUTING -i "$AP" -p udp --dport 53 -j DNAT --to-destination "$VPN_DNS" 2>/dev/null || \
    iptables -t nat -I PREROUTING -i "$AP" -p udp --dport 53 -j DNAT --to-destination "$VPN_DNS"
  iptables -t nat -C PREROUTING -i "$AP" -p tcp --dport 53 -j DNAT --to-destination "$VPN_DNS" 2>/dev/null || \
    iptables -t nat -I PREROUTING -i "$AP" -p tcp --dport 53 -j DNAT --to-destination "$VPN_DNS"

  ip6tables -C tetherctrl_FORWARD -i "$AP" -j DROP 2>/dev/null || \
    ip6tables -I tetherctrl_FORWARD 1 -i "$AP" -j DROP
  ip6tables -C tetherctrl_FORWARD -o "$AP" -j DROP 2>/dev/null || \
    ip6tables -I tetherctrl_FORWARD 1 -o "$AP" -j DROP
  echo 1 > /proc/sys/net/ipv6/conf/"$AP"/disable_ipv6 2>/dev/null || true

  # Hardware offload would keep sending IPv4 to rmnet. Only while VPN is shared.
  settings put global tether_offload_disabled 1 2>/dev/null || true

  # Install the policy rule last, and only if tun is still there.
  if ! ip link show "$TUN" >/dev/null 2>&1; then
    log "tun vanished during apply, aborting to stay fail-open"
    remove
    return 1
  fi
  if ! vpn_rule_present; then
    ip rule add pref "$PREF" iif "$AP" lookup "$TABLE"
  fi

  echo "$AP $TUN $VPN_DNS" > "$STATE"
  log "share ON  AP=$AP ($AP_NET) TUN=$TUN DNS=$VPN_DNS"
}

sync_now() {
  have_ap=0
  have_tun=0
  detect_ap && have_ap=1
  detect_tun && have_tun=1
  have_rule=0
  vpn_rule_present && have_rule=1

  if [ "$have_ap" = 1 ] && [ "$have_tun" = 1 ]; then
    # Need apply if rule missing or android overwrote FORWARD.
    if [ "$have_rule" != 1 ] \
      || ! iptables -C tetherctrl_FORWARD -i "$AP" -o "$TUN" -j ACCEPT 2>/dev/null \
      || ! iptables -t nat -C tetherctrl_nat_POSTROUTING -o "$TUN" -j MASQUERADE 2>/dev/null; then
      apply || true
    fi
  else
    # Fail open: any missing piece -> strip our hijack immediately.
    if [ "$have_rule" = 1 ] || [ -f "$STATE" ]; then
      remove
    fi
  fi
}

status() {
  echo "=== mode ==="
  if vpn_rule_present; then
    echo "VPN_SHARE"
  else
    echo "SYSTEM_TETHER (fail-open)"
  fi
  echo "=== ifaces ==="
  ip -o -4 addr show | grep -E "wlan|tun|rmnet_data3|ap0|softap" || true
  echo "=== rule $PREF ==="
  ip rule show pref "$PREF" || true
  echo "=== table $TABLE ==="
  ip route show table "$TABLE" || true
  echo "=== state file ==="
  cat "$STATE" 2>/dev/null || echo none
  echo "=== FORWARD ==="
  iptables -S tetherctrl_FORWARD | head -10
  echo "=== NAT ==="
  iptables -t nat -S tetherctrl_nat_POSTROUTING
  echo "=== DNS ==="
  iptables -t nat -S PREROUTING | grep dport || echo none
  echo "=== watcher ==="
  if [ -f "$LOCK" ] && [ -d "/proc/$(cat "$LOCK" 2>/dev/null)" ]; then
    echo "alive pid=$(cat "$LOCK")"
  else
    echo "not running"
  fi
}

stop_watchers() {
  if [ -f "$LOCK" ]; then
    old=$(cat "$LOCK" 2>/dev/null || true)
    [ -n "$old" ] && kill "$old" 2>/dev/null || true
    rm -f "$LOCK"
  fi
}

watch() {
  stop_watchers
  echo $$ > "$LOCK"
  log "watch pid=$$ heartbeat=${INTERVAL}s (fail-open)"
  sync_now

  # Instant reaction to tun/SoftAP appearing or disappearing.
  (
    ip monitor link 2>/dev/null | while read -r line; do
      [ -f "$LOCK" ] || exit 0
      case "$line" in
        *tun0*|*tun1*|*tun2*|*wlan2*|*ap0*|*softap0*) sync_now ;;
      esac
    done
  ) &
  mon=$!

  while [ -f "$LOCK" ]; do
    sync_now
    sleep "$INTERVAL"
  done
  kill "$mon" 2>/dev/null || true
}

cmd=${1:-sync}
case "$cmd" in
  start|sync) sync_now ;;
  stop)
    stop_watchers
    remove
    ;;
  status) status ;;
  watch) watch ;;
  *)
    echo "usage: $0 start|stop|status|watch|sync" >&2
    exit 2
    ;;
esac
