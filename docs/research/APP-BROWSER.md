# OpenHarmony 浏览器应用调研（LHT16 / API 11）

- 实测日期：2026-11-17
- 设备：LHT16，`OpenHarmony-4.1.7.5`，API 11，`arm64-v8a`，1080x2408，8GB（内核可见 `MemTotal 7,502,556 kB`）
- 文档边界：只做调研与方案设计，不创建工程、不修改现有代码；实机操作仅限 `hdc` 只读查询、拉起/停止应用、拉取 HAP 副本用于离线分析
- 目标：浏览器“能用、够快、少内存”，先定方案，次日再建工程
- 结论版本：v1.0

## 0. 结论摘要

1. **预置 `com.ohos.nweb` 不是浏览器，只是 Web 引擎载体。** 它的 `module.json` 中没有 `abilities` 数组（`bm dump` 里 `abilityInfos: []`），桌面图标被隐藏（`hideDesktopIcon: true`），`aa start` 直接失败 `resolve ability err`。它携带 `libweb_engine.so`（137.9 MiB，Chromium `114.0.5735.197`）+ `resources.pak`/`icudtl.dat`，供系统 `Web` 组件使用。**结论：无法“唤起预置浏览器”，但新写的 ArkWeb 壳会自动复用这套引擎，不增加包体。**
2. **`ohos.samples.browser1` 能被 launcher 打开，但不能被“当作浏览器”调用。** `aa start` 成功；其 `module.json` 只有 `action.system.home` + `entity.system.home`（无 `viewData`/`http(s)` scheme、无 `entity.system.browsable`），也不解析 intent 传来的 URL。它是 API 9 的示例应用（源码 Apache-2.0），有最多 10 个标签、地址栏、前进/后退/刷新，**没有下载、书签、历史**，且代码里 `loadUrl()` 强制拼 `https://`。
3. **“只做壳去调预置浏览器”这条路不成立。** 既无 launchable ability（nweb），也无 URI 入口（browser1）。壳只能“把 browser1 拉起来”，无法传 URL、加书签或控标签，产品价值接近零。真正可复用的是**系统 Web 引擎**：自己写壳同样用这套引擎，零包体、零三方依赖。
4. **推荐方案 B：新写零三方依赖 ArkTS ArkWeb 壳**（地址栏 + 3 标签上限 + 书签/历史 + 下载 + 文件选择 + 离线错误页），参考 `applications_app_samples` 的 Browser 示例与 `OHBrowser` 的实现思路（均为 Apache-2.0），但不直接 fork。
5. **最大风险是“非系统应用在此镜像上能否正常使用 Web 组件”**（现有两个 Web 应用都是系统应用）。这必须先由 M0 的 0.5~1 人日空壳验证，再投入其余开发。其次是内存：实测单标签就约 **356 MiB**（应用 241.9 MiB + 渲染进程 114.6 MiB）。
6. 总工作量约 **12.5 人日**（单人 2~2.5 周，含 1 人日 buffer），其中 M0 验证、下载、内存控制是三个主要成本点。

---

## 1. 现状实测

### 1.1 设备与运行时

| 项 | 值 | 来源 |
| --- | --- | --- |
| 系统 | `OpenHarmony-4.1.7.5`，`const.ohos.apiversion=11`，`const.product.model=LHT16` | `param get` |
| 内存 | total 7,326 MiB，空闲时 free 4,857 MiB，Swap 1,023 MiB | `free -m` |
| 已装三方/预置应用 | 52 个 bundle（含系统包），**没有第三方浏览器** | `bm dump -a` |
| Web 相关系统库 | `/system/lib64/libnweb_ohos_wrapper.z.so`、`libweb_inner_kit.z.so`、`libwebpplugin.z.so` | `ls /system/lib64` |
| Web 进程 | `nwebspawn`（pid 574，RSS 10.8 MiB）常驻，渲染进程由它派生 | `ps -ef` |
| 引擎配置 | `/system/etc/web/web_config.xml`：`renderProcessCount=40`、`backgroundMediaShouldSuspend=true`、`touchEventShouldRegister=true` | `cat` |
| Web 主题资源 | `/system/etc/webview/ohos_nweb/{alias.svg,context-menu.svg}` | `ls` |

### 1.2 `com.ohos.nweb`（预置 Web 引擎载体）

`bm dump -n com.ohos.nweb` 关键字段：

| 字段 | 值 |
| --- | --- |
| `versionName` / `versionCode` | `4.1.6.5` / `40106505` |
| `apiTargetVersion` / `apiCompatibleVersion` | 10 / 10 |
| `compileSdkVersion` | `4.0.10.13` |
| `isSystemApp` / `appPrivilegeLevel` | `true` / `normal` |
| `appDistributionType` | `os_integration`（系统预置） |
| `hideDesktopIcon` | `true`（不在桌面显示） |
| `mainElementName` | `EntryAbility`（但 `abilityInfos` 为空数组） |
| `hapPath` | `/system/app/com.ohos.nweb/NWeb.hap` |
| HAP 大小 | 83,084,084 B（79.2 MiB） |
| `uid` | 10009 |

`NWeb.hap` 内部（离线解包，只读）：

```
ets/modules.abc                       636 B      # 几乎没有 JS 逻辑
module.json                           711 B      # 无 "abilities" 字段
resources/rawfile/resources.pak       7,466,203 B
resources/rawfile/icudtl.dat         10,544,880 B
resources/rawfile/chrome_100_percent.pak / 200 / locales/*.pak
libs/arm64-v8a/libweb_engine.so     144,591,024 B  # 引擎，Chromium 114.0.5735.197
libs/arm64-v8a/libnweb_render.so        876,856 B
```

安装后引擎落在 `/data/app/el1/bundle/public/com.ohos.nweb/libs/arm64/`。

实测结论（三项互相印证）：

1. `module.json` 无 `abilities`，`bm dump` 的 `hapModuleInfos[0].abilityInfos = []`；
2. `aa start -b com.ohos.nweb -a EntryAbility` → `error: resolve ability err.`；
3. `hideDesktopIcon=true`，桌面也不可见。

**判定：它是“Web 引擎 + 资源”系统预置包（等价于 Android 的 WebView provider），不是可启动浏览器。** 附带结论：Chromium 版本为 114（2023-05 基线），站点兼容性上限由它决定，应用侧无法升级。

### 1.3 `ohos.samples.browser1`（示例浏览器）

| 字段 | 值 |
| --- | --- |
| `versionName` / `versionCode` | `1.0.15` / `1000015` |
| `apiTargetVersion` / `apiCompatibleVersion` | 9 / 9 |
| `compileSdkVersion` | `3.2.16.6` |
| `isSystemApp` / `appPrivilegeLevel` | `true` / `system_core` |
| `hideDesktopIcon` / `removable` | `false` / `true` |
| HAP | `/system/app/ohos.samples.browser1/Browser.hap`，1,707,478 B（1.63 MiB），`uiSyntax=ets` |
| `abilityInfos[0]` | `MainAbility`，`skills = [action.system.home + entity.system.home]`，`visible=true` |
| 权限 | `ohos.permission.INTERNET`、`ohos.permission.GET_WIFI_INFO` |

能力入口实测：

- **launcher 可打开**：`aa start -b ohos.samples.browser1 -a MainAbility` → `start ability successfully.`；`hideDesktopIcon=false`，桌面有图标。
- **不能被第三方当浏览器调用**：`module.json` 的 skills 只有 home，没有 `ohos.want.action.viewData`、`scheme=http/https`、`entity.system.browsable`；代码也不读 `want.uri`。即使强行 `-U https://...` 拉起，页面不会跳转。
- 功能面（源码 + 实机一致，源码为 `applications_app_samples/code/BasicFeature/Web/Browser`，Apache-2.0，8 个 ets 文件）：
  - 有：多标签（`Tabs`，上限 10）、地址栏、前进/后退/刷新、本地主页（`rawfile/phone.html` + 站点图标）、标题栏、手机/平板两套布局。
  - 无：下载、书签、历史、Cookie 管理、错误页、文件上传、新窗口处理、深色模式、搜索建议。
  - 坑：`Browser.ets` 的 `loadUrl()` 无条件 `addr = "https://" + addr`，导致 **http 站点和 IP:端口 无法打开**；`onDownloadStart` 未实现，点下载无反应。
  - 源码 README 声称使用 `@ohos.systemparameter`（系统接口需 Full SDK），实际代码用的是 `@ohos.deviceInfo` + `@ohos.mediaquery`（公开接口），README 已过期；fork 时以代码为准。

### 1.4 内存实测（单标签）

打开 browser1（加载其自带主页）后 6 秒采样：

| 进程 | uid | VmRSS | Threads |
| --- | --- | --- | --- |
| 应用主进程 `ohos.samples.browser1` | 20010024 | 247,696 kB（241.9 MiB） | 72 |
| 渲染进程（父进程 `nwebspawn`） | 1000009 | 117,308 kB（114.6 MiB） | 13 |
| `nwebspawn` | root | 11,048 kB（10.8 MiB） | - |

系统整体 used 从 2,468 MiB 升到 2,748 MiB（**约 +280 MiB**）；`aa force-stop` 后进程回收。说明：

- 内存不是“一个 Web 组件 50MB”的量级，**单标签就要按 250~350 MiB 预算**（含共享库常驻页）；
- 页面越重（图片、视频、复杂 JS）越高，且渲染进程是独立沙箱进程（独立 uid），不会与应用共享崩溃域；
- 10 标签的示例实现如果不销毁非活动 Web，理论上会叠加；官方 `applications_browser` README 明确其标签页**共享同一渲染进程**，内存主要来自各 Web 实例与页面堆。

### 1.5 系统层面的“默认浏览器”现状

- 全机没有第三方浏览器；仅有 `com.ohos.nweb`（引擎）与 `ohos.samples.browser1`（示例）。
- `bm dump` 不输出 ability 的 `skills`，因此无法用 `bm dump -a` 全量枚举 http 处理器；对两个浏览器 HAP 的 `module.json` 直接解包确认：**nweb 无 ability，browser1 仅 home**。
- 结论：**本机没有可用的 http/https 全局入口**。外部链接无法被“默认浏览器”接管；应用内打开网页必须自己实现 Web 容器（或把 URL 复制给用户）。
- 成为默认浏览器需要 `entity.system.browsable` + `viewData` skills，并且大概率需要在“默认应用”设置里被选中；本机 `com.ohos.settings` 是否提供该 UI 未验证。**预置/系统签名才能改系统默认应用配置，普通测试 CA 应用不参与该竞争。**

---

## 2. 可复用的开源实现调研

### 2.1 OpenHarmony 官方 ArkWeb / NWeb 能力（以本机 API 11 SDK 的 `.d.ts` 为准）

SDK：`$OHOS_TOOLS/sdk/openharmony-4.1-Release`（`ets` 4.1.7.5，API 11）。命名空间仍是 `@ohos.web.webview`（`@kit.ArkWeb` 是 API 12 之后的事）。

| 能力 | API 11 状态 | 关键接口 / 说明 |
| --- | --- | --- |
| Web 组件 + 控制器 | 可用 | `Web({src, controller})`；`loadUrl/refresh/stop/backward/forward/accessBackward/accessForward`，`getUrl/getTitle/getPageHeight/getFavicon` |
| 初始化引擎 | 可用 | `WebviewController.initializeWebEngine()`；控制器方法在 `onControllerAttached` 之前调用会抛 `17100001 Init error` |
| 下载 | 可用（11） | `setDownloadDelegate(WebDownloadDelegate)`、`startDownload(url)`；`WebDownloadItem` 支持 `start(path)/pause()/resume()/cancel()/serialize()/getPercentComplete()/getCurrentSpeed()/getState()` |
| Cookie | 可用 | `WebCookieManager.fetchCookieSync/configCookieSync/saveCookieAsync/clearAllCookiesSync`；注意需在 Web 初始化后调用 |
| JS 桥 | 可用 | `registerJavaScriptProxy/deleteJavaScriptRegister/runJavaScript/runJavaScriptExt`、`WebMessagePort`（`createWebMessagePorts/postMessage`） |
| 同层渲染 | 可用（11） | `enableNativeEmbedMode(true)` + `onNativeEmbedLifecycleChange/onNativeEmbedGestureEvent`，HTML 侧 `<embed type="native/xxx">`；只支持嵌套一层 Web |
| 深色模式 | 可用 | `darkMode(WebDarkMode.Auto/On/Off)` + `forceDarkAccess` |
| 文件上传 | 可用（9） | `onShowFileSelector` → `picker.DocumentViewPicker.select()` → `event.result.handleFileList([uri])` |
| 新窗口 | 可用（9/10） | `multiWindowAccess(true)` + `onWindowNew(event)` + `ControllerHandler.setWebController()`；不处理时必须传 `null` |
| 错误/SSL | 可用 | `onErrorReceive`、`onHttpErrorReceive`、`onSslErrorEventReceive`、`onRenderExited` |
| 请求拦截 | 可用 | `onInterceptRequest`、`onLoadIntercept`、`onUrlLoadIntercept`（**没有** `onOverrideUrlLoading`，那是 12+） |
| 调试 | 可用 | `WebviewController.setWebDebuggingAccess(true)`（仅 debug 构建开启） |
| 会话状态 | 可用（10） | `serializeWebState()/restoreWebState()` |
| 安全浏览 | 可用 | `enableSafeBrowsing(true)` |
| **离屏渲染 / 预渲染** | **不可用** | 4.1 文档没有 offscreen rendering 章节；API 11 无对应接口 |
| **预编译 JS / 预取资源** | **不可用** | `precompileJavaScript`、`prefetchResource` 均为 12+ |
| **独立渲染进程模式** | **不可用** | `setRenderProcessMode` 为 12+；4.1 由系统按 `renderProcessCount` 统一调度 |
| **网络错误码枚举** | **不可用** | `@ohos.web.netErrorList.d.ts` 不在 API 11 SDK 中，只能按 `error.errorCode` 数字判断 |
| **`@kit.ArkWeb`** | **不可用** | 12+ 的 Kit 化命名空间 |

### 2.2 开源项目对比

| 项目 | 地址 | 许可证 | API / 平台 | 规模与能力 | 对本机的可用性 |
| --- | --- | --- | --- | --- | --- |
| 官方 `applications_browser`（`com.ohos.browser`） | github.com/openharmony/applications_browser（gitcode 同步） | Apache-2.0（`bundle.json`） | `compatibleSdkVersion 23` / `compileSdkVersion 26`，OpenHarmony | 351 个文件；ArkUI + ArkWeb；标签/书签/历史/下载/RDB 持久化/SceneBoard 窗口/扫描/通知；`ram: 205595KB`（`bundle.json` 声明） | **不能直接用**：API 23 的 ArkWeb/Kit API（`@kit.ArkWeb`、多窗口新接口）在本机不可用；依赖 SceneBoard 与系统权限（`WRITE_IMAGEVIDEO`、`READ_WRITE_DOWNLOAD_DIRECTORY`）、`com.ohos.scanservice`。**只作功能与交互参考。** |
| `applications_app_samples` 的 Browser（即本机 `ohos.samples.browser1`） | gitee.com/openharmony/applications_app_samples → `code/BasicFeature/Web/Browser` | Apache-2.0 | 9（可提到 11） | 8 个 ets，约 30KB；多标签、地址栏、前进后退刷新、本地主页；无下载/书签/历史 | **可作起手模板**：代码量与 API 11 兼容，去掉强制 https 逻辑并补功能即可；但 UI 简陋、无错误页。 |
| `DuXingLang/OHBrowser` | github.com/DuXingLang/OHBrowser | Apache-2.0（示例派生） | 12（`compile/compatibleSdkVersion 12`），OpenHarmony | 在示例基础上加了标签条、页内查找、书签、历史、下载委托、Cookie/WebStorage 清理、`preferences` 持久化；`entry` 约 12 个 ets（`Browser.ets` 22KB） | **API 12，不能直接装/编译到 API 11**；但实现思路最接近本项目，`setDownloadDelegate`、`preferences`、`onWindowNew` 的用法可直接抄。 |
| `awaLiny2333/LinysBrowser_NEXT` | github.com/awaLiny2333/LinysBrowser_NEXT | MIT | HarmonyOS NEXT（`compatibleSdkVersion 6.1.0(23)`） | 292 stars，完整的 NEXT 浏览器 UI/标签/收藏 | **不可移植**：NEXT Kit + API 23，仅作 UI/交互参考。 |
| `OpenMonyHar/OpenMonyHar` | github.com/OpenMonyHar/OpenMonyHar | 未声明 | 自研浏览器方向 | 微内核浏览器概念项目 | **不可用**：无许可证（不能商用/分发）、非 ArkWeb 壳。 |
| NWeb 引擎源码 `web_webview` | gitee.com/openharmony/web_webview | Apache-2.0 | OpenHarmony 4.1 | Chromium fork + `ohos_nweb` 适配层；`rom ~85MB`、`ram ~150MB`（`bundle.json`） | 仅用于理解引擎/能力边界；**应用侧不能替换或裁剪引擎**（144MB 在系统分区）。 |

### 2.3 “不重写浏览器、只做壳”的可行性结论

逐一验证三条“壳”路线：

| 壳路线 | 实测/资料 | 结论 |
| --- | --- | --- |
| Want 拉起 `com.ohos.nweb` | 无 abilities，`aa start` 报 `resolve ability err` | 不可行 |
| Want(uri=http/https) 拉起 `ohos.samples.browser1` | `module.json` 无 viewData/browsable，代码不读 uri | 不可行（只能打开空白主页） |
| 壳内嵌一个 Web 只做“书签/主页导航”，实际渲染交给系统浏览器 | 系统没有可被嵌入/远程控制的浏览器组件 | 不可行 |

**唯一成立的“复用”是复用系统 Web 引擎本体**：普通应用 `Web` 组件加载 `libweb_engine.so`，因此包体只有壳本身（预计 < 2 MB），与“唤起预置浏览器”体验无关但收益相同。

---

## 3. 候选方案对比

| 维度 | A. 复用/唤起预置 nweb | B. 新写 ArkWeb 壳（推荐） | C. fork 开源浏览器裁剪 |
| --- | --- | --- | --- |
| 具体做法 | Want 调 `com.ohos.nweb` / browser1 | 新建 Stage 工程，`Web` + 自研 UI，零三方依赖 | fork `OHBrowser`(API 12) 或官方 `applications_browser`(API 23)，降级裁剪 |
| 可行性 | **不可行**（无 ability / 无 URI 入口） | 高（只需验证普通签名下 Web 可用） | 低~中（API 12/23 → 11 需大面积改；官方版依赖系统权限） |
| 工作量 | 0（但产品价值 0） | 约 12.5 人日 | 8~15 人日，且含大量“降级 + 删功能”的返工 |
| 内存 | 不可控（browser1 自身 356 MiB/标签） | 可控：3 标签上限、非活动标签销毁、无预取 | 继承上游：OHBrowser 多标签常驻，需自行加销毁；官方版声明 205MB RAM 起 |
| API 兼容 | - | 完全按 API 11 写，风险只在 M0 | API 12/23 接口需逐个替换（如 `@kit.ArkWeb`、新窗口接口、RDB 版本） |
| 包体 | - | < 2 MB（引擎由系统提供） | 2~5 MB（含资源/图标） |
| 风险 | 100% 失败 | 中：普通应用 Web 可用性、内存、下载权限 | 高：降级破坏、上游无 4.1 分支、许可/维护分叉 |
| 可维护性 | 无 | 高：代码全自有、单模块、无三方依赖 | 中：上游持续演进到 API 23+，本地补丁难合流 |
| 结论 | 放弃 | **采用** | 只作代码/交互参考，不 fork |

补充：C 里“fork 示例 Browser”其实是 B 的一个子集——示例只有 8 个文件，抄它比自己写省 1~1.5 人日，但必须重写 `loadUrl` 的 https 强拼、补 5 个功能模块，最终仍是 B 的架构。

---

## 4. 推荐方案

**采用方案 B：新写零三方依赖的 ArkTS Stage 浏览器壳**，工程暂定 `ohos-browser`（次日创建，本文件不建工程）。

### 4.1 架构

```
EntryAbility (Stage, API 11)
└─ pages/Index.ets
   ├─ TitleBar.ets        地址栏 + 进度条 + 菜单（书签/历史/下载/设置）
   ├─ TabStrip.ets        标签切换（最多 3 个，可关闭）
   ├─ WebHost.ets         每个标签一个 Web 实例（仅活动标签保持挂载）
   └─ panels/             BookmarksPanel / HistoryPanel / DownloadsPanel / ErrorPage
model/
   ├─ TabManager.ets      Web 控制器生命周期、激活/销毁、会话恢复
   ├─ BrowserStore.ets    preferences 读写（书签/历史/设置/标签会话）
   ├─ DownloadManager.ets WebDownloadDelegate + 导出（picker）+ 失败重试
   └─ UrlResolver.ets     输入判定：URL / 搜索词 / 局域网 IP / 非法 scheme 拦截
resources/rawfile/
   ├─ home.html           轻量主页（纯本地、无远程图片，控制首屏内存）
   └─ offline.html        离线错误页（含错误码 + 重试按钮）
```

### 4.2 范围

必须做（MVP）：

- 地址栏（URL/搜索词判定、http/https 自适应，**不再强拼 https**）、前进/后退/刷新/停止、加载进度、标题、SSL/网络错误提示；
- 3 个标签上限，切换时只保留活动 Web，其余销毁（会话存 URL）；
- 书签（增删改、启动页网格）、历史（按日去重、可删/清空）、下载（进度、暂停/继续、取消、导出）；
- 文件上传（`onShowFileSelector`）、`window.open` 转新标签、深色跟随、离线错误页；
- 安全基线：仅允许 http/https/file(本地)/about 导航，拦截 `javascript:`、`data:` 外部注入；默认拒绝证书错误；release 关闭 Web 调试。

明确不做（非目标）：

- 成为系统默认浏览器、接管全局 http 链接（需系统签名/预置，超出普通应用能力）；
- 广告拦截/扩展、账号同步、阅读模式、代理设置（API 11 无对应公开接口）；
- 替换/升级 Web 引擎（Chromium 114 由系统决定）；
- 打包任何三方 JS 库（保持零依赖）。

### 4.3 复用策略

- UI 结构、`Browser.ets` 的控制器管理思路参考 `applications_app_samples` 的 Browser（Apache-2.0，需保留版权头）；
- 下载/书签/历史的实现方式参考 `OHBrowser`（Apache-2.0），但全部按 API 11 重写，不复制 API 12 代码；
- 不引用官方 `applications_browser` 的代码（模块化过重且绑定 SceneBoard/RDB），只抄交互清单。

---

## 5. 关键技术点

### 5.1 引擎与初始化

- 应用只需声明 `ohos.permission.INTERNET`；引擎由系统 `nwebspawn` + `com.ohos.nweb` 提供，**不要**在 HAP 里打包任何 `.so`。
- 首帧前调用 `WebviewController.initializeWebEngine()`（可选，系统也会懒加载）；控制器方法必须等 `onControllerAttached` 之后再调，否则 `17100001`。
- 页面对象创建成本高：`Web` 放在 `if (tab.active)` 分支里，切走即销毁，回到时用 `loadUrl` 恢复（会话另存 URL，不用 `serializeWebState`，避免状态字节与引擎版本耦合）。

### 5.2 多标签与内存

- 硬上限 3 个标签（实测单标签约 356 MiB，8GB 机器留 4.8GB 空闲，3 个仍安全；更多会挤占前台应用）。
- 非活动标签：从组件树移除（`@State activeTab` + `if`），并在移除前 `controller.stop()`；不要用 `visibility` 隐藏，隐藏仍占内存。
- 标签会话只存 `{url, title, timestamp}` 到 preferences，冷启动最多恢复 3 条。
- 主页用本地轻量 HTML（< 100KB，无远程图片）；示例浏览器的 `img.png` 1.2MB + 20 个站点图标会抬高首屏内存，不建议照搬。

### 5.3 下载

- 页面触发的下载：`setDownloadDelegate` → `onBeforeDownload(item)` 里 `item.start(沙箱路径 + getSuggestedFileName())`；`onDownloadUpdated/onDownloadFinish/onDownloadFailed` 更新 UI。
- 目标路径：`context.filesDir + '/Download/'`（应用沙箱，无需权限）；**不能直接写公共 Download 目录**。
  - `ohos.permission.READ_WRITE_DOWNLOAD_DIRECTORY` 是 `system_basic` + `user_grant` + ACL（起始版本 11），普通测试 CA 应用拿不到；
  - 导出给用户：`picker.DocumentViewPicker.save()` 让用户选位置（系统文件选择器已在机器上：`com.ohos.filepicker`），或提供“分享” Want。
- 直链下载（非页面触发）：`@ohos.request.downloadFile(context, config)`，同样落沙箱，`DownloadTask` 提供进度/暂停/恢复。
- 弱网：`WebDownloadItem` 有 `pause/resume/serialize`，做“失败后点继续”即可；不要做后台断点续传（API 11 无公开的跨进程续传保证）。
- 下载完成后用 `notificationManager` 发一条普通通知（可选，注意通知权限默认开启）。

### 5.4 文件选择（上传）

- `onShowFileSelector(event)` 中调 `new picker.DocumentViewPicker().select(options)`，把结果 `event.result.handleFileList([uri])` 回填，返回 `true`。
- 需要在 `module.json5` 里声明 `ohos.permission.READ_IMAGEVIDEO`/`READ_DOCUMENT` 吗？**不需要**：picker 返回的是临时授权 URI，Web 直接读取即可。
- `event.result.handleFileList([])` 表示用户取消；不要在未选择时返回 `true` 却不回填，会卡住页面。

### 5.5 书签/历史持久化

- 用 `@ohos.data.preferences`（公开 API，API 9+），单一 store `browser_store`，key：`bookmarks`（JSON 数组）、`history`（JSON，上限 500 条，按 URL+日去重）、`settings`、`session`。
- 写入策略：内存态 + `flush()` debounce 300ms，避免每次导航都落盘；书签量级几百条，JSON < 200KB，无需 RDB（官方版用 RDB 是为了支持文件夹树/1 万条，本方案不需要）。
- 迁移：首版加 `schemaVersion`，后续加字段不破坏旧数据。

### 5.6 离线/错误处理

- `onErrorReceive`（主文档失败）、`onHttpErrorReceive`（4xx/5xx，可放行让站点自己渲染）、`onSslErrorEventReceive`（默认 `handler.handleCancel()`，给用户“继续访问（不推荐）”二次确认后再 `handleConfirm()`）。
- 错误页：`controller.loadData(html, 'text/html', 'UTF-8')`，HTML 从 `rawfile/offline.html` 读出并注入 `errorCode/errorDescription/url`；提供“重试”按钮（`controller.loadUrl(lastUrl)`）。
- 弱网策略：主文档 15s 超时（`setTimeout` + `controller.stop()` → 错误页）；不要自动重试超过 2 次，避免流量与电量浪费。
- 网络状态：`@ohos.net.connection` 监听断网/恢复，恢复时提示“重新加载”，不自动刷新（用户可能正在看缓存页）。

### 5.7 安全

- `mixedMode` 默认 `MixedMode.None`（SDK 注释明确）：HTTPS 页面中的 HTTP 子资源会被拦截。做“日常浏览”保持 None；若需访问局域网 HTTP 管理页，提供单站点开关（`MixedMode.Compat`），并在地址栏显示“不安全”。
- 证书：默认拒绝所有 SSL 错误；**不要**为兼容自签站点做全局忽略。
- 文件/本地：`fileAccess(false)`（默认 true），确需本地 HTML 时用 `$rawfile`/`resource://`；`domStorageAccess(true)` 但 `databaseAccess(false)`（除非站点需要）。
- 导航白名单：`onLoadIntercept` 拦截 `javascript:`、`file://`（除 rawfile）、`intent://`、未知 scheme；`onWindowNew` 里同样校验 `targetUrl`。
- 调试：`setWebDebuggingAccess(true)` 只在 debug 构建；release 关闭，避免本地调试端口暴露。
- 隐私：提供“清除 Cookie/缓存/历史”（`WebCookieManager.clearAllCookiesSync`、`WebStorage.deleteAllData`、`removeCache(true)`），退出不清（浏览器习惯），设置里可开“无痕”（4.1 仅能靠不清 Cookie + 不写历史近似，**没有真正的 incognito 隔离**）。

### 5.8 API 11 的具体坑（实测/查 SDK 得出）

1. `onControllerAttached` 之前调用控制器方法 → `17100001 Init error`。
2. 没有 `onOverrideUrlLoading`：只能 `onLoadIntercept`/`onUrlLoadIntercept`，且返回值语义是“已拦截”，别和 `onInterceptRequest` 混用。
3. 没有离屏渲染/预渲染/预编译：**无法做真正的后台预加载**；用隐藏 Web 预加载会直接吃掉 100MB+ 内存，不做。
4. `Web` 放在 `Tabs`/`Swiper` 里必须显式给宽高（`width('100%').height('100%')`），否则白屏。
5. 软键盘：地址栏输入时键盘会顶起布局，`expandSafeArea` + `windowSoftInputMode` 需实测；本机输入法是第三方（`com.kika.hmos.inputmethod`/`com.local.homeime`），行为可能与模拟器不同。
6. `Web` 组件在页面 `onPageHide` 后仍可能持有 surface；切后台要 `controller.stop()` + 非活动销毁。
7. 示例的 `loadUrl` 强拼 `https://` 会让 `http://192.168.x.x:8080` 直接失败 —— 自己写 `UrlResolver`。
8. 4.1 没有 `@ohos.web.netErrorList`，错误码是裸数字（如 `-2` 连接失败、`-6` 找不到主机），错误页只做“通用 + 错误码”，别指望枚举。
9. `WebCookieManager` 的 `configCookieSync/fetchCookieSync` 是 11 才加的；旧写法 `setCookie/getCookie` 已标 `@deprecated`，直接用新接口。
10. `enableNativeEmbedMode` 只支持一层 Web 嵌套且 embed 背景固定白色；深色模式下需自行处理（同层渲染本项目大概率不用）。
11. 引擎是 Chromium 114：新语法/新 Web API（如部分 WebGPU、最新 CSS）不可用，遇到“某站点白屏”先怀疑引擎版本，而不是代码。
12. `bundleName` 需避免与预置冲突；建议 `com.local.browser`（与现有 `com.local.homekiosk`/`com.local.homeime` 风格一致）。

---

## 6. 风险清单

| # | 风险 | 概率 | 影响 | 缓解措施 |
| --- | --- | --- | --- | --- |
| R1 | **普通签名（非系统应用）在此镜像上无法使用 Web 组件**（现有两个 Web 应用都是系统应用，缺少反例） | 中 | 致命（方案 B 不成立） | **M0 第一件事**：空壳工程加载 `rawfile/home.html` + 一个 https 站点，确认引擎加载、无权限报错；失败则回退到“fork browser1 + 系统签名”（不可行）或改做“网页快捷方式壳”（价值低），需重新评估 |
| R2 | API 11 能力缺口（无离屏/预渲染/onOverrideUrlLoading）导致体验不如成熟浏览器 | 高 | 中 | 接受现实：不做预加载；用 `onLoadIntercept` 做导航控制；首屏优化靠本地主页 + 引擎 HTTP 缓存（`cacheMode`） |
| R3 | 内存：单标签 ~356 MiB，多标签叠加触发整机卡顿/杀后台 | 高 | 中 | 3 标签硬上限；非活动销毁；轻量主页；监控 `/proc/<pid>/status`；必要时降到 2 标签 |
| R4 | 下载不能直接写公共 Download，用户体验多一步 | 高 | 低 | 沙箱下载 + `DocumentViewPicker.save()` 导出 + 完成后通知；文案明确“保存到…” |
| R5 | 弱网（GitHub raw 不通、workers.dev 不可达）导致测试与站点选择困难 | 高 | 低 | 全部依赖本地（零 npm）；测试用国内可达站点 + 局域网 HTTP 服务（本机已有 `com.pengju.minihttpserver`）；错误页 + 重试 |
| R6 | 证书/明文策略引发站点不可用（自签、HTTP 子资源） | 中 | 中 | 默认严格；提供单站点“允许不安全”开关；错误页给出明确原因 |
| R7 | 无法成为默认浏览器，外部链接仍打不开 | 确定 | 中 | 产品定位为“应用内浏览器”；提供“复制链接/分享到浏览器”；不承诺全局接管 |
| R8 | 输入法/软键盘遮挡地址栏（第三方输入法） | 中 | 低 | M1 就在真机验证 `windowSoftInputMode`，必要时把地址栏放到底部或做滚动避让 |
| R9 | 应用只能 `hdc install`，恢复出厂/换机后需重装；不能预装 | 确定 | 低 | 沿用现有签名与 `scripts/deploy.sh` 流程；文档记录安装命令 |
| R10 | 引擎 Chromium 114 过旧，部分新站点渲染异常 | 中 | 中 | 记录“已知不兼容站点”；不做 polyfill 库（违背零依赖）；等系统 OTA |
| R11 | 下载/上传大文件时应用被杀（后台限制） | 低 | 中 | 下载用 `request.downloadFile`（系统下载服务）而非纯 delegate；会话内暂停/继续 |
| R12 | 误用系统 API（如 `@ohos.systemparameter`）导致只能 Full SDK 编译 | 中 | 低 | 只参考代码、不复制 import；编译用公开 SDK 验证；CI 里跑一次 clean build |

---

## 7. 里程碑与工时估算

按单人有效工时 6h/天估算，单位为“人日”。

| 里程碑 | 内容 | 验收标准 | 人日 |
| --- | --- | --- | --- |
| M0 可行性验证 | 空壳工程（API 11、Stage、现有测试 CA 签名）；`Web` 加载 `$rawfile/home.html` 与一个 https 站点；`INTERNET` 生效；打印 UA/引擎可用；测首屏时间与 RSS；验证 `preferences`/`picker`/`request` 可 import | 真机可打开页面、无 `201/202` 权限错误；RSS 数据入档；**R1 有结论** | 1.0 |
| M1 核心浏览 | 地址栏 + `UrlResolver`（不再强拼 https）、前进/后退/刷新/停止、进度、标题、错误回调接线 | 可访问 http/https/局域网 IP；`aa start` 冷启动 < 2s 到首帧 | 2.0 |
| M2 多标签与会话 | 3 标签上限、标签条、非活动销毁、会话持久化与恢复 | 3 标签切换无白屏；切走 5s 后 RSS 明显下降 | 1.5 |
| M3 书签/历史 | `preferences` 模型、书签面板、主页网格、历史按日分组/删除/清空 | 杀进程重启后数据完整；1000 次导航无卡顿 | 1.5 |
| M4 下载 | `WebDownloadDelegate` + 进度 UI + 暂停/继续/取消 + 沙箱落盘 + picker 导出 + 失败重试；直链走 `request.downloadFile` | 下载 50MB 文件成功、可导出到公共目录；断网后可继续 | 2.0 |
| M5 上传/新窗口/深色/错误页 | `onShowFileSelector`、`onWindowNew`→新标签、`darkMode`、`offline.html`、SSL 错误页 | 上传本地文件成功；`window.open` 不崩溃；断网有可重试错误页 | 1.5 |
| M6 安全与打磨 | 导航白名单、`mixedMode`、`fileAccess`、release 关调试、清除数据、弱网回归、与 browser1 的性能/内存对比 | 安全清单全过；单标签 RSS ≤ 300MiB；无 ANR/崩溃 | 2.0 |
| buffer | 联调、签名、装机、文档 | - | 1.0 |
| **合计** | | | **12.5 人日** |

关键路径：M0 → M1 → M2；M3/M4 可在 M1 后并行（同一人则串行，总工期不变）。若 R1 在 M0 被证伪，立即停止，改用方案 C 的“fork browser1 + 补功能”，预计额外 +5 人日且仍受系统签名限制。

---

## 8. 参考链接

以下链接均为 2026-11-17 实测可访问（`gitee.com/.../raw/...`、`gh-proxy.com` 可用；`docs.openharmony.cn/pages/...` 直连返回 404，故以 Gitee 文档仓库为准）。

OpenHarmony 4.1 官方文档（Gitee，`OpenHarmony-4.1-Release` 分支）：

- Web 组件概述：https://gitee.com/openharmony/docs/blob/OpenHarmony-4.1-Release/zh-cn/application-dev/web/web-component-overview.md
- 使用 Web 组件加载页面：https://gitee.com/openharmony/docs/blob/OpenHarmony-4.1-Release/zh-cn/application-dev/web/web-page-loading-with-web-components.md
- 下载能力（`setDownloadDelegate`/`startDownload`，API 11）：https://gitee.com/openharmony/docs/blob/OpenHarmony-4.1-Release/zh-cn/application-dev/web/web-download.md
- 文件上传（`onShowFileSelector`）：https://gitee.com/openharmony/docs/blob/OpenHarmony-4.1-Release/zh-cn/application-dev/web/web-file-upload.md
- 同层渲染（`enableNativeEmbedMode`，API 11）：https://gitee.com/openharmony/docs/blob/OpenHarmony-4.1-Release/zh-cn/application-dev/web/web-same-layer.md
- Cookie 与数据存储管理：https://gitee.com/openharmony/docs/blob/OpenHarmony-4.1-Release/zh-cn/application-dev/web/web-cookie-and-data-storage-mgmt.md
- 新窗口打开（`multiWindowAccess`/`onWindowNew`）：https://gitee.com/openharmony/docs/blob/OpenHarmony-4.1-Release/zh-cn/application-dev/web/web-open-in-new-window.md
- 应用/前端页面通信（JS 桥）：https://gitee.com/openharmony/docs/blob/OpenHarmony-4.1-Release/zh-cn/application-dev/web/web-in-app-frontend-page-function-invoking.md
- 权限：`READ_WRITE_DOWNLOAD_DIRECTORY`（system_basic / ACL）：https://gitee.com/openharmony/docs/blob/OpenHarmony-4.1-Release/zh-cn/application-dev/security/AccessToken/permissions-for-system-apps.md

源码与示例：

- Web 引擎（NWeb）源码，Apache-2.0：https://gitee.com/openharmony/web_webview （`bundle.json`：`name @ohos/webview`，`rom ~85MB`，`ram ~150MB`）
- 示例浏览器源码（本机 `ohos.samples.browser1` 对应），Apache-2.0：https://gitee.com/openharmony/applications_app_samples/tree/master/code/BasicFeature/Web/Browser
- 官方系统浏览器 `com.ohos.browser`，Apache-2.0，API 23（仅参考）：https://github.com/openharmony/applications_browser
- `OHBrowser`（API 12，下载/书签/历史实现参考），Apache-2.0：https://github.com/DuXingLang/OHBrowser
- `LinysBrowser_NEXT`（HarmonyOS NEXT，UI 参考），MIT：https://github.com/awaLiny2333/LinysBrowser_NEXT

---

## 附录 A：本次只读探查命令（可复现）

```powershell
$hdc = "$DEVECO_HOME/sdk/default/openharmony/toolchains/hdc.exe"   # Ver 1.3.0a

# 版本与设备
& $hdc version; & $hdc list targets
& $hdc shell "param get const.product.software.version; param get const.ohos.apiversion; param get const.product.model"

# 应用入口（bm dump 不输出 skills，需解包 HAP 的 module.json）
& $hdc shell "bm dump -n com.ohos.nweb"
& $hdc shell "bm dump -n ohos.samples.browser1"
& $hdc shell "aa start -b com.ohos.nweb -a EntryAbility"        # resolve ability err
& $hdc shell "aa start -b ohos.samples.browser1 -a MainAbility"  # success

# HAP 离线分析（只读拉取副本）
& $hdc file recv /system/app/com.ohos.nweb/NWeb.hap $env:TEMP\NWeb.hap
& $hdc file recv /system/app/ohos.samples.browser1/Browser.hap $env:TEMP\Browser.hap
# 然后用任意 zip 工具读取 module.json；引擎版本：
python -c "import re;d=open('libweb_engine.so','rb').read(60_000_000);print(sorted(set(re.findall(rb'Chrome/[0-9.]+',d))))"

# 内存
& $hdc shell "free -m"
& $hdc shell "cat /proc/<pid>/status | grep -E 'Name|VmRSS|Threads'"

# 引擎配置
& $hdc shell "cat /system/etc/web/web_config.xml"
```

本次对设备的写操作仅有：`aa start`/`aa force-stop` 示例浏览器（用于内存采样），以及向宿主机拉取 HAP 副本；未安装/卸载/重启/修改系统设置。

---

## Spike 实测（2026-11-17）

- 目的：验证本文 R1——普通 test-CA（非系统）应用里 `Web` 组件能否创建/加载本地 rawfile 与远程 https。
- 工程：临时 spike，`bundleName=com.local.spike`，compileSdk 10（Stage），模板来自 `ohos-kiosk`；用 SDK 自带 `OpenHarmony.p12` 测试 PKI 重新签发（OpenHarmony Application Root CA → Application CA → HomeKiosk App，10 年），profile 的 `bundle-name=com.local.spike`，`hdc install -r` 安装成功。应用为非系统应用（`isSystemApp=false`），未申请任何系统权限，仅 `ohos.permission.INTERNET`（normal）。
- 页面：`Column` + 固定高度 `Web({ src: $rawfile('spike.html'), controller })` + 按钮 + 可滚动日志；`spike.html` 内容为 `<h1>ok</h1><script>document.title='js-ok'</script>`，页面在 rawfile 加载 8 秒后自动执行 `controller.loadUrl('https://example.com')`。

实测现象（hilog，tag `A00fff/HomeKiosk: spike ...`）：

| 阶段 | 日志/证据 | 结果 |
| --- | --- | --- |
| 创建 `WebviewController` / `Web` 组件 | `WEB controller new OK`；页面正常出现，无 ArkUI 创建异常、无 crash | 通过 |
| 本地 rawfile 加载 | `WEB onPageBegin resource://rawfile/spike.html` → `WEB onPageEnd resource://rawfile/spike.html`，`WEB title=js-ok` | 渲染成功且 JS 执行 |
| `onConsole` | `WEB console spike-html console ok` | 回调可用 |
| 远程 `loadUrl('https://example.com')` | `WEB onPageBegin https://example.com/` → `WEB onPageEnd https://example.com/`，`WEB title=Example Domain`；`onErrorReceive` 未触发 | 通过（无证书/权限错误） |

- 截图：`snapshot_display` 可见页面顶部 `spike: Web + TCPSocketServer`、Web 区域渲染出 `example.com` 的 “Example Domain” 占位页，底部日志面板含上述 rawfile 的 `onPageEnd` / `title=js-ok` 行；抓取时间为启动后约 35 秒。
- 结论：**R1 被证伪**。在本机（LHT16 / OpenHarmony-4.1.7.5，API 11）上，仅用 SDK 自带 OpenHarmony 测试 CA 签名的普通应用即可创建 `Web` 组件：本地 rawfile 页面正常渲染并执行 JS，远程 https 也可加载，无需系统签名，未出现 `201/202` 权限错误。方案 B 的 Web 组件前提成立。
- 本次对设备写操作：安装/启动/卸载 `com.local.spike`，`snapshot_display` 截图，`uitest uiInput` 解锁与切换输入法；未改系统分区或系统设置。

---

## 核实修正

> 2026-11-17 追加。依据：API 11 SDK `.d.ts`（4.1.7.5）+ OpenHarmony 4.1 官方文档 + API 10 SDK 对照；详见 [VERIFY-BROWSER-TRANSFER.md](VERIFY-BROWSER-TRANSFER.md)。以下只列需改动的结论，正文其余部分保持原样。

1. **§2.1 “`@kit.ArkWeb` 不可用（12+）” → 改为可用**：`$OHOS_TOOLS/sdk/openharmony-4.1-Release/ets/kits/@kit.ArkWeb.d.ts` 已存在，内容仅 `import webview from '@ohos.web.webview'; export { webview };`，与 `@ohos.web.webview` 等价。
2. **§5.7 “没有真正的 incognito 隔离” → 改为可用**：`WebOptions.incognitoMode?: boolean`（`ets/component/web.d.ts:3541`，since 11）、`WebviewController.isIncognitoMode()`（`ets/api/@ohos.web.webview.d.ts:3660`，since 11）；`WebCookieManager` 的 Cookie/Geolocation 同步接口也接受 `incognito?`。注意其只隔离 Web 存储/Cookie/Geolocation，下载文件仍需自行清理。
3. **§2.1 “`setWebDebuggingAccess(true)`（仅 debug 构建开启）” → 删除“仅 debug”限制**：SDK 与 4.1 `web-debugging-with-devtools.md` 均未限制构建类型，只要求 `INTERNET` + `hdc fport`。建议改为“建议仅 debug 构建开启”。
4. **§5.3 “API 11 无公开的跨进程续传保证” → 改为有 API、但不能后台托管**：API 11 提供 `WebDownloadItem.serialize()` / `static deserialize()`（`@ohos.web.webview.d.ts:4070/4080`）与 `WebDownloadManager.setDownloadDelegate()/resumeDownload()`（`:4136/4145`），可恢复失败/取消的下载；但下载不由系统服务托管，应用进程被杀后不能继续，不能当后台下载服务。
5. **§5.8 #8 “-2 连接失败、-6 找不到主机” → 删除语义断言**：4.1 无 `@ohos.web.netErrorList`，`WebResourceError.getErrorCode()` 只返回 `number`（`web.d.ts:3131`）；错误页只显示数字 + `getErrorInfo()`。
6. **§1.3 “README 过期：代码已用 deviceInfo” → 限定 master**：`OpenHarmony-3.2/4.0/4.1-Release` 分支的 `pages/Index.ets` 仍是 `import parameter from '@ohos.systemparameter'`；仅 `master` 改为 `@ohos.deviceInfo.deviceType`。
7. **§1.3/§2.2 “示例 `loadUrl()` 强制拼 https” → 限定版本**：3.2/4.0 分支为无条件 `addr = "https://" + addr`；4.1 分支已改为“仅在无 scheme 时补”。设备 `1.0.15`（compileSdk 3.2.16.6）属 3.2 代，故“http://IP:端口 打不开”的实机结论仍成立。
8. **§2.1 下载 / 同层渲染 / Cookie 同步 → 加强**：上述能力在 API 10 SDK 中均不存在（`setDownloadDelegate/startDownload/WebDownloadItem/WebDownloadManager`、`enableNativeEmbedMode/onNativeEmbed*`、`fetchCookieSync/configCookieSync` 等），确属 API 11 新增。
9. **§2.1 “普通应用可能有系统应用限制” → 加强为“API 层无限制”**：`web.d.ts` 与 `@ohos.web.webview.d.ts` 全文 0 处 `@systemapi`、0 处 `@permission`；`Web.Webview.Core` 在 `device-define/default.json` 默认 syscap 中。运行时前提已由本文 `## Spike 实测` 证伪（普通 test-CA 应用可用 `Web`）。
10. **§5.4 “picker 直接读取即可” → 补两点**：`DocumentViewPicker.select()` 返回的是**只读**授权 URI（4.1 `select-user-file.md`）；且 `FILE_ACCESS_PERSIST` 为 `system_basic + system_grant + ACL`（11），普通应用无法持久化，只能会话内使用。
