# vpn-hotspot

给 **没有 LineageOS「共享 VPN」开关** 的 Android（这台是 HyperOS）补同样行为：

| 状态 | 连热点的设备 |
|---|---|
| 没开 VPN | 正常上网，走系统热点上游（蜂窝或手机自己连的 Wi‑Fi） |
| 开了 VPN | 流量走 `tun0`（Karing 等 VpnService） |
| VPN 断了 | **立刻退回系统热点**，不会断网 |

**fail-open**：没有隧道就绝不装 `ip rule`。空的 policy table 是黑洞——上一版电脑断网就是规则还指着已经没了的 `tun0`。

脚本不替你开关热点，也不替你开关 Karing。控制中心开热点、Karing 里连/断即可。

设备相关账号见 [DEVICE.md](DEVICE.md)。

---

## 以后怎么操作

### 0. 前提

- 电脑已装 `adb`，USB 调试开着
- 手机 Magisk root（`adb shell su -c id` 应是 `uid=0`）
- 热点用系统开关打开（SSID 见 DEVICE.md）
- 翻墙用 Karing（或任何标准 `VpnService`，接口 `tun0`/`tun1`/`tun2`）

### 1. 装到手机（换机 / 清过 `/data/local/tmp` 时）

在仓库根目录：

```powershell
.\install.ps1
```

会推脚本、写入 Magisk `service.d` 开机挂钩、拉起守护。

只推文件、不启动：

```powershell
.\install.ps1 -NoStart
```

### 2. 日常

电脑连上 ADB 后：

```powershell
.\scripts\vpn-hotspot.ps1 status
.\scripts\vpn-hotspot.ps1 start    # 守护挂了就再拉一次
.\scripts\vpn-hotspot.ps1 stop     # 停守护并清 VPN 劫持（热点仍开）
.\scripts\vpn-hotspot.ps1 hotspot-on
.\scripts\vpn-hotspot.ps1 hotspot-off
```

或直接：

```powershell
adb shell "su -c 'sh /data/local/tmp/vpn-hotspot.sh status'"
adb shell "su -c 'sh /data/local/tmp/vpn-hotspot-boot.sh'"
adb shell "su -c 'sh /data/local/tmp/vpn-hotspot.sh stop'"
```

`status` 里：

- `SYSTEM_TETHER (fail-open)` = 没劫持，电脑应能正常上网
- `VPN_SHARE` = 热点在走 VPN

### 3. 验证（每次重装后做一遍）

1. 电脑连热点，**先别开 Karing** → 国内网站能开
2. 手机打开 Karing 连上 → 电脑刷新 <https://ip.sb> / Google，IP 变到节点
3. 手机断开 Karing → 电脑马上恢复普通上网，**不能再断网**

### 4. 重启手机之后

开机挂钩会等 `sys.boot_completed=1` 再睡 20 秒，然后自己 `watch`。  
如果没起来：

```powershell
.\scripts\vpn-hotspot.ps1 start
```

---

## 原理

只在「SoftAP 在 + tun 在」时才装：

```
wlan2  --ip rule pref 20500-->  table 2048  --> default dev tun0
iptables FORWARD  wlan2 <-> tun0
NAT MASQUERADE -o tun0
DNS DNAT :53 -> VPN DNS（Karing 一般是 10.20.0.2）
ip6tables DROP wlan2   （防运营商 IPv6 绕过）
```

`tun` 或热点任一消失：

1. **先删** `ip rule 20500`（空表是黑洞，必须先拆这条）
2. 再清 iptables / DNS / IPv6 DROP
3. 恢复 `tether_offload_disabled=0`
4. 系统自己的 `wlan2 -> wlan0/rmnet_data3` 继续工作

守护每 3 秒对一次，并用 `ip monitor link` 盯 `tun*` / `wlan2`。

只认 SoftAP 口：`wlan2` / `ap0` / `softap0`。**不会**把 STA 的 `wlan0` 当热点。

---

## 仓库文件

| 路径 | 作用 |
|---|---|
| `scripts/vpn-hotspot.sh` | 主逻辑：`sync` / `stop` / `status` / `watch` |
| `scripts/vpn-hotspot-boot.sh` | 拉起 `watch` |
| `scripts/zzz_vpn_hotspot.sh` | Magisk 启动器（立刻退出，后台等开机） |
| `scripts/vpn-hotspot.ps1` | 电脑封装 |
| `install.ps1` | 推到手机并安装开机挂钩 |
| `DEVICE.md` | 这台 Poco F5 的 serial / SSID / 路径 |

装到手机后：

| 机内路径 | 作用 |
|---|---|
| `/data/local/tmp/vpn-hotspot.sh` | 主脚本 |
| `/data/local/tmp/vpn-hotspot-boot.sh` | 启动入口 |
| `/data/adb/service.d/zzz_vpn_hotspot.sh` | 开机挂钩 |
| `/data/local/tmp/vpn-hotspot.log` | 日志 |
| `/data/local/tmp/vpn-hotspot.state` | 当前 AP/TUN/DNS（有共享时才有） |
| `/data/local/tmp/vpn-hotspot.watch.pid` | 守护 PID |

`service.d` 禁止写 `while true` 狂敲 binder（同类脚本曾经把开机打卡 logo）。启动器只丢后台再 `exit 0`。

---

## 排障

| 现象 | 查什么 |
|---|---|
| 电脑连上没网，Karing 也没开 | `status` 不该是 `VPN_SHARE`。跑 `stop` 清规则 |
| 开了 Karing 电脑不能翻墙 | `status` 应变成 `VPN_SHARE`；没有就 `start`。确认 `tun0` 存在 |
| 关 Karing 后又断网 | 守护死了，规则还在。立刻 `stop`，再 `start` |
| 重启后没共享 | `.\scripts\vpn-hotspot.ps1 start`；看 `/data/adb/service.d/zzz_vpn_hotspot.sh` 还在不在 |
| PowerShell 里 `su -c` 乱报错 | 引号被吃了。用 `adb shell "su -c '...'"` 外双内单 |

不要改 Android 的 netId 表（97 / 1020 / 1045），只用自己的 2048。
