# 手机↔电脑文件互传调研与方案（LHT16 / OpenHarmony 4.1.7.5 / API 11）

- 实测日期：2026-11-17
- 设备：LHT16，`OpenHarmony-4.1.7.5`，API 11，`arm64-v8a`，1080×2408
- 工程约束：ArkTS Stage、零三方依赖、非系统应用、无系统签名、不能改系统分区
- 文档边界：只做调研与方案设计，不创建工程、不修改现有仓库代码；实机仅做只读查询、`aa start`、启动预置服务观察端口（随后恢复），并拉取 HAP 副本做离线分析
- 相关调研：[APP-BROWSER.md](APP-BROWSER.md)（本机预置浏览器能力）
- 结论版本：v1.0

## 0. 结论摘要

1. **预置 `com.pengju.minihttpserver` 不是“可改造的传输 App”，而是一个系统参数开关 + root 守护进程的外壳。** 点“打开服务”后，`/vendor/etc/init/http_server.cfg` 以 **root** 启动 `/vendor/bin/miniserve -p 80 -W /data -u`，监听 `0.0.0.0:80`，**无鉴权、允许上传、根目录是整个 `/data`**。同网段任何设备都能读写应用沙箱和系统数据。**应保持关闭，不能作为产品基础。**
2. **普通应用不能监听 80。** 设备 `/proc/sys/net/ipv4/ip_unprivileged_port_start = 1024`；80 之所以能起，是因为 init 以 root 启动 miniserve，不是 App 进程的能力。普通应用可用 `@ohos.net.socket` 的 `TCPSocketServer` 监听 **8080 等高位端口**，需声明 `ohos.permission.INTERNET`（normal / system_grant）。
3. **“手机内 HTTP 服务”技术可行，但只在应用前台/亮屏时可靠。** `DATA_TRANSFER` 长时任务只提升优先级，系统仍会挂起应用进程；不能把它当作后台常驻服务器。实践上是“前台 + 保持亮屏 + 空闲自动停”，大文件/熄屏场景用兜底通道。
4. **“电脑起服务 + 手机浏览器上传”在本机不成立。** 本机唯一可打开的浏览器是 `ohos.samples.browser1`：`module.json` 只有 home skills，HAP 中没有 `onShowFileSelector` / `onDownloadStart`，且既有调研确认地址栏强制拼 `https://`，无法打开 `http://IP:端口`。要做这条路线，必须先自建浏览器壳（另立项目），不适合本次。
5. **推荐 A（手机内 HTTP 服务）+ C（hdc 兜底）/ B′（电脑服务 + 原生 ArkTS 客户端）备选；不采用 WebDAV/SMB，不把扫码作为首版硬需求。** 首版用 6 位配对码 + 手输地址即可。单人工作量约 **7~9 人日**，MVP（能传）约 **3.5~4.5 人日**。
6. **WebDAV/SMB 在 API 11 上不划算。** `@ohos.net.http` 的 `RequestMethod` 只有 OPTIONS/GET/HEAD/POST/PUT/DELETE/TRACE/CONNECT，没有 PROPFIND/MKCOL；`rcp` 不在 API 11 SDK；SDK 没有 SMB 客户端 API，CIFS 挂载需要 root。只能走裸 TCP 自己实现，成本高于自建 HTTP 服务。

---

## 1. 现状实测

### 1.1 设备与运行时

| 项 | 值 | 来源 |
| --- | --- | --- |
| 系统 | `OpenHarmony-4.1.7.5`，API 11，产品版本 2.0.613 | `param get` |
| 型号 | `LHT16` | `param get const.product.model` |
| shell | `uid=0(root)` | `id` |
| 网络 | Wi-Fi，当前 `192.168.31.175/24` | `netstat` / `ip` |
| 未特权端口起点 | `1024` | `/proc/sys/net/ipv4/ip_unprivileged_port_start` |
| 已装浏览器 | `ohos.samples.browser1`（系统示例，API 9）；`com.ohos.nweb`（引擎载体，无 ability） | `bm dump -a` |
| 文件选择器 | `com.ohos.filepicker` 1.1.0.300，API 9/10，系统应用 | `bm dump` |
| 外部文件管理 | `com.ohos.UserFile.ExternalFileManager` 1.0.0.3，API 9，系统应用 | `bm dump` |

> 本机没有独立“文件管理”应用；用户侧的公共文件入口只有 FilePicker。应用沙箱与公共目录的边界见 §2.1。

### 1.2 `com.pengju.minihttpserver` 拆解

#### 1.2.1 包信息（`bm dump -n`）

| 字段 | 值 |
| --- | --- |
| `bundleName` | `com.pengju.minihttpserver` |
| 版本 | `1.0.1` / `1000001` |
| 路径 | `/system/app/com.pengju.minihttpserver/HttpServer.hap` |
| 大小 | 55,419 B |
| 预置 | `isPreInstallApp: true`，`isSystemApp: false`，`appDistributionType: os_integration` |
| 权限级别 | `normal` |
| 申请权限 | 仅 `ohos.permission.GET_WIFI_INFO` |
| SDK | `compileSdkVersion 4.0.10.19`，`apiTargetVersion 10`，`minAPIVersion 10` |
| 模型 | Stage，`uiSyntax: hml`，主 ability `EntryAbility`，页面 `pages/Index` |
| 桌面 | `hideDesktopIcon: false`，可被 launcher 打开 |
| 进程 | `com.pengju.minihttpserver`，uid `20010049` |

HAP 内只有 `ets/modules.abc`、`module.json`、资源，没有 native 库。反汇编 `modules.abc` 可见：

- `import systemParameter from '@ohos:systemparameter'`
- 调用 `systemParameter.setSync('miniserve.started', '1' / '0')`
- 页面状态从 `systemParameter.getSync('miniserve.started', '0')` 读取

**结论：App 本身不提供 HTTP 服务，只负责切换系统参数；真正的服务器是 vendor 的 root 守护进程。**

#### 1.2.2 UI 与入口

`aa start -a EntryAbility -b com.pengju.minihttpserver` 成功。界面文字：

- 标题：`HTTP服务已关闭`
- 说明：`在同一WiFi内的其他设备上，可以通过如下链接下载和上传文件。`
- 地址：`http://192.168.31.175`（端口 80 省略）
- 按钮：`打开服务`

点击“打开服务”后，`netstat -tlnp`：

```text
tcp   0 0 0.0.0.0:80     0.0.0.0:*  LISTEN  21998/miniserve
tcp6  0 0 :::80          :::*       LISTEN  21998/miniserve
```

进程与启动参数：

```text
root 21998 1 ... miniserve -p 80 -W /data -u
Uid: 0 0 0 0
```

`/vendor/etc/init/http_server.cfg`：

```json
{
  "jobs": [
    { "name": "param:miniserve.started=1", "condition": "miniserve.started=1",
      "cmds": ["start mini_http_service"] },
    { "name": "param:miniserve.started=0", "condition": "miniserve.started=0",
      "cmds": ["stop mini_http_service"] }
  ],
  "services": [{
    "name": "mini_http_service",
    "start-mode": "condition",
    "path": ["/vendor/bin/miniserve", "-p", "80", "-W", "/data", "-u"],
    "uid": "root",
    "gid": "root",
    "secon": "u:r:init:s0"
  }]
}
```

#### 1.2.3 暴露面实测

从 PC 直接访问：

```text
HTTP/1.1 200 OK
content-type: text/html; charset=utf-8
```

`GET /?sort=name` 返回根目录列表，包含：

```text
/app/  /ashmem/  /bluetooth/  /chipset/  /data/  /local/  /log/
/misc/  /modem_ril.ini  /module_update/  /nfc/  /samgr/  /service/
/system/  /unix/  /update/  /updater/  /vendor/
```

这说明 `-W /data` 生效，根目录就是整个 `/data`。响应没有 `WWW-Authenticate`，也没有登录页；`-u` 表示上传开启。**即：同网段任意设备可无密码浏览、下载，并可向 root 可写的 `/data` 任意位置上传。**

> 为避免污染 `/data`，本次**没有实际上传文件**；只验证了目录列表和启动参数。验证完成后已执行 `param set miniserve.started 0`，确认进程和 `:80` 监听消失。

#### 1.2.4 安全结论

| 项 | 实际情况 | 风险 |
| --- | --- | --- |
| 运行身份 | `uid=0(root)`，由 init 启动 | 极高 |
| 根目录 | `/data` 全分区 | 极高：应用沙箱、数据库、token、照片等全部可见 |
| 鉴权 | 无 | 极高：同网段任何人可访问 |
| 上传 | `-u` 已开 | 极高：可写 root 可写路径 |
| 端口 | 80，所有接口 | 高：易被扫描 |
| 可复用性 | 只有 `.abc` 壳，依赖系统参数 + vendor init 服务 | 不可复用；改造成本/合规风险高 |

**处理建议：保持 `miniserve.started=0`；不要把它当作日常传输工具；禁止在公共/不可信 Wi-Fi 打开。** 若必须临时使用，只在可信家庭网络、传完立即关闭，并避免上传敏感文件。

### 1.3 其他预置能力

- `com.ohos.filepicker`：系统应用，权限含 `FILE_ACCESS_MANAGER`、`PROXY_AUTHORIZATION_URI`、`READ_MEDIA`、`WRITE_MEDIA` 等。普通应用通过 `@ohos.file.picker` 的 `DocumentViewPicker` 调起，拿到的是**临时授权 URI**，不是公共目录全量权限。
- `com.ohos.UserFile.ExternalFileManager`：系统应用，`FILE_ACCESS_MANAGER`，属于公共文件访问框架的一部分；不是可被普通应用直接复用的客户端。
- 没有独立文件管理器，因此“把文件放进公共下载目录”不能靠系统文件管理器完成，必须走 FilePicker 的保存流程。

### 1.4 端口与浏览器事实

- `ip_unprivileged_port_start=1024`：普通应用 UID 不能 bind 80/443 等低位端口；需要 `CAP_NET_BIND_SERVICE`，普通应用没有。
- 当前 `8080` 未被占用；高位的 8080/8686 可用。App 应做 8080~8090 的占用探测，失败时提示改端口。
- `ohos.samples.browser1`：
  - `module.json` 的 skills 只有 `action.system.home` + `entity.system.home`，没有 `viewData` / `browsable`。
  - HAP 的 `modules.abc` 中 `onShowFileSelector`、`onDownloadStart`、`setDownloadDelegate` 出现次数均为 0。
  - 既有调研（[APP-BROWSER.md](APP-BROWSER.md) 1.3）确认其 `loadUrl()` 强制拼 `https://`，`http://IP:端口` 打不开。
  - **结论：不能用它做“手机浏览器上传/下载”通道。**

---

## 2. 通道可行性

### 2.1 应用内 HTTP 服务器（手机当服务端，PC 浏览器当客户端）

**API 事实（以本机 API 11 SDK `@ohos.net.socket.d.ts` 为准）**

| 项 | 事实 |
| --- | --- |
| 服务端类 | `socket.constructTCPSocketServerInstance()` → `TCPSocketServer` |
| 起始版本 | `@since 10`（API 11 可用） |
| 监听 | `listen(address: NetAddress): Promise<void>` / callback |
| 权限 | `ohos.permission.INTERNET`（normal，system_grant，安装即授予，无弹窗） |
| 客户端连接 | `on('connect', (conn: TCPSocketConnection) => ...)` |
| 收数据 | `conn.on('message', (info: SocketMessageInfo) => ...)`，`info.message` 为 `ArrayBuffer` |
| 发数据 | `conn.send({ data: ArrayBuffer | string, encoding?: string })` |
| 绑定地址 | 可 `0.0.0.0`（局域网）或 `127.0.0.1`（仅本机/配合 hdc fport） |
| 端口范围 | 结构上 0~65535；实际受内核 `ip_unprivileged_port_start=1024` 限制，普通应用用 **≥1024** |
| 错误 | `201` 权限拒绝；`2303198` 地址占用；`2303109` 坏文件号等 |

**可行性判断：可行。** 这是“PC 浏览器 ⇄ 手机 App”最直接的通道：

- PC 侧不需要安装任何软件，Chrome/Edge 即可；
- 手机侧不需要浏览器（正好绕开 browser1 的限制）；
- 不依赖公网、不依赖云；
- 保持零三方依赖，纯 ArkTS 实现 HTTP/1.1 子集。

**必须自己实现的部分**

1. 增量解析请求头：按 `\r\n\r\n` 切分，限制头大小（如 16 KB），解析 `Content-Length`、`Content-Type`、`Cookie`、`Range`。
2. 上传：建议 PC 页面用 `fetch`/XHR 对每个文件发 **`PUT /u/<name>` 原始字节**，而不是 `<form multipart>`。这样服务端只需按 `Content-Length` 流式写文件，**不需要 multipart 解析器**，代码量和出错面都小很多。
3. 下载：`GET /f/<id>`，用 `Content-Length` + `Content-Disposition: attachment; filename*=UTF-8''...`，分块 `fs.read` + `conn.send`，不要整文件读入内存。
4. 列表/会话：`GET /api/files` 返回 JSON；`POST /pair` 校验 6 位码后下发 HttpOnly Cookie；所有文件接口校验会话。
5. 连接管理：每连接状态机、空闲超时、最大并发（如 8）、最大头上限、最大上传大小、临时文件 + 原子 rename、磁盘剩余空间检查。
6. 文件名安全：只取 basename，拒绝 `..`、`/`、`\`、控制字符；UTF-8 文件名用 RFC 5987 编码。

**生命周期与后台限制（关键）**

- `@ohos.resourceschedule.backgroundTaskManager` 的 `DATA_TRANSFER` 长时任务**只提升进程优先级，系统仍会挂起应用进程**；官方文档明确“需要调用系统上传下载代理接口托管给系统执行”。它不是“后台常驻服务器”。
- 因此本方案的实际运行模式是：**App 在前台 + `setWindowKeepScreenOn(true)` + 传输期间不锁屏**。用户看着传，传完自动停。
- 不建议申请 `DATA_TRANSFER` 来伪装后台服务：既不能阻止挂起，还可能因“未真正执行对应任务”被系统管控。
- App 退到后台时应主动停止监听并清理连接，避免“看似在传、实际已断”的假状态。

**安全**

- 明文 HTTP，无 TLS；局域网可被嗅探。PIN 只能防误连/弱扫描，不能防同网段抓包。
- 首版安全基线：随机 6 位码 + 会话 Cookie + 每 IP 尝试限速 + 空闲 10 分钟自动停 + 只暴露 App 收件箱 + 不做目录遍历。
- 可选增强：`TLSSocketServer`（API 11 可用）自签证书，但 PC 浏览器会告警，不适合“傻瓜化”首版；或绑定 `127.0.0.1`，PC 侧用 `hdc fport tcp:8080 tcp:8080` 走 USB，完全不暴露局域网。

**结论：主方案可行，前提是接受“前台亮屏传输”。**

### 2.2 反向：电脑起 HTTP 服务，手机端下载/上传

#### 2.2.1 手机端客户端能力

| 能力 | API | 限制 |
| --- | --- | --- |
| `@ohos.net.http` | API 6+ | 只有客户端；`RequestMethod` 无 PROPFIND/MKCOL；请求体为 string/Object/ArrayBuffer，**没有文件流式上传**；大文件全量进内存不现实 |
| `@ohos.request.uploadFile` | API 9+ | 需 `INTERNET`；**只支持上传应用缓存目录（cacheDir）下的文件**；系统服务代理，可在后台继续 |
| `@ohos.request.downloadFile` | API 9+ | 需 `INTERNET`；**只能下载到应用文件目录**；系统服务代理，可在后台继续 |
| `@ohos.net.webSocket` | API 6+ | 可用于信令/小数据，不适合大文件 |

因此，若走“PC 服务端”路线，手机端有两种做法：

- **B（原任务描述）：PC 服务 + 手机预置浏览器上传/下载。**
  - 本机 browser1 不支持 `http://IP:端口`、无文件选择、无下载委托 → **不可行**。
  - 要可行必须先自建 ArkWeb 浏览器壳（参考 [APP-BROWSER.md](APP-BROWSER.md)），额外 5~6 人日 + 单标签 250~350 MiB 内存，不划算。
- **B′：PC 服务 + 手机原生 ArkTS 客户端。**
  - 手机 App 用原生列表/选择器，上传前把 picker 文件复制到 `cacheDir`，再 `request.uploadFile`；下载用 `request.downloadFile` 到沙箱，再 picker 导出。
  - 优点：传输由系统上传下载服务代理，**熄屏/后台也能继续**，不受 §2.1 的挂起限制。
  - 缺点：需要 PC 常驻服务；上传多一次“picker → cacheDir”复制；PC→手机是“手机拉取”，不是 PC 主动推送；需要处理 PC IP/防火墙/服务发现。

**结论：B 否决；B′ 可行，作为 A 的后台/大文件备选。**

### 2.3 WebDAV / SMB

**WebDAV**

- WebDAV 依赖 `PROPFIND`、`MKCOL`、`MOVE`、`COPY` 等方法；`@ohos.net.http` 的 `RequestMethod` 枚举没有这些方法（只有 OPTIONS/GET/HEAD/POST/PUT/DELETE/TRACE/CONNECT），不能用它实现标准 WebDAV 客户端。
- API 11 SDK 没有 `rcp`（Remote Communication Kit）；找到的开源 ArkTS WebDAV 客户端 `qy2001/qy2001-webdav_client_harmonyos` 基于 `rcp`、`compatibleSdkVersion 5.0.0(12)`，且仓库**没有 LICENSE**，不能用于本约束。
- 理论上可用 `TCPSocket` 自己实现 WebDAV 客户端 + XML 解析，但工作量大于自建一个精简 HTTP 服务，且没有文件管理器集成收益。
- **结论：不采用。**

**SMB**

- API 11 SDK 没有 SMB 客户端 API；要用只能引入 NAPI 的 `libsmbclient` 等三方 native 库，违反零三方依赖，还要编 arm64 `.so`。
- 内核 CIFS 挂载需要 root；设备虽然 shell 是 root，但普通 App 不能挂载，且会改变系统挂载状态，违反约束。
- **结论：不可行。**

### 2.4 hdc 文件通道（零开发兜底）

**能力**

```text
hdc file send [option] local remote   # 主机 -> 设备
hdc file recv [option] remote local   # 设备 -> 主机
hdc fport localnode remotenode        # 主机端口 -> 设备端口
hdc rport remotenode localnode        # 设备端口 -> 主机端口
```

**已有先例**

`D:\ohos-kiosk\scripts\push-photos.sh` 已经做过：

- 优先直接写应用沙箱 `/data/app/el2/100/base/<bundle>/haps/<module>/files/...`；
- root 写入后 `chown` 回应用 uid、`chmod 660`；
- 失败时退到 `/data/local/tmp` 暂存，并给出 root `cp` 的手动步骤；
- 处理了 Git Bash 路径转换和 `hdc file send` 远端相对路径的坑。

**优点**

- 零 App 开发、零端口、零局域网暴露；
- 大文件稳定，走 USB；
- 设备有 root shell，可直接读写沙箱/公共目录；
- 可配合 `hdc fport` 把 App 的 `127.0.0.1:8080` 映射到 PC，兼顾安全与浏览器体验。

**缺点**

- 必须插 USB、开开发者模式/hdc；
- 不是“傻瓜化”日常体验；
- 直接写 `/data` 有权限/属主风险，脚本必须限定目录并 `chown`；
- Windows 路径、相对路径、编码坑较多。

**结论：作为兜底/运维通道保留，不作为首版主交互。**

### 2.5 扫码配对与 6 位配对码

- `@ohos.multimedia.camera` 可用，但需要 `ohos.permission.CAMERA`（user_grant），且 API 11 SDK **没有二维码解码 API**；要解码必须引入 ZXing/NAPI 等三方库，违反零依赖。
- 纯前端二维码**生成**可以 vendored `qrcode-generator`（MIT，`kazuhikoarase/qrcode-generator`）之类的代码，但解决不了“谁来扫”：
  - PC 浏览器没有标准扫码能力（Chrome 的 `BarcodeDetector` 支持不稳定，且需要摄像头）；
  - 手机没有可用的浏览器/扫码 App；
  - 让 PC 扫手机屏幕上的二维码，需要 PC 有摄像头 + 额外页面，不是通用能力。
- **首版建议：手机显示 `http://IP:端口` + 6 位随机配对码，PC 浏览器输入一次，服务端下发会话 Cookie。** 这就是“输地址 + 输码”，比扫码更稳、更少依赖。
- 可选后续：PC 端用 Chrome `BarcodeDetector` + 手机显示二维码（仅作锦上添花）；或 App 内用相机扫 PC 屏幕上的二维码（需要引入解码库，暂不做）。

---

## 3. 候选方案对比

| 方案 | 组成 | 工作量（单人） | 权限/端口风险 | 文件访问范围 | 网络要求 | 安全 | 结论 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| **A. 手机内 HTTP 服务** | ArkTS App：`TCPSocketServer` + 内嵌 PC 页面 + 收件箱 | 7~9 人日；MVP 3.5~4.5 | 需 `INTERNET`（normal）；只能高位端口；无 root | App 沙箱收件箱；手机→PC 用 picker URI；PC→手机后需 picker 导出 | 同一局域网；手机前台亮屏；PC 浏览器 | 明文 HTTP；必须 PIN + 会话 + 限速 + 空闲停；可用 USB fport 增强 | **主方案** |
| **B. 电脑服务 + 手机预置浏览器** | PC HTTP 服务 + browser1 | 0.5~1 人日（但本机不可用） | PC 防火墙；手机无端口权限问题 | PC 目录 + 浏览器下载目录 | 同一局域网 | PC 服务暴露；需 PIN | **否决**：browser1 不能开 http://IP:端口、无上传/下载 |
| **B′. 电脑服务 + 原生 ArkTS 客户端** | PC HTTP 服务 + 手机原生列表/选择器；`request.uploadFile/downloadFile` | 4~5 人日 | 手机仅 `INTERNET`；无监听端口 | PC 目录；手机 picker + 沙箱；导出用 picker | 同一局域网；PC 常驻 | PC 服务暴露；PIN；可只绑私有网卡 | **备选**：后台/熄屏传输更稳 |
| **C. hdc 脚本兜底** | PowerShell/bash + `hdc file send/recv`；可选 `fport` | 0.5~1 人日 | 无 App 端口；需 USB 调试 + root 写沙箱 | 沙箱/`/data/local/tmp`/公共目录（root） | USB，无需局域网 | 物理连接，风险最低；脚本权限需收紧 | **兜底** |
| **D. WebDAV/SMB** | PC WebDAV/SMB 服务 + 手机客户端 | 10+ 人日或不可行 | WebDAV 需裸 TCP 自实现；SMB 需 NAPI/root | 取决于服务端 | 同一局域网 | 取决于服务端 | **不采用** |

### 3.1 关键维度补充

**端口与权限**

- A：8080/8686 等高位端口；`INTERNET` 是 normal/system_grant，安装即授予；不需要 `KEEP_BACKGROUND_RUNNING`（也不解决挂起）。
- B′：手机不监听端口；只需要 `INTERNET`；上传受限于 cacheDir，下载受限于应用目录。
- C：不涉及端口；但 hdc 需要开发者模式和 USB 调试。
- 80/443：普通 App 一律不可用（`ip_unprivileged_port_start=1024`）。不要设计“手机 80 端口”的产品。

**文件访问范围**

| 位置 | 普通 App 权限 | 说明 |
| --- | --- | --- |
| `context.filesDir` / `cacheDir` | 直接读写 | 沙箱；其他 App/文件管理器看不到 |
| Picker 选中的 URI | 临时读/写授权 | `DocumentViewPicker.select/save`；进程/会话结束后不要缓存 |
| 公共 Download/Documents | 需要 `READ_WRITE_DOWNLOAD_DIRECTORY` / `READ_WRITE_DOCUMENTS_DIRECTORY` | **system_basic + ACL，普通应用不可用** |
| `/data` 全分区 | 仅 root | 预置 miniserve 就是这样，危险 |

**断网/同网段**

- A/B′ 都要求手机和 PC 在同一子网；酒店/公司 Wi-Fi 常开 AP isolation，会直接失败。
- 路由器 DHCP 可能改手机 IP；App 必须每次显示当前 IP，建议路由器做 DHCP 保留。
- 不要求公网；不要引入云中转。

**安全（无鉴权风险）**

- 预置 miniserve：**已经是无鉴权 + root + 全 `/data` + 上传**，是本机当前最大的文件安全风险。
- A：如果偷懒不做鉴权，同网段任何人可读写收件箱；必须默认 PIN + 会话 + 限速 + 空闲停。
- B′：PC 服务同样不能裸奔；只绑私有网卡、随机 PIN、传完即停。
- 明文 HTTP 下 PIN 可被嗅探；敏感文件建议 USB fport 模式或 C。

---

## 4. 推荐方案

### 4.1 选择

**推荐 A 作为产品主方案，C 作为兜底；B′ 作为“必须后台/熄屏传输”时的备选。B 与 D 否决。**

理由：

1. 本机没有可用浏览器，PC 浏览器是唯一成熟的“客户端”，所以让**手机当服务端、PC 当客户端**最顺。
2. 零三方依赖、无需 PC 安装、无需公网，符合“输地址就能传”。
3. 高位端口 + `INTERNET` 权限即可，不碰系统分区/root。
4. 主要短板是后台挂起，用“前台 + 亮屏 + 空闲停”可控；大文件/熄屏交给 C 或 B′。

> 如果明天的目标只是“先有个能用的”，可以先写 C 的 PC 脚本（0.5~1 天）；但产品化仍建议按 A 建工程。

### 4.2 架构（A）

```text
┌────────────────────────────── 手机 (ArkTS Stage, API 11) ──────────────────────────────┐
│  UIAbility / IndexPage                                                                  │
│   ├─ 开始/停止、显示 http://IP:8080、6 位配对码、收件箱、进度、导出                      │
│   ├─ setWindowKeepScreenOn(true)（传输期间）                                             │
│   └─ onBackground: 停止监听、清理连接                                                    │
│                                                                                         │
│  HttpServer (TCPSocketServer, 0.0.0.0:8080)                                             │
│   ├─ 增量 HTTP/1.1 解析（头上限、Content-Length、Range、Cookie）                          │
│   ├─ 路由：GET /（配对页） POST /pair  GET /api/files  GET /f/<id>  PUT /u/<name>       │
│   ├─ 流式下载：fs.read → conn.send（64KB 块，await 背压）                                │
│   ├─ 流式上传：message(ArrayBuffer) → fs.write → 临时文件 → rename                        │
│   └─ 每连接状态机、空闲超时、最大并发、最大文件、磁盘余量检查                             │
│                                                                                         │
│  FileStore                                                                              │
│   ├─ filesDir/inbox（PC→手机落点） + metadata.json                                       │
│   ├─ 手机→PC：DocumentViewPicker.select() 拿 URI，fs.open(uri) 直接流式读                 │
│   └─ 导出：DocumentViewPicker.save({ newFileNames: [...] }) 批量保存到用户选择的位置       │
│                                                                                         │
│  Session / Security                                                                     │
│   ├─ 每次启动随机 6 位码；POST /pair 校验后下发 HttpOnly Cookie                           │
│   ├─ 每 IP 失败限速/锁定；空闲 10 分钟自动停                                             │
│   └─ 只暴露 inbox；basename 清洗；拒绝 ..、绝对路径、控制字符                             │
└─────────────────────────────────────────────────────────────────────────────────────────┘
                                      ▲  HTTP（局域网明文）
                                      │
┌────────────────────────────── PC（Chrome/Edge，无需安装） ──────────────────────────────┐
│  打开 http://192.168.31.175:8080 → 输入 6 位码                                           │
│   ├─ 拖拽/选择文件 → XHR/fetch PUT /u/<name>（带进度）                                   │
│   ├─ 列表 /api/files → 点击下载 GET /f/<id>                                              │
│   └─ 页面 HTML/CSS/JS 全部内嵌在 App rawfile，不依赖 CDN                                 │
└─────────────────────────────────────────────────────────────────────────────────────────┘
```

### 4.3 使用流程

**电脑 → 手机**

1. 手机打开 App，点“开始”，显示 `http://192.168.31.175:8080` 和 6 位码。
2. PC 浏览器打开地址，输入 6 位码。
3. PC 拖入文件；页面逐个 `PUT`，显示进度；手机端写入 `inbox`。
4. 手机端点“导出”，用 `DocumentViewPicker.save({ newFileNames: [...] })` 批量保存到“下载/文档”等用户选择的位置。

**手机 → 电脑**

1. 手机端点“选择文件”，`DocumentViewPicker.select({ maxSelectNumber: N })` 选多个文件。
2. 选中的 URI 出现在 PC 页面列表中（只显示文件名/大小，不暴露路径）。
3. PC 点击下载；手机端用 `fs.open(uri, READ_ONLY)` 流式读取并发送。
4. 传完清除本次会话的文件句柄；URI 授权不持久化。

**USB 安全模式（可选）**

- App 绑定 `127.0.0.1:8080`，PC 执行 `hdc fport tcp:8080 tcp:8080`，浏览器访问 `http://127.0.0.1:8080`。
- 不暴露局域网，适合不可信 Wi-Fi；代价是插 USB + hdc。

### 4.4 安全设计（首版必须）

- 每次启动生成随机 6 位码；`POST /pair` 校验；失败 5 次/分钟锁定；成功后下发 `HttpOnly; SameSite=Strict` 会话 Cookie（128-bit 随机）。
- 所有 `/api/*`、`/f/*`、`/u/*` 校验会话；未配对只允许 `GET /` 和 `POST /pair`。
- 只服务 `filesDir/inbox`；不接受任意路径；文件名 `basename` + 白名单字符；拒绝 `..`、`/`、`\`、NUL。
- 上传限制：默认 2 GB/文件、总空间检查、临时文件 + 原子 rename；失败清理。
- 下载：`Content-Disposition` 用 RFC 5987；不返回目录列表以外的元数据。
- 空闲 10 分钟自动停；App 进后台立即停；页面持续显示“正在共享”，避免忘记关。
- 明示“局域网明文传输，勿在公共 Wi-Fi 使用”；敏感场景用 USB fport。

### 4.5 范围决策

**首版做**

- 手机内 HTTP 服务、PC 网页、6 位码、收件箱、上传/下载、批量导出、进度、空闲停。
- 端口 8080（可改 8081~8090）、前台亮屏、错误提示（端口占用/无 Wi-Fi/磁盘满）。

**首版不做**

- 二维码扫描/生成（依赖/收益不匹配）。
- WebDAV/SMB（API 不支持或需三方库）。
- 后台常驻服务（系统会挂起，不做假承诺）。
- 直接写公共 Download/Documents（无 system_basic 权限）。
- 改造/复用 `com.pengju.minihttpserver`（root + 全 `/data` + 无鉴权）。

### 4.6 M0 空壳验证（明天开工先做，0.5 人日）

必须在投入 UI 前确认以下 6 条，任何一条失败都要调整方案：

1. 新 App 声明 `ohos.permission.INTERNET`，`TCPSocketServer.listen({ address: '0.0.0.0', port: 8080 })` 成功；`netstat` 能看到监听。
2. 同一 Wi-Fi 的 PC `curl http://<手机IP>:8080/` 能拿到响应；手机切后台/熄屏后请求在多久内失败（记录实际行为）。
3. `listen` 80 失败（预期权限/绑定错误，具体错误码以实测为准），确认文档结论。
4. `DocumentViewPicker.select()` 返回 URI，`fs.openSync(uri, READ_ONLY)` 能读前 1 KB；`save({ newFileNames: [...] })` 能批量写多个文件。
5. `DocumentSelectMode.FOLDER` 在本机 FilePicker 1.1.0.300 上是否真的可选目录（API 11 声明支持，但预置版本较旧）；不支持就删掉“选目录”设计。
6. `setWindowKeepScreenOn(true)` 生效；传输 10 分钟不熄屏；退出页面后恢复。

---

## 5. 风险清单

| # | 风险 | 级别 | 影响 | 缓解/验证 |
| --- | --- | --- | --- | --- |
| 1 | 预置 miniserve 无鉴权、root、全 `/data`、可上传 | **严重** | 同网段任意人读写应用数据/系统文件 | 保持 `miniserve.started=0`；不改造、不日常使用；公共 Wi-Fi 禁用 |
| 2 | 手机 App 进后台/熄屏被挂起 | **高** | 传输中断、PC 端超时 | 前台 + `setWindowKeepScreenOn`；空闲停；大文件用 C/B′ |
| 3 | 明文 HTTP + 6 位码可被嗅探/爆破 | **高** | 局域网内文件泄露/被写入 | 随机码、限速、会话、空闲停；敏感场景 USB fport；不在公共 Wi-Fi 用 |
| 4 | 用户以为能直接写“下载”目录 | **高** | 预期落差、找不到文件 | 首版明确“收件箱 + 导出”；用 picker 批量保存；文案说明沙箱 |
| 5 | 80 端口不可用/端口冲突 | 中 | 启动失败 | 默认 8080，探测 8080~8090；错误提示可改端口 |
| 6 | 本机浏览器不能做 B | 中 | 方案选错、返工 | 已在 §2.2/§1.4 否决；若要做 B 必须另立浏览器壳项目 |
| 7 | HTTP 解析/大文件内存/并发 | 中 | OOM、卡死、文件损坏 | 原始 `PUT` 流式写；64KB 块；头/体上限；临时文件 + rename；1 GB 压测 |
| 8 | AP isolation / 不同子网 / IP 变化 | 中 | PC 连不上 | 同网段提示；显示当前 IP；建议 DHCP 保留；可选 mDNS 后续 |
| 9 | Windows 防火墙（B′/PC 服务） | 中 | 手机连不上 PC | 仅私有网络放行；文档写明端口；传完关闭 |
| 10 | 文件名编码/路径穿越 | 中 | 覆盖文件、写入异常 | basename + 白名单；RFC 5987；拒绝 `..`/绝对路径；UTF-8 测试 |
| 11 | 第三方代码许可污染 | 中 | 合规风险 | 只用 Apache-2.0/MIT；GPL/无 LICENSE 不引入；WebDAV 客户端仓库无 LICENSE 已排除 |
| 12 | 长传发热/耗电/文件系统满 | 低 | 传输失败 | 进度/剩余空间检查；分块；失败重试；提示充电/清理 |
| 13 | 依赖预置 FilePicker 的隐藏行为 | 低 | 选择器/批量保存不符合预期 | M0 实测；按 API 11 公开接口降级为单文件保存 |

---

## 6. 里程碑与工时

单人估算；不含“自建浏览器壳”这种另立项目的工作。

| 阶段 | 内容 | 工时 | 交付/验收 |
| --- | --- | --- | --- |
| M0 | 空壳验证：8080 监听、PC curl、80 失败、picker 读/批量存、folder 模式、keep-screen-on | 0.5 人日 | 6 条结论全部有记录；失败项有替代方案 |
| M1 | HTTP 核心：增量解析、路由、`PUT` 流式上传、`GET` 流式下载、错误码、连接管理 | 1.5~2 人日 | PC 上传/下载 100 MB 文件成功；断连不崩溃；头/体上限生效 |
| M2 | UI：开始/停止、IP/端口/6 位码、收件箱列表、进度、keep-screen-on、前后台处理 | 1.5 人日 | 手机可完成一次完整 PC↔手机互传；退后台自动停 |
| M3 | 文件：picker 多选、批量导出、文件名清洗、磁盘余量、临时文件原子落盘 | 1 人日 | 中文/emoji 文件名正确；`..` 被拒；批量导出成功 |
| M4 | 安全：PIN 会话、限速/锁定、空闲停、只暴露 inbox、日志脱敏 | 0.5~1 人日 | 错码 5 次锁定；未配对无法列目录/下载；10 分钟空闲自动停 |
| M5 | 实机联调：Chrome/Edge、1 GB 大文件、多文件、Wi-Fi 抖动、熄屏、并发、发热 | 1.5 人日 | 验收清单通过；已知问题记录 |
| M6 | 文档/打包/回滚说明 | 0.5 人日 | README、端口/权限说明、USB 模式说明、故障排查 |
| **合计** |  | **7~9 人日** | MVP（M0~M2）约 **3.5~4.5 人日** |

**验收清单（建议）**

- PC Chrome/Edge 拖入 1 GB 文件，手机收件箱可见、校验和一致；进度正常。
- 手机选 20 张照片，PC 全部下载，文件名/大小一致。
- 中文、空格、emoji 文件名不报错；`../x`、绝对路径被拒。
- 错码 5 次锁定；未配对访问 `/api/files` 返回 401/403。
- 空闲 10 分钟自动停；App 退后台立即停；重新开始生成新码。
- 8080 被占用时能提示并换端口；80 不使用。
- 熄屏/后台行为与文档一致，不出现“假在线”。

---

## 7. 参考链接

### 7.1 官方文档 / 代码（API 11 基线）

| 主题 | 链接 | 说明 |
| --- | --- | --- |
| TCP Socket 开发指导 | https://gitcode.com/openharmony/docs/blob/OpenHarmony-4.1-Release/zh-cn/application-dev/network/socket-connection.md | TCP/UDP 客户端与服务端示例 |
| `@ohos.net.socket` API | https://gitcode.com/openharmony/docs/blob/OpenHarmony-4.1-Release/zh-cn/application-dev/reference/apis-network-kit/js-apis-socket.md | `TCPSocketServer.listen`、`INTERNET` 权限 |
| 普通权限清单 | https://gitcode.com/openharmony/docs/blob/OpenHarmony-4.1-Release/zh-cn/application-dev/security/AccessToken/permissions-for-all.md | `INTERNET`、`KEEP_BACKGROUND_RUNNING`、`GET_NETWORK_INFO` 均为 normal/system_grant |
| 系统应用权限清单 | https://gitcode.com/openharmony/docs/blob/OpenHarmony-4.1-Release/zh-cn/application-dev/security/AccessToken/permissions-for-system-apps.md | `READ_WRITE_DOWNLOAD_DIRECTORY` 为 system_basic |
| 长时任务 | https://gitcode.com/openharmony/docs/blob/OpenHarmony-4.1-Release/zh-cn/application-dev/task-management/continuous-task.md | `DATA_TRANSFER` 仍会挂起进程 |
| 应用文件上传下载 | https://gitcode.com/openharmony/docs/blob/OpenHarmony-4.1-Release/zh-cn/application-dev/file-management/app-file-upload-download.md | upload 仅 cacheDir；download 仅应用目录 |
| 选择用户文件 | https://gitcode.com/openharmony/docs/blob/OpenHarmony-4.1-Release/zh-cn/application-dev/file-management/select-user-file.md | `DocumentViewPicker.select` |
| 保存用户文件 | https://gitcode.com/openharmony/docs/blob/OpenHarmony-4.1-Release/zh-cn/application-dev/file-management/save-user-file.md | `DocumentViewPicker.save` |
| `@ohos.file.picker` API | https://gitcode.com/openharmony/docs/blob/OpenHarmony-4.1-Release/zh-cn/application-dev/reference/apis-core-file-kit/js-apis-file-picker.md | `DocumentSaveOptions.newFileNames`、`DocumentSelectMode.FOLDER` |
| `@ohos.request` API | https://gitcode.com/openharmony/docs/blob/OpenHarmony-4.1-Release/zh-cn/application-dev/reference/apis-basic-services-kit/js-apis-request.md | 上传/下载任务 |
| hdc 使用 | https://gitcode.com/openharmony/docs/blob/OpenHarmony-4.1-Release/zh-cn/application-dev/dfx/hdc.md | `file send/recv`、`fport/rport` |

### 7.2 开源项目评估（均已克隆到临时目录，未加入本仓库）

| 项目 | 许可证 | API / 平台 | 可复用性 | 结论 |
| --- | --- | --- | --- | --- |
| `openharmony/applications_filepicker`（4.1 分支） | Apache-2.0 | compileSdk 10 / compatible 9 | 系统 FilePicker；`FILE_ACCESS_MANAGER` 等系统权限 | 只作选择器交互/URI 授权参考，不能作为普通应用直接复用 |
| `openharmony/applications_app_samples` → `Connectivity/UploadAndDownLoad`（4.1 分支） | Apache-2.0 | compileSdk 10 / compatible 10 | `request.uploadFile/downloadFile`、后台任务、picker 选文件 | B′ 的代码参考；注意其部分实现可能已用更新 API |
| `openharmony/filemanagement_user_file_service`（4.1 分支） | Apache-2.0 | 系统服务 | FileAccessFramework、公共文件 URI 授权模型 | 只作原理参考，不能嵌入普通 App |
| `Explore-In-HMOS/how-to-create-tcp-server` | MIT | HarmonyOS SDK 5.1(18) | 单个 59 行 `http_server.ts`，TCP + 极简 HTTP 解析 | 思路参考；无流式/大文件/并发，不能直接用于 API 11 工程 |
| `svenstaro/miniserve` | MIT | Rust，上游 0.35.0；设备为 0.27.1 | 独立 HTTP 文件服务器，支持上传/鉴权 | 不能嵌入 ArkTS；设备上的 root + `/data` + 无鉴权配置不可取 |
| `qy2001/qy2001-webdav_client_harmonyos` | **无 LICENSE** | target 26 / compatible 12，基于 `rcp` | WebDAV 客户端（约 46 KB / 19 个 ets/ts） | **不可用**：无许可证、API 12+、rcp 不在 API 11 |
| `kazuhikoarase/qrcode-generator` | MIT | JS/TS | 二维码生成 | 仅编码；首版不需要，后续可选 |
| `SomethingNotReal/Harmonyos-NetFile-Project` | 无 | 空仓库（仅 README） | 无 | 忽略 |

> 克隆位置：`C:\Users\21996\AppData\Local\Temp\opencode\filetransfer-research\`（临时目录，可随时删除）。GitHub 直连失败时经 `gh-proxy.com` 克隆；OpenHarmony 仓库经 `gitcode.com` 镜像获取。

---

## 附录 A：本次只读探查命令（可复现）

```powershell
$hdc = "D:\ohos-tools\sdk\openharmony\toolchains\hdc.exe"

# 设备/包信息
& $hdc shell "param get const.product.model; param get const.ohos.apiversion"
& $hdc shell "bm dump -n com.pengju.minihttpserver"
& $hdc shell "bm dump -n com.ohos.filepicker"
& $hdc shell "bm dump -n com.ohos.UserFile.ExternalFileManager"

# 启动预置 UI（只读动作）
& $hdc shell "aa start -a EntryAbility -b com.pengju.minihttpserver"

# 观察服务（点击“打开服务”后）
& $hdc shell "netstat -tlnp 2>/dev/null | head -15"
& $hdc shell "ps -ef | grep miniserve | grep -v grep"
& $hdc shell "cat /vendor/etc/init/http_server.cfg"

# PC 侧验证（无鉴权/目录）
curl.exe -sI http://192.168.31.175/
curl.exe -s "http://192.168.31.175/?sort=name"

# 端口策略
& $hdc shell "cat /proc/sys/net/ipv4/ip_unprivileged_port_start"

# 恢复：关闭预置服务（本次验证后已执行）
& $hdc shell "param set miniserve.started 0"
```

本次对设备的写操作仅有：

- `aa start` 预置 App；
- 通过 UI 打开预置服务（用于确认端口/身份/参数）；
- `param set miniserve.started 0` 恢复关闭状态；
- 向宿主机拉取 HAP 副本用于离线分析。

未安装/卸载/重启/修改系统设置，未实际上传文件到 `/data`。

## 附录 B：HAP/开源分析产物

| 产物 | 路径（临时目录） | 用途 |
| --- | --- | --- |
| minihttp HAP | `...\filetransfer-research\minihttpserver\HttpServer.hap` | 包结构、`module.json`、`.abc` 反汇编 |
| minihttp 反汇编 | `...\filetransfer-research\minihttpserver\modules.pa` | 确认 `systemParameter.setSync('miniserve.started', ...)` |
| browser1 HAP | `...\filetransfer-research\Browser.hap` | 确认无 `onShowFileSelector`/`onDownloadStart` |
| 设备权限清单 | `...\filetransfer-research\permission_definitions.json` | 本机权限定义补充 |
| 开源克隆 | `...\filetransfer-research\{applications_filepicker,user_file_service,app-samples,how-to-create-tcp-server,miniserve-upstream,webdav-client-ohos,qrcode-generator}` | 许可证/API/代码评估 |

---

## Spike 实测（2026-11-17）

- 目的：验证本文 §4.6 M0 第 1 条——普通（非系统、test-CA 签名）应用能否用 `TCPSocketServer` 在 `0.0.0.0:8080` 监听。
- 工程与签名同 [APP-BROWSER.md](APP-BROWSER.md) 的 spike：`bundleName=com.local.spike`，仅声明 `ohos.permission.INTERNET`（normal），compileSdk 10 / 设备 API 11，普通应用，`hdc install -r` 成功。
- API 差异：API 11 的 `TCPSocketServer` 没有 `bind()`；服务端方法名是 `listen(address: NetAddress): Promise<void>`（`bind()` 属于 `TCPSocket`/UDP 客户端）。实际调用改为 `server.listen({ address: '0.0.0.0', port: 8080, family: 1 })`，语义等价（绑定并开始监听）。

实测现象：

| 检查 | 证据 | 结果 |
| --- | --- | --- |
| 创建服务端 | `socket.constructTCPSocketServerInstance()` 未抛异常 | 通过 |
| 监听 8080 | `TCP listen OK 0.0.0.0:8080`（`listen` Promise resolve；无 `201` / `2303198` 等错误码） | 通过 |
| 内核监听表 | `netstat -tlnp`：`tcp 0 0 0.0.0.0:8080 0.0.0.0:* LISTEN 577/com.local.spike`；`/proc/net/tcp` 中 `00000000:1F90 ... 0A`，uid `20010052` | 通过 |
| 宿主机连接 | Windows `TcpClient` 连 `192.168.31.175:8080` 成功；应用日志 `TCP connect port=8080 clientId=1` | 通过 |
| 18080 回退 | 8080 一次成功，未触发回退；页面保留 18080 按钮但未执行 | 未使用 |

- 权限与端口：设备 `/proc/sys/net/ipv4/ip_unprivileged_port_start=1024`，8080 高于阈值，无需 `CAP_NET_BIND_SERVICE`；`INTERNET` 安装即授予，实际未出现权限拒绝。
- 结论：**M0 第 1 条成立**。普通 test-CA 应用可在 `0.0.0.0:8080` 成功 bind + listen，并接受同网段主机连接；§4.1 推荐的“手机内 HTTP 服务”通道不需要 root 或系统签名。注意文档与代码里应使用 `listen()`，不存在服务端 `bind()`。
- 清理：`hdc uninstall com.local.spike` 成功；`bm dump -a | grep spike` 无结果，`/data/app/el2/100/base/com.local.spike` 不存在，进程与 8080 监听均消失；默认输入法已确认恢复为 `com.local.homeime`（`hidumper -s InputMethodService -a -a` 中 `isCurrentIme=true`）。

---

## 核实修正

> 2026-11-17 追加。依据：API 11 SDK `.d.ts`（4.1.7.5）+ OpenHarmony 4.1 官方文档 + Linux 内核文档；详见 [VERIFY-BROWSER-TRANSFER.md](VERIFY-BROWSER-TRANSFER.md)。`## Spike 实测` 已覆盖 8080/`0.0.0.0`，以下只列需改动处。

1. **§0/§2.1 “长时任务只提升优先级，系统仍会挂起应用进程” → 改为**：官方原文是“仅提升应用进程优先级、降低被终止概率，但依然可能终止”，并要求真实执行对应类型任务，否则会被系统管控（4.1 `continuous-task.md`）。结论“不能当后台常驻服务器”不变。
2. **§3.1 “不需要 `KEEP_BACKGROUND_RUNNING`（也不解决挂起）” → 保留结论，措辞同步**改为“不解决被终止/管控”。
3. **§2.2 “uploadFile/downloadFile 系统服务代理，可在后台继续” → 补限制**：任务确由系统服务代理，但 4.1 `js-apis-request.md` 明示“应用处于后台时不支持回调”；只有 `request.agent` 的 `Mode.BACKGROUND` 有“后台任务不受影响”的明确表述。B′ 应写成“传输可继续、后台不能依赖回调更新 UI”。
4. **§2.1 接口表 → 补一句**：`TCPSocketServer` 没有 `bind()`，`listen(NetAddress)` 内部完成 bind+listen（`@ohos.net.socket.d.ts:2978`；Spike 已说明）。`bind()` 仅属于 `TCPSocket` 客户端（`:518/540`）。
5. **§2.1 错误码 → 补全**：另含 `401`、`2300002`、`2303111`、`2303199`；端口占用固定 `2303198`（`socket.d.ts:2986-2992`）。
6. **§2.1 绑定地址 → 更新状态**：官方示例只写具体网卡 IP，`0.0.0.0` 无示例；Spike 已实测 `0.0.0.0:8080` 成功，可把“待验证”改为“已实测”。
7. **§2.1 “`TLSSocketServer`（API 11 可用）” → 补版本**：`@since 10`，非 API 11 新增。
8. **§3.1/§4.2 URI 权限 → 细化**：`DocumentViewPicker.select()` 返回**只读**授权；`save()` 返回**读写**授权；`FILE_ACCESS_PERSIST` = `system_basic + system_grant + ACL`（4.1 `permissions-for-system-apps.md`），普通应用不能持久化 URI，“会话内用完即弃”是硬约束而非选择。
9. **§1.4/§3.1 端口依据 → 补源码/内核依据**：1024 来自 Linux `ip_unprivileged_port_start` 默认值（`Documentation/networking/ip-sysctl.rst`）；OpenHarmony 4.1 `startup_init/services/etc/init.cfg` 集中设置启动期 sysctl，但**不含**该键；API 文档只声明端口 0~65535（0=系统分配），不承诺低端口。
10. **§2.2 上传限制 → 加强**：官方明文“仅支持上传 cacheDir 下的文件”，且 `File.uri` 只支持 `internal://cache/`，因此“picker → cacheDir 复制”是必需步骤。
11. **§1.4/§2.2 “browser1 不能开 http://IP:端口” → 结论成立，补版本**：3.2/4.0 分支无条件补 `https://`（设备 1.0.15 属该代），4.1 分支已修复为“无 scheme 才补”。
