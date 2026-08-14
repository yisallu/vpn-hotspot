# 手机热点共享 VPN（LineageOS 同款行为）

日期：2026-08-14（重做，fail-open）  
设备：`8026ca76` / 23049PCD8G（Poco F5 · HyperOS 3.0.4）  
前提：ADB + Magisk root。VPN 用 Karing（`com.nebula.karing`）

---

## 行为（跟 LineageOS「共享 VPN」一样）

| 状态 | 连热点的设备 |
|---|---|
| 没开 VPN | 正常上网，走系统热点上游（蜂窝或手机自己连的 Wi‑Fi） |
| 开了 VPN | 流量改走 `tun0`，可以翻墙 |
| VPN 断了 | **立刻退回系统热点**，不会断网 |

上次断网的原因：规则还指着已经没了的 `tun0`，等于黑洞。  
这次 **先删劫持规则，再谈共享**。没有隧道就绝不装 `ip rule`。

---

## 热点

| 项 | 值 |
|---|---|
| SSID | `zi3` |
| 密码 | `88888888` |
| 接口 | `wlan2`（`10.187.219.71/24`） |
| 没 VPN 时上游 | 系统选：现在是手机 STA `wlan0`，没有 Wi‑Fi 就走 `rmnet_data3` |
| 有 VPN 时上游 | Karing `tun0` |

脚本 **不会** 替你开关热点、也 **不会** 替你开关 Karing。  
你照常：控制中心开热点、Karing 里连/断。

---

## 用法

电脑连一次 ADB 后，守护会一直在（也已放进 Magisk `service.d`，开机等 `boot_completed` 再跑）：

```powershell
adb shell "su -c 'sh /data/local/tmp/vpn-hotspot-boot.sh'"
```

看当前是系统热点还是 VPN 共享：

```powershell
adb shell "su -c 'sh /data/local/tmp/vpn-hotspot.sh status'"
```

- `SYSTEM_TETHER (fail-open)` = 没劫持，电脑应能正常上网  
- `VPN_SHARE` = 热点在走 Karing

停掉守护并清规则（热点仍开，只是不再跟 VPN）：

```powershell
adb shell "su -c 'sh /data/local/tmp/vpn-hotspot.sh stop'"
```

---

## 你怎么验证

1. 电脑连 `zi3` / `88888888`，**先别开 Karing** → 应能打开任意国内网站。  
2. 手机打开 Karing 连上 → 电脑刷新 `https://ip.sb` / Google，IP 应变到节点。  
3. 手机断开 Karing → 电脑应马上恢复普通上网，**不能再断网**。

---

## 原理

只在「热点在 + tun 在」时才装：

```
wlan2  --ip rule pref 20500-->  table 2048  --> default dev tun0
iptables FORWARD  wlan2 <-> tun0
NAT MASQUERADE -o tun0
DNS DNAT :53 -> VPN DNS（一般 10.20.0.2）
ip6tables DROP wlan2   （防运营商 IPv6 绕过）
```

`tun` 或热点任一消失：

1. **先删** `ip rule 20500`（空表是黑洞，必须先拆这条）  
2. 再清 iptables / DNS / IPv6 DROP  
3. 恢复 `tether_offload_disabled=0`  
4. 系统自己的 `wlan2 -> wlan0/rmnet_data3` 继续工作

守护每 3 秒对一次，并用 `ip monitor link` 盯 `tun*` / `wlan2`，VPN 通断几乎马上切。

---

## 文件

| 路径 | 作用 |
|---|---|
| `D:\pocof5\tools\vpn-hotspot.sh` | 主逻辑 start/sync/stop/status/watch |
| `D:\pocof5\tools\vpn-hotspot-boot.sh` | 拉起 watch |
| `D:\pocof5\tools\zzz_vpn_hotspot.sh` | Magisk 启动器（立刻退出，后台等开机） |
| `/data/local/tmp/vpn-hotspot.sh` | 机内主脚本 |
| `/data/adb/service.d/zzz_vpn_hotspot.sh` | 开机挂钩 |
| `/data/local/tmp/vpn-hotspot.log` | 日志 |

`service.d` 只 `setsid` 一下就退出，真正的 watch 等 `sys.boot_completed=1` 再加 20 秒，避免再踩开机卡 logo。

---

## 不要做的

- 不要在 `service.d` 里写 `while true` 狂敲 binder。  
- 不要改 Android 的 netId 表（97 / 1020 / 1045），只用自己的 2048。  
- 不要在没有 `tun` 时保留 `iif wlan2 lookup 2048`。
