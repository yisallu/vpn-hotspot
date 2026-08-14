# 这台设备（Poco F5 / marble）

换机后改这个文件和 `scripts/vpn-hotspot.ps1` 里的默认 serial。

| 项 | 值 |
|---|---|
| ADB serial | `8026ca76` |
| 型号 | 23049PCD8G（marble） |
| 系统 | HyperOS 3.0.4（`OS3.0.4.0.VMREUXM`），Android 15 |
| Root | Magisk |
| VPN | Karing `com.nebula.karing`（`VpnService` → `tun0`） |
| 热点 SSID | `zi3` |
| 热点密码 | `88888888` |
| 安全 | WPA2 |
| SoftAP 接口 | `wlan2`（常见地址 `10.187.219.71/24`） |
| 蜂窝 | `rmnet_data3` |
| 手机自己连 Wi‑Fi 时 | STA 是 `wlan0`，系统热点上游会选它 |

`cmd wifi start-softap` **必须 root**。shell 用户会 `SecurityException`。

环境变量可覆盖 serial：

```powershell
$env:ANDROID_SERIAL = '8026ca76'
```
