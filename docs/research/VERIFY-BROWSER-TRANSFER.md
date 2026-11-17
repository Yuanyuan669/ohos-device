# 浏览器 / TCP Server / 文件上传 结论核实（源码 + 官方文档级）

- 核实日期：2026-11-17
- 核实对象：`docs/research/APP-BROWSER.md`、`docs/research/APP-FILETRANSFER.md`
- 核实边界：**不碰设备**。只做 SDK `.d.ts`、OpenHarmony 4.1 官方文档（`OpenHarmony-4.1-Release` 分支）、上游示例源码、Linux 内核文档的静态比对
- 主证据 SDK：`D:\ohos-tools\sdk\openharmony-4.1-Release`（`ets/oh-uni-package.json`：`apiVersion=11`，`version=4.1.7.5`）
- 对照 SDK：`D:\ohos-tools\sdk\10`（`apiVersion=10`，`version=4.0.10.13`；用于 API 10→11 增量比对，属 4.0 Release SDK，API 级别比较有效）
- 证据等级：**A**=SDK 声明/源码可直接引用；**B**=官方文档明文；**C**=间接推断/需实机确认；**D**=未找到依据
- 与设备实测的关系：两份文档已于 2026-11-17 追加 `## Spike 实测`（设备侧，不属于本报告方法）。本报告只在与其重叠处引用该实测作为 C 级佐证；若冲突以设备实测为准

---

## 0. 结论速览（被推翻/被加强的原判断）

| # | 原文档判断 | 核实结果 | 等级 |
| --- | --- | --- | --- |
| 1 | `@kit.ArkWeb` 不可用（12+） | **推翻**：4.1.7.5 SDK 已提供 `ets/kits/@kit.ArkWeb.d.ts`，等价于 `@ohos.web.webview` 的别名 | A |
| 2 | API 11 没有真正的 incognito 隔离 | **推翻**：`WebOptions.incognitoMode`（since 11）+ `WebviewController.isIncognitoMode()` + Cookie/Geolocation 的 `incognito?` 参数 | A |
| 3 | Web 调试只能 debug 构建开启 | **未找到依据**：SDK 与 4.1 文档均未限制构建类型 | A/B |
| 4 | API 11 无跨进程下载续传保证 | **部分推翻**：有 `serialize()/deserialize()` + `WebDownloadManager.resumeDownload()`（11），但下载不由系统服务托管 | A |
| 5 | Web 下载可交给 `@ohos.request` | **不成立**：两者无集成；`request` 只能独立按 URL 下载直链 | A/B |
| 6 | 普通应用使用 Web 组件有“系统应用限制”风险 | **加强为“无 API 层限制”**：`web.d.ts`/`@ohos.web.webview.d.ts` 均 0 处 `@systemapi`、0 处 `@permission`；默认 syscap 含 `Web.Webview.Core`；同目录 Spike 已用普通 test-CA 应用实测通过 | A/C |
| 7 | TCP Server 需 `bind` 再 `listen`（任务前提） | **前提不成立**：`TCPSocketServer` **没有** `bind()`，只有 `listen(NetAddress)`（内部完成 bind+listen）；`bind()` 属客户端 `TCPSocket`。文档正文未写 bind，但建议在接口表补一句，避免误读 | A |
| 8 | 长时任务 DATA_TRANSFER“仍会挂起进程” | **措辞需改**：官方是“提升优先级、降低被终止概率，仍可能终止”，且需真实执行对应任务，否则被管控 | B |
| 9 | 普通应用不能监听 1024 以下端口 | **加强**：Linux 内核 `ip_unprivileged_port_start` 默认 1024；OpenHarmony `init.cfg` 未改写该键 | A/B/C |
| 10 | Picker URI 不能持久化 | **加强**：`FILE_ACCESS_PERSIST` = `system_basic` + `system_grant` + ACL（11），普通应用确实拿不到 | B |
| 11 | 示例浏览器 `loadUrl()` 强制 https | **需限定版本**：3.2/4.0 分支无条件补 `https://`；4.1 分支已修复为“无 scheme 才补” | A（上游源码） |
| 12 | 示例浏览器 README 过期，代码已用 deviceInfo | **需限定版本**：仅 master 用 `@ohos.deviceInfo`；3.2/4.0/4.1 分支仍是 `@ohos.systemparameter` | A（上游源码） |

---

## 1. Web / ArkWeb

### 1.1 普通应用可用性

| 结论 | 依据 | 影响 |
| --- | --- | --- |
| `Web` 组件与 `WebviewController` 是**公开 API**，不是系统接口 | `ets\component\web.d.ts`：全文 `@systemapi` 计数 = **0**；`ets\api\@ohos.web.webview.d.ts`：`@systemapi` = **0**，`@permission` = **0** | 普通 CA 签名应用可直接 import/使用；“必须系统应用”的假设不成立 |
| Web 能力在默认设备能力集内 | `ets\api\device-define\default.json:182` 含 `SystemCapability.Web.Webview.Core` | 默认形态设备应具备该 syscap；同目录 Spike 已在设备上确认 |
| 加载网络页面只需 `ohos.permission.INTERNET` | 4.1 文档 `web/web-page-loading-with-web-components.md` 第 7 行：“页面加载过程中，若涉及网络资源获取，需要配置 ohos.permission.INTERNET 权限” | 权限清单与普通应用一致，无额外系统权限 |
| 引擎由系统提供，应用只声明权限 | 既有机型事实（`com.ohos.nweb` + `libweb_engine.so`）见 APP-BROWSER.md §1.2；SDK 中无打包引擎的要求 | 包体小；Spike 已证明普通 test-CA 应用可加载引擎 |

> 说明：`@ohos.web.webview.d.ts` 里出现的 36 处 “permission” 是普通英文单词/注释，`@permission` 注解为 0，不能据此认为有权限要求。

> 说明：原担忧“此镜像的 Web 引擎供给（`nwebspawn`/`com.ohos.nweb`）是否对普通应用生效”已由同目录 `## Spike 实测` 用普通 test-CA 应用验证通过（`isSystemApp=false`，rawfile 渲染、JS、`onConsole`、远程 https 均通过）；本报告只负责确认 API 层无系统限制。

### 1.2 `$rawfile` 作为 `src`

| 结论 | 依据 | 影响 |
| --- | --- | --- |
| `Web({ src: ... })` 支持 `Resource`，即 `$rawfile(...)` | `ets\component\web.d.ts:3498` `src: string \| Resource;`（`WebOptions`）；`@ohos.web.webview.d.ts:2457` `loadUrl(url: string \| Resource, headers?)` | 本地主页/离线页可直接用 `$rawfile`，无需 `file://` |
| 官方示例即用 `$rawfile` | 4.1 文档 `web/web-page-loading-with-web-components.md`：`Web({ src: $rawfile("local.html"), controller })`；`controller.loadUrl($rawfile("local1.html"))` | 方案可行，属官方推荐路径 |
| `fileAccess(false)` 不影响 `$rawfile` | 4.1 文档 `reference/apis-arkweb/ts-basic-components-web.md`：`fileAccess` 默认 `true`，“默认启用 `$rawfile` …rawfile 路径的文件不受该属性影响” | 安全收紧（关 fileAccess）与本地主页可同时成立 |

### 1.3 `onErrorReceive` / `onConsole`

| 结论 | 依据 | 影响 |
| --- | --- | --- |
| 两个回调均为公开 API，since 8 | `web.d.ts:4687` `onConsole(callback: (event?: { message: ConsoleMessage }) => boolean)`（首个 `@since 8`）；`web.d.ts:4725` `onErrorReceive(callback: (event?: { request: WebResourceRequest; error: WebResourceError }) => void)`（`@since 8`） | 可做错误页与前端日志转发 |
| `ConsoleMessage` 提供 message/sourceId/lineNumber/level | `web.d.ts:2475` `declare class ConsoleMessage`；`2520 getMessage()`、`2536 getSourceId()`、`2552 getLineNumber()`、`2569 getMessageLevel()` | 日志可结构化，不必解析字符串 |
| 错误码只有裸数字，无枚举 | `web.d.ts:3131` `getErrorCode(): number`；4.1 SDK 无 `@ohos.web.netErrorList.d.ts` | 原文档“-2 连接失败、-6 找不到主机”**未找到官方依据**，不应硬编码语义，只展示数字+描述 |

### 1.4 下载接口

| 结论 | 依据 | 影响 |
| --- | --- | --- |
| Web 页面下载是一套**独立于 `@ohos.request`** 的 API，API 11 才引入 | `@ohos.web.webview.d.ts:3602 setDownloadDelegate()`、`:3613 startDownload(url)`、`:3931 class WebDownloadItem`、`:4088 class WebDownloadDelegate`、`:4128 class WebDownloadManager`；API 10 SDK 中均不存在 | 原文档“下载可用（11）”成立，且是 11 的新增能力 |
| `WebDownloadItem` 能力齐全 | `getGuid/getCurrentSpeed/getPercentComplete/getTotalBytes/getState/getLastErrorCode/getMethod/getMimeType/getUrl/getSuggestedFileName/start(path)/cancel/pause/resume/getReceivedBytes/getFullPath/serialize/deserialize`（`@ohos.web.webview.d.ts:3931-4081`） | 进度、暂停/继续、错误码、落盘路径都可做 |
| 落盘只能是应用可写路径，官方示例用沙箱 | 4.1 文档 `web/web-download.md`：`start("/data/storage/el2/base/cache/web/" + getSuggestedFileName())`，并注明未指定路径时默认 `/data/storage/el2/base/cache/web/` | 原文档“不能直接写公共 Download”成立 |
| 与 `@ohos.request` **无集成** | `@ohos.request.d.ts` 全文无 `Web` 相关符号；4.1 文档 `js-apis-request.md` 中 “Web” 出现 0 次；`request.downloadFile(context, { url, filePath })` 是独立任务（`@ohos.request.d.ts:674`，`DownloadConfig` 在 776，`filePath?` 在 895） | 页面触发的下载不能“转交系统下载服务”；只能在 `onDownloadStart` 拿到 `url` 后，自行调 `request.downloadFile` 下载**可 GET 的直链**（可在 header 里手动补 Cookie/Referer，但无法覆盖 POST/`data:`/`blob:`） |
| 下载可跨会话恢复，但**不是**后台下载服务 | `serialize()/static deserialize()`（`:4070/:4080`）+ `WebDownloadManager.setDownloadDelegate()/resumeDownload()`（`:4136/:4145`），注释为 “resume failed or canceled downloads” | 原文档“API 11 无公开的跨进程续传保证”需修正；但下载进程仍随应用，应用被杀后不能像系统下载服务那样继续 |

### 1.5 权限 / 系统应用限制

| 检查项 | 结果 | 依据 |
| --- | --- | --- |
| `@systemapi` 注解 | Web 组件 0 处；`@ohos.web.webview` 0 处 | 两份 `.d.ts` 全文计数 |
| `@permission` 注解 | `@ohos.web.webview` 0 处 | 同上 |
| 权限来源 | 只有“加载网络资源需 `INTERNET`”的文档要求 | `web-page-loading-with-web-components.md` |
| 系统应用专属能力 | 本项目用到的导航/下载/Cookie/上传/新窗口/同层渲染均未见 `@systemapi` | 同上 |
| 默认 syscap | `Web.Webview.Core` 在 `device-define/default.json` | A |

> 唯一无法用源码/文档排除的是“此镜像的 Web 引擎供给（`nwebspawn`/`com.ohos.nweb`）是否对普通应用生效”。该点已由同目录 `## Spike 实测`（普通 test-CA 应用，`isSystemApp=false`）验证通过；本报告不重复设备验证。

### 1.6 Web 组件 API 10 → 11 差异（按 SDK 成员名差集）

新增 `WebAttribute` 成员（API 10 SDK 无）：

| 成员 | 位置 | 用途 |
| --- | --- | --- |
| `enableNativeEmbedMode` | `web.d.ts:6213` | 同层渲染开关 |
| `onNativeEmbedLifecycleChange` | `:6223` | 同层渲染生命周期 |
| `onNativeEmbedGestureEvent` | `:6233` | 同层渲染手势 |
| `onNavigationEntryCommitted` | `:6166` | 导航提交回调 |
| `onSafeBrowsingCheckResult` | `:6156` | 安全浏览结果 |
| `javaScriptOnDocumentStart` | `:6175` | 文档开始注入 JS |
| `javaScriptOnDocumentEnd` | `:6184` | 文档结束注入 JS |
| `layoutMode` | `:6193` | 布局模式 |
| `nestedScroll` | `:6203` | 嵌套滚动 |
| `overScrollMode` | `:4176`（11 版重写） | 过滚动模式 |
| `onContextMenuHide` | `:5301` | 上下文菜单关闭 |

新增 `WebOptions` 字段：`incognitoMode?: boolean`（`:3541`）。

新增控制器/管理类能力（`@ohos.web.webview.d.ts`，API 10 无）：

- 下载全家桶：`setDownloadDelegate`、`startDownload`、`WebDownloadItem/Delegate/Manager`、`WebDownloadState/ErrorCode`
- 安全浏览：`enableSafeBrowsing`、`isSafeBrowsingEnabled`
- Cookie 同步族：`fetchCookie(Sync)`、`configCookie(Sync)`、`clearAllCookies(Sync)`、`clearSessionCookie(Sync)`
- 其他：`isIncognitoMode`、`getSecurityLevel`、`postUrl`、`createWebPrintDocumentAdapter`、`setConnectionTimeout`（`setHttpDns` 在 API 10 已存在，不算新增）

原有且 11 仍可用（非新增）：`loadUrl/refresh/backward/forward`、`onErrorReceive/onHttpErrorReceive/onConsole`、`onShowFileSelector`、`multiWindowAccess/onWindowNew`、`onInterceptRequest/onLoadIntercept`、`serializeWebState/restoreWebState`、`setWebDebuggingAccess`。

---

## 2. TCP Server

### 2.1 接口与参数

| 结论 | 依据 | 影响 |
| --- | --- | --- |
| 服务端构造：`socket.constructTCPSocketServerInstance()`，since 10 | `@ohos.net.socket.d.ts:104`；4.1 文档 `js-apis-socket.md` “TCPSocketServerInstance 10+” | API 11 可用 |
| `TCPSocketServer` **没有 `bind()`** | `@ohos.net.socket.d.ts:2978` 接口成员只有：`listen`（2996/3014）、`getState`（3026/3037）、`setExtraOptions`（3050/3063）、`on/off('connect')`（3072/3081）、`on/off('error')`（3090/3099）、`close`（3154/3165） | 任务前提中的“服务端 bind”不成立；`bind()` 是 `TCPSocket`（客户端）接口（`:518/540`）。文档正文未写 bind，Spike 已补充说明 |
| `listen` 参数为 `NetAddress { address, family?, port? }` | `@ohos.net.connection.d.ts:1579`；`port` 注释“0~65535”，`family` 1=IPv4/2=IPv6，默认 1 | `port: 0` 表示由系统分配（文档亦如此说明） |
| 权限只要 `ohos.permission.INTERNET` | `socket.d.ts:2983/3001` `@permission ohos.permission.INTERNET` + `@throws 201`；4.1 文档 `js-apis-socket.md` “需要权限：ohos.permission.INTERNET” | `INTERNET` = normal + system_grant（4.1 `permissions-for-all.md`），安装即授予 |
| 错误码（listen） | 401 Parameter error；201 Permission denied；2300002 System internal error；2303109 Bad file number；2303111 Resource temporarily unavailable；2303198 Address already in use；2303199 Cannot assign requested address（`socket.d.ts:2986-2992`） | 原文档只列 3 个，需补全；端口占用判断用 `2303198` |
| 连接与收发 | `on('connect', Callback<TCPSocketConnection>)`（`:3072`）；`TCPSocketConnection.on('message')`（`:2917`）→ `SocketMessageInfo { message: ArrayBuffer, remoteInfo }`（`:3332`）；`send({ data, encoding? })`（`:2844/2856`）；`getRemoteAddress()`（`:2889/2900`）；`close()`（`:2867/2877`） | 与现有方案一致，可支撑手写 HTTP/1.1 |
| 绑定 `0.0.0.0` | 接口层无限制，但官方示例均写具体网卡 IP（`192.168.xx.xxx`），文档未给 `0.0.0.0` 示例；同目录 Spike 已实测 `0.0.0.0:8080` 成功 | 官方文档无示例，但设备实测可行（C）；产品 M0 建议复测 |
| `TLSSocketServer` | API 10 SDK 已存在（`@ohos.net.socket.d.ts:3356`，`@since 10`） | 原文档“API 11 可用”成立，但不是 11 新增 |

### 2.2 监听非特权端口（1024+）是否受限

| 结论 | 依据 | 等级 |
| --- | --- | --- |
| 1024 以下端口需要 root 或 `CAP_NET_BIND_SERVICE`；普通应用不可绑 | Linux 内核文档 `Documentation/networking/ip-sysctl.rst`：`ip_unprivileged_port_start` “Privileged ports require root or CAP_NET_BIND_SERVICE in order to bind to them”，“Default: 1024” | A（内核/官方） |
| OpenHarmony 未改写该 sysctl（未找到显式设置） | `startup_init`（OpenHarmony-4.1-Release）`services/etc/init.cfg` 集中设置启动期 sysctl：`ping_group_range`（L51）、`rmem_max`（L55）、`fwmark_reflect`（L57/58）、`tcp_fwmark_accept`（L59）等，但**不含** `ip_unprivileged_port_start`；全文件 210 行，`unprivileged` 计数 0 | B/C（源码检索 + 未找到反例） |
| API 文档不承诺低端口 | 4.1 `js-apis-socket.md` 仅声明端口范围 0~65535、0 为系统分配，无“低端口可用性”表述 | B |
| 本机实测值为 1024 | APP-FILETRANSFER.md §1.1 已记录 `/proc/sys/net/ipv4/ip_unprivileged_port_start = 1024` | C（既有实测，本次未复测） |

**结论**：普通应用使用 **≥1024** 端口是“内核默认 + 既有实测”的组合结论，不是 API 契约；产品应默认 8080 等高位端口，并在 M0 实测 80 的失败行为（`listen` 低端口预期返回 201/2303199 一类错误，本次无实测数据）。同目录 Spike 已实测 8080 成功、IPC 连通。

### 2.3 前台服务 / 长时任务（`KEEP_BACKGROUND_RUNNING` + `backgroundTaskManager`）

| 结论 | 依据 | 影响 |
| --- | --- | --- |
| `KEEP_BACKGROUND_RUNNING` 是普通权限 | 4.1 `permissions-for-all.md`：`ohos.permission.KEEP_BACKGROUND_RUNNING`，**权限级别 normal / 授权方式 system_grant / 起始版本 8** | 可声明，安装即授予；但“能申请”不等于“能常驻” |
| `startBackgroundRunning` 要求该权限 | `@ohos.resourceschedule.backgroundTaskManager.d.ts:120/143` `@permission ohos.permission.KEEP_BACKGROUND_RUNNING`；`:138/161` API；`@systemapi` = 0 | 公开 API，Stage 模型需在 `module.json5` 的 `abilities[].backgroundModes` 配 `dataTransfer`（4.1 `continuous-task.md`） |
| `DATA_TRANSFER` 的真实语义 | 4.1 `continuous-task.md`：“对于 DATA_TRANSFER（数据传输）的长时任务，系统仅会提升应用进程的优先级，降低系统终止应用进程的概率。但依然可能终止应用进程。如果实际上传下载等对应功能，需要调用系统上传下载代理接口托管给系统执行。” | **不能**当后台常驻服务器；原文档“仍会挂起”应改为“仍可能被终止/管控” |
| 同一 UIAbility 同时只允许 1 个长时任务；未执行对应任务会被管控 | 4.1 `continuous-task.md` “约束与限制” | 用 `DATA_TRANSFER` 伪装“监听服务”有被管控风险，不建议 |
| 维持 TCP 服务的可行做法 | 无官方“后台常驻监听”能力；只能“前台 + `setWindowKeepScreenOn(true)` + 空闲停” | 与 APP-FILETRANSFER.md 结论一致，但机制描述需修正 |
| `setWindowKeepScreenOn` 可用 | `@ohos.window.d.ts:3165`（Promise）/`:3202`（callback）；`setKeepScreenOn` 已 `@deprecated`（`:3117/3128`） | 用新接口，API 11 可编译 |

---

## 3. 文件与上传

### 3.1 `@ohos.request` 上传

| 结论 | 依据 | 影响 |
| --- | --- | --- |
| 普通应用可上传到 PC 的 HTTP 服务 | `@ohos.request.d.ts:756` `uploadFile(context, config)`；`UploadConfig`：`url: string`（`:1812`）、`header: Object`、`method: string`（必填，示例 POST）、`files: Array<File>`（`:1895`）；仅要求 `INTERNET` | 可行；PC 侧用 multipart/form-data 接收 |
| **只能上传 cacheDir 下的文件** | 4.1 `file-management/app-file-upload-download.md`：“当前上传应用文件功能，仅支持上传应用缓存文件路径（cacheDir）下的文件”；`File.uri` 注释只支持 `internal` 协议、`internal://cache/`（`request.md` / `@ohos.request.d.ts:1660` 附近） | picker 选中文件必须先复制到 `cacheDir`（B′ 方案成立） |
| `downloadFile` 只能落到应用目录 | 4.1 同文档：“当前仅支持下载资源文件到应用文件目录”；`DownloadConfig.filePath?`（`:895`） | 导出仍需 picker |
| 是否由系统服务代理 | 4.1 `js-apis-request.md` 第 3 行：“request 模块主要为应用提供上传下载文件、后台代理等功能” | 传输任务本身可继续；但注意下条 |
| 后台回调限制 | `js-apis-request.md` 多处注明：“应用处于后台时，为满足功耗要求，不支持调用此接口进行回调” | 不能依赖回调在后台刷新 UI；`request.agent` 的 `BACKGROUND` 模式才明确“后台任务不受影响”（`request.md` “Mode 10+” 表） |
| `request.agent` 可用性 | `namespace agent`（`@ohos.request.d.ts:2255`），`Action` since 10、`Mode` since 10、`Config` since 11、`create` since 11 | API 11 可用；比 legacy 接口更完整（进度/重试/网络约束） |

### 3.2 Web 下载与 `@ohos.request` 的关系

| 结论 | 依据 | 影响 |
| --- | --- | --- |
| 无“Web 下载 → 系统下载服务”的直连 | `@ohos.request` 无 `Web` 符号；Web 下载文档只用 `setDownloadDelegate` | 页面下载必须走 `WebDownloadDelegate` |
| 可从 `onDownloadStart` 取 `url` 后自行 `request.downloadFile` | `web.d.ts:4815` `onDownloadStart({ url, userAgent, contentDisposition, mimetype, contentLength })`；`request.downloadFile(context, { url, filePath, header?, … })`（`DownloadConfig.header` 可手动补 Cookie/Referer） | 适合可直接 GET 的直链；POST 表单、`data:`/`blob:`、需要浏览器会话状态的下载不能这样替代 |
| 系统下载服务的价值 | `request` 任务由系统服务执行，可在应用退后台后继续（`request.md`） | 大文件/熄屏场景可优先 `request.agent`（BACKGROUND）而非纯 Web delegate |

### 3.3 filePicker URI 的持久化

| 结论 | 依据 | 影响 |
| --- | --- | --- |
| `select()` 返回**只读**授权 URI | 4.1 `file-management/select-user-file.md`：“select 返回的 uri 权限是只读权限” | 上传、读取 OK；不能改原文件 |
| `save()` 返回**读写**授权 URI | 4.1 `file-management/save-user-file.md`：“save 返回的 uri 权限是读写权限” | 导出写文件 OK |
| 授权不能持久化（普通应用） | `@ohos.fileshare.d.ts:152 persistPermission(policies)`，`@permission ohos.permission.FILE_ACCESS_PERSIST`（`:141`）；4.1 `permissions-for-system-apps.md`：`FILE_ACCESS_PERSIST` 权限级别 **system_basic**、授权方式 system_grant、**ACL 使用 true**、起始版本 11 | 普通 CA 应用无法跨进程/重启保留 URI；会话结束即失效，必须重新 picker |
| 无需 `READ_IMAGEVIDEO`/`READ_DOCUMENT` | 4.1 `web/web-file-upload.md` 的上传示例只 import picker，不声明媒体/文档读权限 | 原文档 §5.4 结论成立 |

---

## 4. 与两份文档的逐条对照

### 4.1 `APP-BROWSER.md`

| 原判断（位置） | 核实 | 处理 |
| --- | --- | --- |
| §2.1 “`@kit.ArkWeb` 不可用（12+）” | `ets/kits/@kit.ArkWeb.d.ts` 存在，内容仅 `import webview from '@ohos.web.webview'; export { webview };` | **文档需修正** |
| §2.1 “下载可用（11）” | API 10 SDK 无下载类，11 新增 `setDownloadDelegate/startDownload/WebDownloadItem/…` | 加强 |
| §2.1 “同层渲染可用（11）” | `enableNativeEmbedMode/onNativeEmbedLifecycleChange/onNativeEmbedGestureEvent` 均为 11 新增 | 加强 |
| §2.1 “Cookie `fetchCookieSync/configCookieSync` 11 才加” | API 10 SDK 只有 `saveCookieAsync`；11 新增同步族 | 加强 |
| §2.1 “调试 `setWebDebuggingAccess`（仅 debug 构建开启）” | SDK 无此限制；4.1 `web-debugging-with-devtools.md` 只要求 `INTERNET` + `hdc fport` | **文档需修正**（改为“建议 release 关闭”） |
| §2.1 “离屏/预渲染/预编译/`setRenderProcessMode` 不可用” | 4.1 SDK 中 `precompileJavaScript/prefetchResource/setRenderProcessMode` 均 ABSENT | 加强 |
| §2.1 “`onOverrideUrlLoading` 是 12+” | 4.1 两份 `.d.ts` 均 ABSENT | 加强 |
| §2.1 “`@ohos.web.netErrorList` 不在 API 11” | SDK 无该文件 | 加强 |
| §5.1 “应用只需声明 `INTERNET`” | 两份 `.d.ts` 0 `@systemapi`/0 `@permission`；文档仅要求 `INTERNET` | 加强 |
| §5.4 “picker 临时授权 URI，Web 直接读取即可” | 正确；select 为只读；且 `FILE_ACCESS_PERSIST` 为 system_basic → 不可持久化 | 加强（补“只读、不可持久化”） |
| §5.7 “没有真正的 incognito 隔离” | `WebOptions.incognitoMode`（11）、`isIncognitoMode()`（11）、Cookie/Geolocation 的 `incognito?` | **文档需修正** |
| §5.8 #9 “configCookieSync/fetchCookieSync 是 11 才加” | 正确 | 保持 |
| §5.8 #8 “-2 连接失败、-6 找不到主机” | 无官方枚举/文档；只有 `getErrorCode(): number` | **文档需修正**（去语义、只显示数字） |
| §5.3 “API 11 无公开的跨进程续传保证” | 有 `serialize/deserialize/resumeDownload`（11），但非系统托管 | **文档需修正**（补“需应用存活”） |
| §1.3 “示例 README 过期，代码用 deviceInfo” | master 用 deviceInfo；3.2/4.0/4.1 用 `@ohos.systemparameter` | **文档需修正**（限定 master） |
| §1.3/§2.2 “示例 `loadUrl` 强制拼 https” | 3.2/4.0：无条件 `addr = "https://" + addr`；4.1：仅在无 scheme 时补 | **文档需修正**（限定版本；设备 1.0.15 属 3.2 代，实机结论仍成立） |
| §2.2 官方 `applications_browser` API 23 不可直接用 | 未复核上游仓库（本次不拉大仓），保留原判断 | 未复核 |
| §5.3 “下载完成后 `notificationManager` 通知” | 未复核通知权限细节；不影响主结论 | 未复核 |

### 4.2 `APP-FILETRANSFER.md`

| 原判断（位置） | 核实 | 处理 |
| --- | --- | --- |
| §2.1 服务端 `bind`（任务前提，正文未写） | `TCPSocketServer` 无 `bind()`；只有 `listen(NetAddress)`；Spike 已在正文补充说明 | 无需改正文，建议在 §2.1 表补一句“listen 内部完成 bind+listen” |
| §2.1 `listen` 参数/权限/错误 | 参数 `NetAddress`；`INTERNET`；错误码 401/201/2300002/2303109/2303111/2303198/2303199 | 加强（补错误码） |
| §2.1 “绑定 0.0.0.0” | 接口无限制；官方示例用具体网卡 IP；Spike 已实测 0.0.0.0:8080 | 加强（设备已覆盖） |
| §2.1 “长时任务只提升优先级，系统仍会挂起进程” | 官方原文是“降低终止概率，仍可能终止”，并要求真实执行对应任务 | **文档需修正**（措辞） |
| §3.1 “A 不需要 `KEEP_BACKGROUND_RUNNING`（也不解决挂起）” | 权限为 normal/system_grant 可申请；但确实不构成后台保证 | 保持，措辞同步修正 |
| §2.2 “uploadFile/downloadFile 系统服务代理，可在后台继续” | 任务由系统服务代理；但后台**不支持回调**；仅 `agent.BACKGROUND` 明确后台不受影响 | **文档需修正**（补回调限制与模式差异） |
| §2.2 “uploadFile 只支持 cacheDir” | 官方明文 + `File.uri` 只支持 `internal://cache/` | 加强 |
| §2.2 “downloadFile 只落到应用目录” | 官方明文 | 加强 |
| §2.2 “http 请求体无文件流式上传” | `HttpRequestOptions.extraData?: string \| Object \| ArrayBuffer`（`@ohos.net.http.d.ts:143`）；`requestInStream` 用于响应流（`:932/973/1014`） | 加强 |
| §2.3 “RequestMethod 无 PROPFIND/MKCOL” | `@ohos.net.http.d.ts:1220+` 枚举仅 OPTIONS/GET/HEAD/POST/PUT/DELETE/TRACE/CONNECT | 加强 |
| §2.3 “rcp 不在 API 11 SDK” | SDK 无 `*rcp*`/`*remoteCommunication*` 文件 | 加强 |
| §2.4 “SDK 无 SMB API” | 无 `*smb*`/`*cifs*` 文件 | 加强 |
| §2.5 “无二维码解码 API” | 无 `*barcode*`/`*scan*` 模块 | 加强 |
| §1.4/§3.1 “普通应用不能 bind 80/443” | 内核默认 `ip_unprivileged_port_start=1024`；OpenHarmony `init.cfg` 未改写；本机实测 1024 | 加强（补源码依据） |
| §4.2/§4.3 “URI 授权不持久化” | `FILE_ACCESS_PERSIST` = system_basic + ACL，普通应用不可用 | 加强（补权限定义） |
| §4.2 “`fs.open(uri)` 直接流式读” | select 返回只读 URI，可读 | 加强（补“只读”） |
| §4.2 “`DocumentViewPicker.save({ newFileNames })` 批量保存” | `@ohos.file.picker.d.ts:441 save(option?)`；`DocumentSaveOptions.newFileNames?: Array<string>`（`:203/382`） | 加强 |
| §4.6 M0 #5 “FOLDER 模式” | `DocumentSelectMode.FOLDER = 1`，`@since 11`（`@ohos.file.picker.d.ts:319`）；但设备 FilePicker 1.1.0.300 是 API 9/10 | 保持“需实测”，补 `@since 11` |
| §2.1 “TLSSocketServer（API 11 可用）” | `TLSSocketServer` 在 API 10 SDK 已存在（`@since 10`） | 保持，补“since 10” |
| §1.4/§2.2 “browser1 无法打开 http://IP:端口” | 3.2/4.0 分支无条件补 https → 与设备 1.0.15 行为一致；4.1 分支已修复 | 保持（补版本说明） |
| §1.2 “预置 miniserve 是 root + 全 /data + 无鉴权” | 本次未碰设备，保留既有实测；与本次静态结论无冲突 | 未复核（设备事实） |

---

## 5. 未找到 / 无法核实（明确列出）

1. **`ip_unprivileged_port_start` 在 OpenHarmony 源码中的显式设置**：未找到。`base/startup/init`（4.1）`services/etc/init.cfg` 集中写 net sysctl，但无该键；推断沿用 Linux 默认 1024（C）。
2. **“Web 调试仅 debug 构建可用”**：4.1 SDK/文档均未找到该限制。
3. **`onErrorReceive` 错误码 -2/-6 的官方语义**：未找到（无 `netErrorList`、无枚举、无文档表）。
4. **Web 下载与 `@ohos.request` 的官方集成路径**：未找到（无 API、文档 0 提及）。
5. **普通应用在本镜像上 Web 组件可用性**：源码层无限制；同目录 `## Spike 实测` 已用普通 test-CA 应用验证通过（设备证据，非本报告方法）。
6. **`TCPSocketServer.listen` 绑定 `0.0.0.0`**：接口无限制，文档无示例；同目录 Spike 已实测 `0.0.0.0:8080` 成功。
7. **`request.uploadFile` legacy 接口在应用后台的传输行为**：文档只明确“后台不支持回调”，未像 `agent.BACKGROUND` 那样明文承诺“后台任务不受影响”，需实测。
8. **设备预置 FilePicker 1.1.0.300 是否支持 `DocumentSelectMode.FOLDER`**：需实机 M0（API 11 声明支持）。
9. **官方 `applications_browser`（API 23）能力清单**：本次未拉取大仓复核，保留原文档判断。

---

## 6. 参考（可复现）

### 6.1 SDK（本机）

| 内容 | 路径 |
| --- | --- |
| Web 组件声明 | `D:\ohos-tools\sdk\openharmony-4.1-Release\ets\component\web.d.ts` |
| WebView 控制器/下载 | `D:\ohos-tools\sdk\openharmony-4.1-Release\ets\api\@ohos.web.webview.d.ts` |
| ArkWeb Kit 别名 | `D:\ohos-tools\sdk\openharmony-4.1-Release\ets\kits\@kit.ArkWeb.d.ts` |
| Socket | `D:\ohos-tools\sdk\openharmony-4.1-Release\ets\api\@ohos.net.socket.d.ts` |
| NetAddress | `D:\ohos-tools\sdk\openharmony-4.1-Release\ets\api\@ohos.net.connection.d.ts` |
| request | `D:\ohos-tools\sdk\openharmony-4.1-Release\ets\api\@ohos.request.d.ts` |
| picker | `D:\ohos-tools\sdk\openharmony-4.1-Release\ets\api\@ohos.file.picker.d.ts` |
| fileshare（URI 持久化） | `D:\ohos-tools\sdk\openharmony-4.1-Release\ets\api\@ohos.fileshare.d.ts` |
| 长时任务 | `D:\ohos-tools\sdk\openharmony-4.1-Release\ets\api\@ohos.resourceschedule.backgroundTaskManager.d.ts` |
| window（keep screen on） | `D:\ohos-tools\sdk\openharmony-4.1-Release\ets\api\@ohos.window.d.ts` |
| 默认 syscap | `D:\ohos-tools\sdk\openharmony-4.1-Release\ets\api\device-define\default.json`（L182） |
| API 10 对照 | `D:\ohos-tools\sdk\10\ets\...`（`apiVersion=10`，`4.0.10.13`） |

### 6.2 官方文档（OpenHarmony-4.1-Release）

- Web 页面加载（`$rawfile`、`INTERNET`）：`zh-cn/application-dev/web/web-page-loading-with-web-components.md`
- Web 下载（`setDownloadDelegate/startDownload`）：`zh-cn/application-dev/web/web-download.md`
- Web 文件上传（`onShowFileSelector`）：`zh-cn/application-dev/web/web-file-upload.md`
- Web 调试：`zh-cn/application-dev/web/web-debugging-with-devtools.md`
- Web 属性（`mixedMode` 默认 None、`fileAccess` 默认 true）：`zh-cn/application-dev/reference/apis-arkweb/ts-basic-components-web.md`
- Socket API：`zh-cn/application-dev/reference/apis-network-kit/js-apis-socket.md`
- request API：`zh-cn/application-dev/reference/apis-basic-services-kit/js-apis-request.md`
- 应用文件上传下载：`zh-cn/application-dev/file-management/app-file-upload-download.md`
- 选择/保存用户文件：`zh-cn/application-dev/file-management/select-user-file.md`、`save-user-file.md`
- 长时任务：`zh-cn/application-dev/task-management/continuous-task.md`
- 普通权限：`zh-cn/application-dev/security/AccessToken/permissions-for-all.md`
- 系统应用权限：`zh-cn/application-dev/security/AccessToken/permissions-for-system-apps.md`

### 6.3 上游源码 / 内核

- 示例浏览器（分支差异）：
  - `OpenHarmony-3.2-Release` / `OpenHarmony-4.0-Release`：`entry/src/main/ets/model/Browser.ets` 无条件 `addr = "https://" + addr`；`pages/Index.ets` 用 `@ohos.systemparameter`
  - `OpenHarmony-4.1-Release`：`loadUrl` 仅在无 scheme 时补 `https://`；`Index.ets` 仍用 `@ohos.systemparameter`
  - `master`：仍无条件补 `https://`；`Index.ets` 改用 `@ohos.deviceInfo.deviceType`
- OpenHarmony init 的 sysctl 列表：`startup_init`（4.1）`services/etc/init.cfg`（210 行，无 `ip_unprivileged_port_start`）
- Linux `ip_unprivileged_port_start`：`Documentation/networking/ip-sysctl.rst`（Default: 1024；privileged 需 root/CAP_NET_BIND_SERVICE）
