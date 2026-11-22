# OpenHarmony 4.1 应用分发中心调研（LHT16 / API 11）

- 实测日期：2026-11-17
- 设备：LHT16，`OpenHarmony-4.1.7.5`，API 11，`arm64-v8a`
- 文档边界：只做调研与方案设计，不创建工程、不修改现有代码；实机操作均为只读查询/拉起/抓图/拉取 HAP 副本。
- 结论版本：v1.0

## 0. 结论摘要

1. **应用内不能一键安装。**
   普通三方应用无法获得 `ohos.permission.INSTALL_BUNDLE`（`system_core`），也无法调用 `@ohos.bundle.installer`（`@systemapi`）。即使通过 ACL 声明权限，非系统应用调用系统 API 仍会得到 `202 Permission denied, non-system app called system api`。

2. **本机也没有“点 HAP 文件调起系统安装器”的公共路径。**
   这个 4.1.7.5 镜像没有带 UI 的文件管理器；`com.ohos.UserFile.ExternalFileManager` 只有 `fileAccess`/`backup` 扩展；`com.ohos.filepicker` 只声明 `OPEN_FILE`/`CREATE_FILE`；未发现处理 `application/vnd.ohos.hap` 或 install action 的系统组件。该能力属于 HarmonyOS NEXT 的文件管理器/系统安装器，不是 OH 4.1 的公共能力。

3. **本机可行的安装通道是宿主机 `hdc install` / `bm install`。**
   该设备是 debug/eng 构建：`hdc shell` 直接是 `uid=0(root)`，`const.debuggable=1`，SELinux `enforce=0`。`bm install -p <不存在路径>` 返回 `9568269 install file path invalid`，不是 `201/202` 权限错误，说明 shell/root 具备安装权限。

4. **推荐产品形态：设备端“应用中心”负责浏览/下载/校验/导出，PC 端 `hdc-agent` 负责自动安装。**
   设备端把校验通过的 HAP 放进自己的沙箱目录，PC 端 watcher 通过 `hdc` 拉取、复核 SHA256、`hdc install`，体验接近“一键”（前提是 PC 已连接且 agent 常驻）。没有 PC 时，本机无法完成安装。

5. **预置应用判断：**
   `com.laval.dispatchcenter` 是应用市场类（唯一带 `INSTALL_BUNDLE`，代码里用 `@ohos.bundle.installer` 下载并安装 HAP）；`com.ohos.updateapp` 是 OTA 系统更新；`com.laval.betaclub` 是开发者俱乐部。三者都能拉起，但服务端/内容不可用。

6. **唯一真·应用内一键安装的路线：** 把应用做成系统应用/刷入系统镜像（`system_core` + `INSTALL_BUNDLE`）。这超出“普通三方应用”范围，不建议作为本项目 MVP。

---

## 1. 安装权限结论（最重要）

### 1.1 `ohos.permission.INSTALL_BUNDLE` 的等级

OpenHarmony 4.1 官方权限文档（system apps 分册）对 `ohos.permission.INSTALL_BUNDLE` 的定义：

| 字段 | 值 |
| --- | --- |
| 描述 | 允许应用安装/卸载其他应用（不含企业 InHouse/MDM/Normal 应用） |
| Permission level | `system_core` |
| Authorization mode | `system_grant` |
| Enable via ACL | `true` |
| 起始版本 | 9 |

应用 APL 的等级顺序是 `normal < system_basic < system_core`。文档明确：`system_core` 只授予系统应用或 MDM 应用。普通三方应用默认 APL 为 `normal`，不能直接申请 `system_core` 权限。

ACL 的边界也要说清楚：

- ACL 文档写明，ACL 方式“只适用于调试阶段”，不能用于上架应用市场的商用版本。
- ACL 只是让低 APL 应用在**调试签名 profile** 里获得某个高等级权限；它不会把应用变成 `isSystemApp=true`。
- `@ohos.bundle.installer` 的接口定义里，非系统应用调用系统 API 会抛 `202 Permission denied, non-system app called system api`。
- 如果普通 HAP 在 `module.json5` 里直接声明 `INSTALL_BUNDLE`，BMS 预期会以 `17700054`（HAP requests wrong permissions）或权限校验失败拒绝安装；这一点建议在 M0 用测试包再确认一次。

### 1.2 `@ohos.bundle.installer` 是系统 API，不在公开 SDK

从 OpenHarmony 4.1 的 `interface_sdk-js` 拉取 `@ohos.bundle.installer.d.ts` 可以看到：

- `install(hapFilePaths, installParam)` 标注 `@systemapi`；
- `@permission ohos.permission.INSTALL_BUNDLE`；
- 错误码包括 `201`（无权限）、`202`（非系统应用调用系统 API）、`17700011`（签名校验失败）、`17700054`（请求了错误权限）等。

本机 4.1 SDK 的 `ets/api` 目录中没有 `@ohos.bundle.installer.d.ts`。这意味着：

- 用公开 SDK 的普通工程无法直接 `import installer from '@ohos.bundle.installer'`；
- 即使自己补 `.d.ts` 绕过编译，运行时仍会被系统 API 检查拦住；
- 必须使用 full/system SDK 且应用本身是系统应用，才具备可用的调用前提。

本文假设的 AppCenter 是 SDK 公开测试 CA 签名的普通应用（非系统签名、`isSystemApp=false`），因此上述两条路都不成立。

### 1.3 本机实测：谁有安装权限

`com.laval.dispatchcenter` 的 `bm dump -n` 关键字段：

| 字段 | 值 |
| --- | --- |
| `appPrivilegeLevel` | `system_core` |
| `isSystemApp` | `true` |
| `appDistributionType` | `os_integration` |
| `appProvisionType` | `release` |
| `reqPermissions` | `GET_INSTALLED_BUNDLE_LIST`、`INSTALL_BUNDLE`、`INTERNET`、`LISTEN_BUNDLE_CHANGE` |
| 证书指纹 | `161B018F761647414D959344141CAD4F48525DD8DA9B9286844ACED06781E879` |

`/system/etc/app/install_list_permissions.json` 里，`com.laval.dispatchcenter` 只额外列了 `GET_INSTALLED_BUNDLE_LIST`；`INSTALL_BUNDLE` 并不是通过这个文件授予的，而是因为它本身是 `system_core` 系统应用，`system_grant` 权限在安装时自动授予。

`com.ohos.updateapp` 虽然是系统应用，但 `appPrivilegeLevel=normal`，只有 `UPDATE_SYSTEM`，没有 `INSTALL_BUNDLE`；`com.laval.betaclub` 是 `system_core`，但权限列表里没有 `INSTALL_BUNDLE`。

### 1.4 本机实测：shell/root 可以安装

```text
$ hdc -t <serial> shell id
uid=0(root) gid=0(root) groups=0(root),1007(log),2000(shell),3009(readproc)

$ hdc -t <serial> shell "param get const.debuggable"
1

$ hdc -t <serial> shell "cat /sys/fs/selinux/enforce"
0

$ hdc -t <serial> shell "bm install -p /data/local/tmp/__no_such__.hap"
error: failed to install bundle.
code:9568269
error: install file path invalid.
```

这里的关键不是“路径不存在”，而是**错误码不是 201/202**。说明 `hdcd` 拉起的 root shell 具备 `INSTALL_BUNDLE` 所需的令牌能力，宿主机的 `hdc install` / `hdc shell bm install` 通道可用。

注意：这是 debug/eng 构建（`debuggable=1`、SELinux permissive、root shell）。零售机是否仍能 root shell、是否需要开发者模式/USB 调试授权，需要在目标机上另测。本文的“宿主机安装可用”结论只对本机成立。

### 1.5 手动点 HAP 为什么不行

本机与“文件管理器/安装器”相关的组件只有：

| 组件 | 能力 | 是否安装 UI |
| --- | --- | --- |
| `com.ohos.UserFile.ExternalFileManager` | `fileAccess` 扩展、`backup` 扩展 | 否，没有 UIAbility |
| `com.ohos.filepicker` | `MainAbility`，skills 仅 `ohos.want.action.OPEN_FILE`、`ohos.want.action.CREATE_FILE` | 是，但只是文件选择/保存 |
| `com.ohos.updateapp` | OTA 系统更新，`UPDATE_SYSTEM` | 是，但只做系统更新 |
| `com.ohos.settings` / `com.ohos.launcher` | 申请了 `INSTALL_BUNDLE`，用于应用管理/卸载等 | 否，没有“从文件安装”的入口 |
| `com.ohos.amsdialog` | Selector/Tips/JumpInterceptor/SwitchUser 系统对话框 | 否 |
| `com.ohos.devicemanagerui` | 设备管理 UI | 否 |

结论：

- 本机没有“文件管理器点 HAP → 系统安装器”的公共路径。
- `filepicker` 只是把文件 URI 返回给调用方，不会安装。
- `aa` CLI 不支持只按 action 隐式启动（需要 `-a`/`-b`），也没有可用的 install handler 可供测试。
- 不能把 HarmonyOS NEXT 的“开发者模式 → 本地安装 → 选文件”直接套到 OH 4.1；本机没有对应的系统安装器 UI。

### 1.6 替代路径评估

| 路径 | 是否可行 | 前提 | 说明 |
| --- | --- | --- | --- |
| 应用内调用 `@ohos.bundle.installer` | 否 | 系统应用 + `INSTALL_BUNDLE` | 普通应用不可用；`@systemapi` |
| 应用内声明 `INSTALL_BUNDLE` | 否 | `system_core` APL / 系统签名 | 普通应用预期被 `17700054` 拒绝；ACL 仅调试且不改变 `isSystemApp` |
| `bm install` | 是 | shell/root | 本机 `hdc shell` 为 root，已验证权限通道 |
| `hdc install` | 是 | 宿主机 + USB/无线 hdc + 授权 | 本机最现实的安装方式 |
| 用户点 HAP 文件 | 否 | 系统文件管理器/安装器 | 本机没有该组件 |
| 第三方装机工具转交（Want） | 条件可行 | 已安装支持 OH 4.1 的装机工具 | 本机未发现 `openharmony.package` handler；`auto-installer` 主要面向 HarmonyOS NEXT |
| 复用 `com.laval.dispatchcenter` | 技术上有黑路径 | root、hosts/DNS、HTTP 目录伪造 | 它是系统应用且有安装权限，但目录协议是私有 HTTP，服务端已死，风险高，不建议产品化 |
| 系统应用/刷 ROM | 是 | 改系统镜像/系统签名 | 唯一真·一键安装，超出普通应用范围 |

---

## 2. 现状实测

### 2.1 设备基础信息

| 项 | 值 |
| --- | --- |
| 型号 | `LHT16` |
| 系统 | `OpenHarmony-4.1.7.5` |
| API | 11 |
| 内核 | `Linux 5.15.74-ab19 aarch64` |
| ABI | `arm64-v8a` |
| 构建 | `const.debuggable=1`，开发者模式 `true`，SELinux `enforce=0` |
| Bundle 数 | 约 53 个条目（用户 100） |
| hdc | `1.3.0a`（`$OHOS_TOOLS/sdk/openharmony/toolchains/hdc.exe`） |
| 设备序列号 | `<device-serial>`（本机实测，已脱敏） |

### 2.2 三个预置应用

| 应用 | 版本 | APL | 系统应用 | 关键权限 | 拉起结果 | 实际 UI | 判断 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `com.ohos.updateapp` | `204.0.0.108` | `normal` | 是 | `UPDATE_SYSTEM`、`GET_NETWORK_INFO`、`START_ABILITIES_FROM_BACKGROUND` | 成功 | “软件更新 2.0.613 / 正在检查更新” | OTA 系统更新，不是应用市场 |
| `com.laval.betaclub` | `1.0.19` | `system_core` | 是 | `GET_BUNDLE_INFO`、`INTERNET`、`READ_MEDIA`、`READ_IMAGEVIDEO`、`START_INVISIBLE_ABILITY`、`sec.ACCESS_UDID` | 成功 | “DeveloperClub”，空白 + 刷新按钮 | 开发者俱乐部，不是应用市场 |
| `com.laval.dispatchcenter` | `1.0.7` | `system_core` | 是 | `INSTALL_BUNDLE`、`GET_INSTALLED_BUNDLE_LIST`、`LISTEN_BUNDLE_CHANGE`、`INTERNET` | 成功 | 空白内容页 + 底部“应用 / 我的” | 应用市场/分发中心，服务端不可用 |

三者都通过 `aa start` 成功拉起：

```text
aa start -a com.ohos.updateapp.MainAbility -b com.ohos.updateapp
aa start -a EntryAbility -b com.laval.betaclub
aa start -a EntryAbility -b com.laval.dispatchcenter
```

#### 2.2.1 `com.ohos.updateapp`

- HAP：`/system/app/com.ohos.updateapp/UpdateApp.hap`
- Ability：`com.ohos.updateapp.MainAbility`（PAGE）、`ServiceExtAbility`（service）、`Subscriber`（staticSubscriber）
- 权限：`GET_NETWORK_INFO`、`START_ABILITIES_FROM_BACKGROUND`、`UPDATE_SYSTEM`
- 结论：系统 OTA 更新器；`UPDATE_SYSTEM` 不等于 `INSTALL_BUNDLE`，不能用来安装普通 HAP。

#### 2.2.2 `com.laval.betaclub`

- HAP：`/system/app/com.laval.betaclub/DeveloperClub.hap`
- Ability：`EntryAbility`
- 权限：`GET_BUNDLE_INFO`、`GET_NETWORK_INFO`、`INTERNET`、`KEEP_BACKGROUND_RUNNING`、`READ_IMAGEVIDEO`、`READ_MEDIA`、`SET_NETWORK_INFO`、`START_INVISIBLE_ABILITY`、`sec.ACCESS_UDID`
- UI：标题 `DeveloperClub`，右上角 `+`，页面中间“刷新”和空状态插图。
- 结论：开发者俱乐部/运营 App，没有安装能力。

#### 2.2.3 `com.laval.dispatchcenter`

- HAP：`/system/app/com.laval.dispatchcenter/DispatchCenter.hap`
- Ability：`EntryAbility`（exported）
- 权限：`GET_INSTALLED_BUNDLE_LIST`、`INSTALL_BUNDLE`、`INTERNET`、`LISTEN_BUNDLE_CHANGE`
- 从 `modules.abc` 提取到的关键字符串：
  - `@ohos:bundle.installer`
  - `getBundleInstallerSync`
  - `install filesPath`
  - `downloadHap enter, dowmloadUrl`
  - `requestUrlSync`
  - `haps` / `hsps`
  - `http://dispatchcenter.laval.aidog.club/home.json`
- 结论：这是唯一的“应用市场”类应用：从 `home.json` 拉目录，下载 HAP，调用 `bundle.installer` 安装。但它依赖的 `dispatchcenter.laval.aidog.club` 当前 DNS 解析失败，页面空白，不能作为可用服务端。

### 2.3 系统组件与安装能力

- `com.ohos.UserFile.ExternalFileManager`：`appPrivilegeLevel=normal`，只有 `fileAccess`/`backup` 扩展，没有 UIAbility。
- `com.ohos.filepicker`：`system_basic`，`MainAbility` 的 skills 只有 `ohos.want.action.OPEN_FILE`、`ohos.want.action.CREATE_FILE`。
- `com.ohos.settings`：申请了 `INSTALL_BUNDLE`，但用于应用信息/卸载等管理场景，没有“从文件安装”的公开入口。
- `com.ohos.launcher`：同样申请了 `INSTALL_BUNDLE`，用于桌面应用管理/卸载，不是安装器。
- `com.ohos.amsdialog`：Selector/Tips/JumpInterceptor/SwitchUser 对话框，不处理 HAP 安装。
- `com.ohos.devicemanagerui`：设备管理 UI，不是安装器。
- `com.ohos.updateapp`：OTA 更新器，不处理普通 HAP。

`bm install` 的用法（本机）：

```text
bm install -p <hap-path> [-r] [-u <user-id>] [-w <180-600s>]
```

`hdc install` 是宿主机命令，直接把 PC 上的 HAP 推到设备并安装。本机通道存在，实际安装需在 M0 用测试 HAP 验证。

### 2.4 网络实测

宿主机（PowerShell，2026-11-17）对几个候选地址的探测：

| URL | 结果 |
| --- | --- |
| `https://gh-proxy.com/https://raw.githubusercontent.com/...` | 200 |
| `https://ghproxy.net/https://raw.githubusercontent.com/...` | 200 |
| `https://ghfast.top/https://raw.githubusercontent.com/...` | 超时 |
| `https://cdn.jsdelivr.net/gh/...` | 503（当前不可用） |
| `https://raw.githubusercontent.com/...` | 200（宿主机） |
| `https://store.iparo.app/` | 200 |

设备侧：

- 设备上没有 `curl` / `wget`，只有 `ping`；无法在 shell 里直接做 HTTPS 探测。
- `ping` 能解析上述域名并拿到 IP；部分地址能 ping 通，部分（如 Cloudflare 的 `gh-proxy.com`）只解析不回 ICMP。ICMP 可达不等于 HTTPS 可用。
- 按用户实测约束：**GitHub raw 直连常失败，`gh-proxy.com` 可用，`*.workers.dev` 不可达**。方案必须以这个约束为前提，不能假设 GitHub 直连稳定。

因此设备端必须实现：

- 多镜像模板（前缀式）；
- 失败自动换链路；
- 目录/快照本地缓存（离线可浏览）；
- 不依赖 `*.workers.dev`；
- 镜像列表可远程更新（避免 App 发版才能换镜像）。

---

## 3. 候选方案对比

| 方案 | 应用内一键安装 | 前提 | 用户体验 | 主要风险 | 工作量 | 结论 |
| --- | --- | --- | --- | --- | --- | --- |
| A. 纯应用内安装 | 否 | 系统应用 + `system_core` + `INSTALL_BUNDLE` | 原生 | 本机不可能 | - | 放弃 |
| B. 应用 + 宿主机 `hdc-agent` | 是（自动，需 PC） | USB/无线 hdc + 授权 + PC 常驻 | 设备点下载，PC 自动装 | 依赖 PC/线；零售机授权未知 | 中 | **推荐** |
| C. 应用 + 第三方装机工具转交 | 条件可行 | 已装支持 OH 4.1 的装机工具 | 设备内完成 | 生态缺失；本机无 handler | 低 | 备选 |
| D. 复用 `com.laval.dispatchcenter` | 技术上是（黑路径） | root + hosts/DNS + 伪造 HTTP 目录 | 无 PC | 私有协议、服务端已死、安全/合规风险 | 高 | 仅研究 |
| E. 系统应用/刷 ROM | 是 | 改系统镜像/系统签名 | 原生 | 高风险、维护成本高 | 很高 | 长期 |
| F. 纯下载站（无安装） | 否 | 浏览器/文件管理器 | 手动 | 本机无文件管理器，仍需 PC | 低 | 降级 |

### 3.1 推荐形态

```text
┌──────────────────────────────┐        USB / 无线 hdc        ┌──────────────────────────┐
│ LHT16 设备端 AppCenter       │  <─────────────────────────>  │ PC 端 hdc-agent          │
│ - 拉取 index.json            │                               │ - 轮询设备沙箱目录       │
│ - 浏览/搜索/详情             │                               │ - 拉取 .hap + .ready     │
│ - 下载 .hap 到沙箱           │                               │ - 复核 SHA256/签名       │
│ - SHA256/大小校验            │                               │ - hdc install -r         │
│ - 导出到用户目录             │                               │ - 写回安装结果           │
│ - 安装引导/状态              │                               │ - 日志/重试              │
└──────────────────────────────┘                               └──────────────────────────┘
```

设备端只做“可审计的下载器 + 校验器 + 安装队列”，不碰系统安装权限；PC 端是“安装执行器”。这样：

- 不违反 OH 4.1 的权限模型；
- 本机 `hdc` root shell 已验证可安装；
- 设备端代码简单，零三方依赖；
- 未来如果设备变成系统应用/ROM，可把 PC 端替换成应用内 `bundle.installer`，设备端数据/索引/校验逻辑可复用。

---

## 4. 开源项目调研

克隆/评估目录：临时目录 `opencode/appcenter-research/repos/`（仅调研，未复制进本仓）。

说明：Gitee 的仓库搜索页是前端渲染，公开搜索 API 未返回可用结果；因此以 GitHub 项目为主，并额外克隆了 HapLane 的 Gitee 镜像仓（`gitee-haplane-registry`）确认国内可访问性。

| 项目 | 类型/目标 | 可复用点 | 结论 |
| --- | --- | --- | --- |
| [zhailinlang/hapstore](https://github.com/zhailinlang/hapstore) | HarmonyOS NEXT 应用商店 App（API 26） | 目录快照 + manifest 指针 + 镜像测速/自动回退 + `.part` 下载 + SHA256/大小校验 + 安装引导 + 下载记录 | 最接近目标 UX；但用 `@kit.*`、API 26，依赖 NEXT 系统安装器/第三方装机工具，不能直接跑在 OH 4.1 |
| [LeonTing1010/haplane-registry](https://github.com/LeonTing1010/haplane-registry) | 只索引、不托管 HAP 的注册表 + CLI | `index.json` schema、SHA256、`upstreamRelease`、`discoveryOnly`、CI 校验、license 白名单 | 索引契约和校验脚本可直接借鉴 |
| [eclipse-oniro4openharmony/oniro-app-store-actions](https://github.com/eclipse-oniro4openharmony/oniro-app-store-actions) | GitHub Actions 构建/签名/发布到 Oniro App Store | 无 secret 的 OIDC 发布、`oniro-app` 安装 OH SDK、签名、release 资产、构建/发布分离 | CI 流水线参考；商店本身是中心化服务，不是静态仓库 |
| [qius-code/hap-distribution](https://github.com/qius-code/hap-distribution) | GitHub Pages/jsDelivr HAP 分发 | `manifest.json5` 的 `packageHash`/`sign`/`deployDomain`、Range 说明、部署脚本 | 静态托管参考；但依赖 Cloudflare Pages/Workers/jsDelivr，本机网络下不可靠 |
| [XiaoChuangll/OpenStore](https://github.com/XiaoChuangll/OpenStore) | Vue 3 + Express + SQLite 的 Web 应用商店 | 分类/榜单/投稿/后台的产品设计 | 需要服务器，不是零成本静态方案；与设备端集成弱 |
| [PureHarmonyProject/Aptoide-OHOS](https://github.com/PureHarmonyProject/Aptoide-OHOS) | 号称 Aptoide 的 OHOS 商店 | 无（仓库只有 README/LICENSE） | 不可用 |
| [shihuan1999/ondevice-hap-dev](https://github.com/shihuan1999/ondevice-hap-dev) | 设备本机 HAP 构建/签名/安装工具链 | `bm install` 路径、`withtoken` 借用 hdcd 令牌、安装失败码经验 | 证明“设备本机安装”仍要 `bm install`/令牌；不是普通 App 能力 |
| [shihuan1999/ohos-apps](https://github.com/shihuan1999/ohos-apps) | 面向设备应用商店的 GitHub Release HAP 仓 | Release 资产 + 版本管理 | 可作为“GitHub Releases 作为 HAP 源”的参考 |
| [likuai2010/auto-installer](https://github.com/likuai2010/auto-installer) | HarmonyOS 侧装机助手（内置 hdc 客户端） | HapStore 的 Want 转交目标（`openharmony.package`） | 主要面向 HarmonyOS NEXT；未验证 OH 4.1/API 11 |
| [Zitann/HarmonyOS-Haps](https://github.com/Zitann/HarmonyOS-Haps) | 社区 HAP 清单 | 应用元数据/分类 | 数据源参考，需自行筛选 OH 4.1 兼容项 |

### 4.1 关键结论

- **没有现成项目能在本机实现普通应用内安装 HAP。** 所有“商店”最终都落到系统安装器/第三方装机工具/`bm install`。
- HapStore 的产品结构最值得抄：`manifest.json` 指针（约 700B）→ `apps.json` 快照（数百 KB）→ 镜像测速/失败回退 → 沙箱 `.part` → 校验 → 导出/转交。它的 README 也明确写了“鸿蒙不允许第三方应用静默安装，最后一步必须你在系统安装器上确认一次”。这句话在 OH 4.1 本机上更严重：连系统安装器 UI 都没有。
- HapLane 的“只索引不托管、SHA256 强校验、CI 机检”适合做仓库契约。
- Oniro 的 GitHub Actions 适合做“源码仓 → 构建/签名 → Release”的零成本 CI 模板。

---

## 5. 静态仓库分发方案

### 5.1 总览

```text
GitHub 仓库（唯一事实源）
  ├─ index.json / index.json.sig
  ├─ icons/*.png
  ├─ apps/<bundle>/<versionCode>/*.hap
  ├─ schemas/index.schema.json
  ├─ scripts/build-index.mjs / validate-index.mjs
  └─ .github/workflows/validate.yml / publish.yml
        │
        ├─ raw.githubusercontent.com（canonical）
        ├─ gh-proxy.com / ghproxy.net（前缀镜像）
        ├─ Gitee 镜像仓（国内备用）
        └─ GitHub Pages（可选，静态页面/下载页）
```

零成本原则：

- 服务端只用 GitHub 仓库 + raw/Pages，不租服务器、不跑数据库；
- CI 只做校验/索引/发布，构建可本地做也可 GitHub Actions 做；
- 设备端不依赖任何在线 API（GitHub API 有 60 次/小时/IP 限制），只拉静态文件；
- 镜像列表内置默认值，并允许从 `index.json` 或远程小文件更新。

### 5.2 仓库结构

```text
ohos-appcenter-index/
├─ index.json
├─ index.json.sig                  # 可选：ECDSA P-256 对 index.json 原始字节签名
├─ client.json                     # 可选：客户端自更新信息（也可并入 index.json）
├─ apps/
│  └─ com.example.app/
│     ├─ 1002003/
│     │  ├─ com.example.app-1.2.3-arm64.hap
│     │  └─ com.example.app-1.2.3-arm64.meta.json
│     └─ 1002002/
│        └─ ...
├─ icons/
│  └─ com.example.app.png          # 128x128 / 256x256，建议 <20KB
├─ schemas/
│  └─ index.schema.json
├─ scripts/
│  ├─ build-index.mjs              # 扫描 HAP/metadata，生成 index.json
│  └─ validate-index.mjs           # 零依赖校验（Node 18+）
├─ .github/workflows/
│  ├─ validate.yml                 # PR/push 校验
│  └─ publish.yml                  # tag/手动发布
├─ docs/
│  └─ PUBLISHING.md
└─ README.md
```

HAP 放置策略：

- **MVP（少量应用）**：HAP 直接放 `apps/`，用 raw URL，路径稳定、镜像友好。
- **规模化（>50 个或单包 >20MB）**：HAP 放 GitHub Releases，`index.json` 里存 `downloadUrl` + `sha256` + `sizeBytes`；`gh-proxy` 会跟随 Release 重定向，但要实测。部分镜像不代理 `objects.githubusercontent.com`，所以 raw 仍是更可控的主路径。
- 不建议 Git LFS：raw/LFS 带宽和镜像兼容性都更差。

### 5.3 `index.json` 契约（schema v1）

```json
{
  "schemaVersion": 1,
  "generatedAt": "2026-11-17T00:00:00Z",
  "channel": "stable",
  "minAppVersionCode": 1000000,
  "repo": "owner/ohos-appcenter-index",
  "mirrors": [
    { "id": "direct", "name": "GitHub 直连", "template": "" },
    { "id": "gh-proxy", "name": "gh-proxy.com", "template": "https://gh-proxy.com/{url}" },
    { "id": "ghproxy.net", "name": "ghproxy.net", "template": "https://ghproxy.net/{url}" }
  ],
  "client": {
    "versionCode": 1000001,
    "versionName": "1.0.1",
    "minAPIVersion": 11,
    "hap": "apps/com.example.appcenter/1000001/com.example.appcenter-1.0.1-arm64.hap",
    "sha256": "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
    "sizeBytes": 1234567,
    "publishedAt": "2026-11-17T00:00:00Z",
    "releaseNotes": "首个版本"
  },
  "apps": [
    {
      "id": "com.example.app",
      "bundleName": "com.example.app",
      "name": "示例应用",
      "summary": "一句话简介",
      "description": "长描述，支持换行。",
      "developer": "Example",
      "license": "Apache-2.0",
      "source": "https://github.com/example/app",
      "category": "工具",
      "tags": ["离线", "轻量"],
      "icon": "icons/com.example.app.png",
      "iconSha256": "abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789",
      "deviceTypes": ["phone", "tablet"],
      "latest": {
        "versionName": "1.2.3",
        "versionCode": 1002003,
        "minAPIVersion": 10,
        "targetAPIVersion": 11,
        "abi": "arm64-v8a",
        "deviceTypes": ["phone", "tablet"],
        "sizeBytes": 1234567,
        "sha256": "89abcdef0123456789abcdef0123456789abcdef0123456789abcdef01234567",
        "hap": "apps/com.example.app/1002003/com.example.app-1.2.3-arm64.hap",
        "downloadUrl": "https://raw.githubusercontent.com/owner/ohos-appcenter-index/main/apps/com.example.app/1002003/com.example.app-1.2.3-arm64.hap",
        "signature": {
          "scheme": "openharmony-hap",
          "subject": "C=CN,O=OpenHarmony,OU=OpenHarmony Team,CN=OpenHarmony Application Release",
          "issuer": "C=CN,O=OpenHarmony,OU=OpenHarmony Team,CN=OpenHarmony Application CA",
          "fingerprintSha256": "eeb00e63401c85853f677a73c6f12ccb7c53692d44caf459994bb2ce5a47a94d",
          "notAfter": "2049-12-31T20:15:32Z"
        },
        "publishedAt": "2026-11-17T00:00:00Z",
        "releaseNotes": "修复...",
        "installMode": "hdc"
      },
      "history": [
        {
          "versionName": "1.2.2",
          "versionCode": 1002002,
          "sha256": "fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210",
          "hap": "apps/com.example.app/1002002/com.example.app-1.2.2-arm64.hap",
          "publishedAt": "2026-10-01T00:00:00Z"
        }
      ],
      "revoked": false,
      "revokedReason": ""
    }
  ]
}
```

字段说明：

| 字段 | 必填 | 说明 |
| --- | --- | --- |
| `schemaVersion` | 是 | 契约版本，当前 1 |
| `generatedAt` | 是 | 索引生成时间（UTC） |
| `channel` | 是 | `stable` / `beta`，设备端可切换 |
| `minAppVersionCode` | 是 | 低于此版本的客户端必须先升级，避免解析不了新字段 |
| `repo` | 是 | `owner/repo`，用于生成镜像 URL |
| `mirrors` | 是 | 前缀式镜像模板，`{url}` 占位；空模板表示直连 |
| `client` | 否 | 客户端自更新信息 |
| `apps[].id` | 是 | 稳定唯一 ID；建议直接用 bundleName |
| `apps[].bundleName` | 是 | HAP 的 bundleName |
| `apps[].latest.versionCode` | 是 | 必须递增；系统安装对降级会报 `17700047` |
| `apps[].latest.minAPIVersion` | 是 | 设备端过滤：`<= 11` 才显示“兼容” |
| `apps[].latest.abi` | 是 | 本机只支持 `arm64-v8a` |
| `apps[].latest.sha256` | 是 | HAP 文件 SHA256（小写 hex） |
| `apps[].latest.sizeBytes` | 是 | 下载后先校验大小，再算哈希 |
| `apps[].latest.hap` | 是 | 仓库内相对路径，禁止 `..`、绝对路径 |
| `apps[].latest.downloadUrl` | 是 | canonical 绝对 URL（raw 或 Release） |
| `apps[].latest.signature` | 建议 | 从 `hap-sign-tool verify-app` 提取的签名者信息 |
| `apps[].latest.installMode` | 是 | 本方案固定 `hdc`（因为应用内不能装） |
| `apps[].revoked` | 否 | 下架/阻断；设备端应隐藏或显示“已下架” |
| `history` | 否 | 旧版本，供回滚/审计；设备端默认只显示 latest |

校验规则（`validate-index.mjs`）：

1. `schemaVersion === 1`；
2. `id` / `bundleName` 唯一；
3. `latest.versionCode` 大于 `history` 中的最大值；
4. `sha256` 为 64 位小写 hex；`sizeBytes` 与文件实际大小一致；
5. `hap` 是相对路径、以 `.hap` 结尾、不含 `..`；
6. `downloadUrl` 是 `https://`，host 在允许列表（`raw.githubusercontent.com`、`github.com`、`gitee.com`、`cdn.jsdelivr.net`、`gh-proxy.com`、`ghproxy.net`）；
7. `minAPIVersion <= 11`（OH 4.1 通道）；
8. `deviceTypes` 包含 `phone` 或 `tablet`；
9. 已下架条目必须有 `revokedReason`；
10. 图标存在且 < 100KB；
11. 可选：`module.json` 里不能声明 `system_core` 权限（避免装不上）。

### 5.4 URL / 镜像策略

设备端把 canonical URL 改写为镜像 URL：

```text
mirror(template, url) = template.replaceAll("{url}", url)
```

默认镜像优先级：

1. `direct`：`raw.githubusercontent.com/...`
2. `gh-proxy`：`https://gh-proxy.com/<raw-url>`
3. `ghproxy`：`https://ghproxy.net/<raw-url>`
4. `gitee`：如果维护了 Gitee 镜像仓，直接用 Gitee raw 基址 + 相对路径
5. `custom`：用户自定义前缀模板（设置页可编辑）

明确不推荐：

- `*.workers.dev`（用户实测不可达）；
- 把 `cdn.jsdelivr.net` 当主链路（本机宿主机实测 503，且国内波动大）；
- 把 `ghfast.top` 当默认（本机宿主机实测超时，可作为可选）；
- 依赖 GitHub API 做目录（未鉴权 60 次/小时/IP，移动网络 NAT 下很容易耗尽）。

镜像不是永久可信的，所以：

- 镜像列表放在 `index.json` 的 `mirrors` 字段，App 每次刷新目录时更新；
- App 内置一份默认镜像作为兜底（避免“镜像更新文件本身拉不到”的死锁）；
- 下载失败自动换下一条链路；
- 设置页提供“测速”，用真实 HAP 的 Range 请求测，不要用 README。

### 5.5 设备端拉取与缓存

推荐两级结构（借鉴 HapStore）：

```text
client 启动
  ├─ 读 rawfile/index.snapshot.json（内置快照，离线可浏览）
  ├─ 异步拉 index.json（小文件）
  │   ├─ 校验 schema / 可选签名
  │   ├─ 比较 generatedAt 或 sha256
  │   └─ 有变化才替换本地缓存
  ├─ 拉图标（按需，懒加载，失败用占位图）
  └─ 用户下拉刷新 / 定时检查
```

要点：

- 首次启动不空白：内置快照至少包含应用列表和图标 URL；
- 索引很小（100 个应用约 50-100KB），不需要分页；
- 如果索引变大，可加 `manifest.json` 指针：`{snapshot:{url,size,sha256,generatedAt}, client:{...}}`，App 先拉指针再决定是否拉快照；
- 缓存写入用“临时文件 + rename”，避免半截 JSON；
- 缓存损坏时回退到内置快照；
- 记录 `lastCheckAt`，避免每次启动都打网络。

### 5.6 下载、校验、失败回退

状态机：

```text
IDLE -> RESOLVING -> DOWNLOADING -> VERIFYING -> READY -> EXPORTED -> INSTALL_WAIT -> INSTALLED
                                      |            |
                                      v            v
                                   FAILED       REJECTED
```

实现建议：

1. 下载到沙箱 `filesDir/hap/<name>.hap.part`；
2. 用 `@ohos.request` 的 `downloadFile`（简单）或 `request.agent`（暂停/续传/进度）；
3. 进度回调更新 UI 和 `downloads.json`；
4. 完成后先比较 `sizeBytes`，再用 `@ohos.file.hash` 算 SHA256；
5. 哈希不匹配：标记失败、保留 `.part` 供排查、换镜像重试一次；
6. 通过后 rename 成正式 `.hap`；
7. 写 sidecar `.ready.json`（bundleName、versionCode、sha256、size、time）；
8. 等 PC agent 安装，或用户点“导出”。

失败回退：

- 下载失败 → 当前镜像重试 1 次 → 换下一条镜像；
- 所有镜像失败 → 提示“网络/镜像不可用”，保留已下载部分（如果支持 Range）；
- 哈希失败 → 删除或隔离文件，换镜像重下；
- 版本降级 → 提示“已安装更高版本”，不下载/不安装；
- 空间不足 → 提前用 `statfs` 检查，提示清理；
- 文件名非法 → 统一 sanitize（`/ \ : * ? " < > |` 替换为 `_`）。

### 5.7 签名/证书校验能做到什么程度

| 校验项 | 应用内 | CI/宿主机 | 说明 |
| --- | --- | --- | --- |
| 文件大小 | 是 | 是 | 下载后 `stat` |
| SHA256 | 是 | 是 | `@ohos.file.hash` / `sha256sum` |
| HAP 内 `module.json` 的 bundleName/versionCode/minAPI | 可选（解压后读） | 是 | `@ohos.zlib` 解压；签名数据可能附加在 ZIP 末尾之后 |
| HAP 代码签名（PKCS#7/证书链） | 否（公开 SDK 无直接 API） | 是 | `hap-sign-tool verify-app -inFile x.hap -outCertChain ... -outProfile ...` |
| 签名者证书指纹 | 可展示（来自 index） | 是 | CI 从 `verify-app` 提取，写入 index |
| 索引本身防篡改 | 可选（ECDSA 验签） | 是（签名） | `cryptoFramework.createVerify` + 内置公钥 |
| 系统安装时的最终验签 | 系统负责 | - | 安装失败会报 `17700011`/`17700048` |

HAP 签名格式的实测结论：

- 用 kiosk 的 `entry-signed.hap` 与 `entry-unsigned.hap` 对比，ZIP 条目完全相同；
- 签名后的文件比未签名大 5,567 字节；ZIP 条目完全相同，说明签名数据不是 ZIP 内条目，而是附加在 ZIP 数据之后的签名块（未逐字节验证偏移）；
- `hap-sign-tool verify-app` 能验证成功，输出证书链 SHA256、`SHA384withECDSA`、`Digest verify result: true`。

因此：

- **应用内做完整 HAP 代码签名验证不现实**：需要解析 ZIP 数据之后的签名块、PKCS#7、证书链和摘要校验；公开 SDK 没有现成 API，自己实现成本高且容易出错。
- **应用内可以做**：SHA256 + 大小 + 索引字段一致性 + 展示签名者指纹 + 可选索引签名。
- **最终验签交给系统安装器**：`hdc install`/`bm install` 会做签名校验；失败会返回 `17700011`/`17700048`。
- **信任根**：设备信任 `trusted_apps_sources.json` 里的 OpenHarmony/Huawei 证书；本机 kiosk 应用就是测试证书签名并已安装。但“公开测试 CA”不是身份信任边界（谁都能签）。真正的 allowlist 是 `index.json` 里的 `signature.fingerprintSha256`；CI/宿主机 agent 必须校验它。

索引签名（可选，Phase 2）：

- CI 用离线 ECDSA P-256 私钥对 `index.json` 原始字节签名，生成 `index.json.sig`；
- App 内置公钥，启动时用 `cryptoFramework.createVerify('ECC|SHA256')` 验签；
- 这样即使 GitHub 仓库被篡改，攻击者也无法伪造目录（除非同时改 App 内置公钥）；
- 私钥放 GitHub Secrets 或本地离线，不入库；
- 如果暂时不做，至少用 HTTPS + 仓库权限 + 每个 HAP 的 SHA256 + 系统验签，接受“仓库被攻破”的残余风险。

### 5.8 安装路径设计

#### B1. 宿主机 `hdc-agent`（推荐）

设备端：

- 把校验通过的 HAP 放在 `filesDir/haps/`（实际路径类似 `/data/app/el2/100/base/<bundle>/haps/`）；
- 同时写 `<file>.ready.json`，包含 `bundleName`、`versionCode`、`sha256`、`sizeBytes`、`createdAt`；
- UI 显示“等待电脑安装”，并提供“复制 hdc 命令”/“导出到下载目录”。

PC 端：

```powershell
# 伪代码，详见附录 C
$serial = "<device-serial>"
$dir = "/data/app/el2/100/base/com.example.appcenter/haps"
while ($true) {
  $ready = hdc -t $serial shell "ls $dir/*.ready.json 2>/dev/null"
  foreach ($r in $ready) {
    $meta = hdc -t $serial shell "cat $r" | ConvertFrom-Json
    $hapRemote = $r -replace '\.ready\.json$', '.hap'
    hdc -t $serial file recv $hapRemote "$env:TEMP\$($meta.bundleName).hap"
    # 校验 SHA256 / 可选签名
    hdc -t $serial install "$env:TEMP\$($meta.bundleName).hap"
    hdc -t $serial shell "mv $r $dir/.done/"
  }
  Start-Sleep -Seconds 3
}
```

优点：

- 不需要 root 写系统分区；
- 不需要应用内安装权限；
- 本机已验证 `hdc` root shell 具备安装权限（实际安装待 M0 冒烟）；
- 设备端只读/写自己的沙箱，安全边界清晰。

缺点：

- 需要 PC 常驻 + USB/无线 hdc；
- 安装结果回传要额外设计（agent 可写 `.result.json` 到同一目录）；
- 零售机的 hdc 授权/开发者模式可能不同。

#### B2. 手动导出 + `hdc install`

- App 用 `DocumentViewPicker.save()` 让用户选保存位置；
- 用 `fileIo.copyFile` 把沙箱 HAP 复制到用户 URI；
- 用户在 PC 上执行：

```powershell
hdc install .\com.example.app-1.2.3-arm64.hap
```

适合低频安装/调试；体验不如 B1。

#### B3. 局域网队列（可选）

- App 启动一个本地 HTTP 服务（例如 `0.0.0.0:18080`），提供 `/queue` 和 `/hap/<id>`；
- PC agent 通过 `http://<device-ip>:18080/queue` 拉取并安装；
- 不依赖 USB，但依赖同一 Wi-Fi、IP 发现、端口安全；
- 需要 `@ohos.net.socket`，MVP 可不做。

#### B4. 第三方装机工具转交（条件可行）

HapStore 的做法是：

```ts
const want: Want = {
  action: 'ohos.want.action.viewData', // 或 sendData
  uri: fileUri.getUriFromPath(hapPath),
  type: 'openharmony.package',
  flags: wantConstant.Flags.FLAG_AUTH_READ_URI_PERMISSION
};
await ctx.startAbility(want);
```

本机未发现能处理 `openharmony.package` 的组件；`auto-installer` 主要面向 HarmonyOS NEXT。可以保留这个“探测 + 降级”逻辑：

- 尝试 `startAbility`；
- `16000001`（ability 不存在）/`16000050`（无匹配）→ 判定“未安装装机工具”；
- 引导用户安装兼容的装机工具（如果有）；
- 否则回退到 B1/B2。

#### B5. 复用 `com.laval.dispatchcenter`（仅研究）

技术链路：

1. 它是 `system_core` 系统应用，拥有 `INSTALL_BUNDLE`；
2. 代码从 `http://dispatchcenter.laval.aidog.club/home.json` 拉目录；
3. 目录里有 `haps`/`hsps`，它下载 HAP 后调用 `bundle.installer.install(filesPath)`；
4. 如果能在设备上把该域名指到自己的 HTTP 服务（hosts/iptables，需要 root），并伪造 `home.json`，理论上可以让它安装任意 HAP。

不建议产品化：

- 私有协议/字段未公开，需要逆向；
- 依赖一个已停止维护的厂商应用；
- 修改 hosts/系统配置、绕过原有服务，属于高风险操作；
- 可能违反厂商条款/安全策略；
- 设备重启/OTA 后可能失效。

### 5.9 服务端零成本托管与 CI

#### 托管

- 代码/索引/HAP：GitHub 公开仓库（免费）；
- 目录/图标/HAP：GitHub raw（canonical）+ `gh-proxy`/`ghproxy.net` 镜像；
- 国内备用：Gitee 镜像仓（同步 `index.json` + HAP，把 `downloadUrl` 改写为 Gitee raw；或只同步索引、HAP 继续走 gh-proxy）；
- 可选：GitHub Pages 做一个人可读的下载页（不依赖 Workers）；
- 不租服务器、不跑数据库、不用 `*.workers.dev`。

#### CI 方案 A：只校验/索引（推荐先做）

触发：PR / push / tag。

```yaml
name: validate-index
on:
  pull_request:
  push:
    branches: [main]
permissions:
  contents: read
jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: '20'
      - run: node scripts/validate-index.mjs
```

发布时（tag）：

```yaml
name: publish-index
on:
  push:
    tags: ['app-v*']
permissions:
  contents: write
jobs:
  publish:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: '20'
      - run: node scripts/validate-index.mjs
      - run: node scripts/build-index.mjs
      - run: |
          git config user.name "github-actions"
          git config user.email "github-actions@users.noreply.github.com"
          git add index.json icons apps
          git commit -m "index: $GITHUB_REF_NAME" || true
          git push
```

HAP 由本地 DevEco 构建/签名后提交，或由 `publish.yml` 从 Release 资产拉取。这样 CI 不需要装 10GB SDK，最稳、最省。

#### CI 方案 B：GitHub Actions 构建 + 签名 + 发布

参考 Oniro 的 `publish.yml`：

- `oniro-app` npm 安装 OpenHarmony SDK；
- 用 OpenHarmony 开发密钥签名；
- 把 HAP 附加到 GitHub Release；
- 计算 SHA256，更新 `index.json`；
- 用 OIDC 向商店发布（本项目可改为直接 commit/Release）。

注意：

- OpenHarmony SDK 解压约 10GB，CI 需要先清理磁盘；
- API 11 的 SDK 是否被 `oniro-app` 支持要先验证；不支持就退回方案 A；
- 构建/签名/发布拆成两个 job：build 不拿 token，publish 不执行仓库代码（参考 Oniro 的权限隔离）；
- 所有 action 用 commit SHA 固定，避免供应链风险。

#### 发布流程

```text
开发者本地/CI 构建 HAP
  -> hap-sign-tool verify-app 验签 + 导出证书链
  -> 计算 SHA256/size，提取 module.json 的 bundleName/versionCode/minAPI
  -> 复制到 apps/<bundle>/<versionCode>/
  -> 更新 index.json（latest + history）
  -> 本地 validate-index.mjs 全绿
  -> git commit/push 或 tag
  -> CI 再跑 validate-index.mjs
  -> 合并/发布
  -> 设备端下拉刷新
```

#### 下架/回滚

- 下架：`revoked: true` + `revokedReason`，保留 HAP 便于审计；
- 回滚：把 `latest` 指回旧版本，但设备已装高版本无法降级（`17700047`），需要先卸载；
- 撤包：删除 `apps/` 中的 HAP 并更新索引；已下载到用户设备的副本无法收回。

### 5.10 App 端实现要点（API 11 / ArkTS Stage）

权限：

```json5
"requestPermissions": [
  { "name": "ohos.permission.INTERNET" },
  { "name": "ohos.permission.GET_NETWORK_INFO" }
]
```

不需要存储/媒体权限：下载走应用沙箱；导出走 `DocumentViewPicker` 授权 URI。

关键 API：

| 能力 | API | 可用性 | 备注 |
| --- | --- | --- | --- |
| HTTP 拉索引 | `@ohos.net.http` | API 6+ | `createHttp().request(url, {method: GET})` |
| 下载文件 | `@ohos.request` `downloadFile` | API 9+ | 简单；进度回调 |
| 下载/暂停/续传 | `@ohos.request` `agent` | API 10+ | 4.1 SDK 有；建议用于大文件 |
| 文件读写 | `@ohos.file.fs` | API 9+ | 沙箱路径、`.part`、rename |
| SHA256 | `@ohos.file.hash` | API 9+ | 返回大写 hex，比较前统一小写 |
| 选择保存位置 | `@ohos.file.picker` `DocumentViewPicker.save` | API 9+ | 返回 URI，立即复制 |
| 解压 HAP 读 module.json | `@ohos.zlib` | API 9+ | 可选；签名块在 ZIP 末尾之后，需实测 |
| ECDSA 验签索引 | `@ohos.security.cryptoFramework` | API 9+ | `createVerify`；算法字符串需 M0 验证 |
| 证书解析 | `@ohos.security.cert` | API 9+ | 可选；HAP 代码签名验证不推荐在 App 内做 |
| 版本/包信息 | `@ohos.bundle.bundleManager` | API 9+ | 只能 `getBundleInfoForSelf`；不能查其他应用（4.1 公开 API） |

UI 结构建议：

- 首页：搜索框 + 分类 chip + 应用列表（图标/名称/版本/大小/兼容标记）；
- 详情：图标、简介、版本、minAPI、ABI、SHA256 前 8 位、签名者、下载按钮；
- 下载管理：进度、暂停/继续/取消、失败原因、实际使用的镜像；
- 设置：镜像开关/测速/自定义模板、离线快照、清理缓存、安装说明；
- 安装引导：显示 `hdc install` 命令、导出按钮、PC agent 状态。

兼容性过滤：

- `latest.minAPIVersion <= 11`；
- `latest.abi === 'arm64-v8a'`；
- `deviceTypes` 包含 `phone`/`tablet`；
- 已安装版本 `>= latest.versionCode` 时显示“已是最新/已安装”；
- 对 `revoked` 条目禁用下载。

错误提示要具体：

- 网络：当前镜像、错误码、建议切换镜像；
- 哈希：期望/实际 SHA256 前 8 位；
- 安装：`hdc` 输出原文、错误码（`17700047`/`17700048`/`17700011`）；
- 空间：需要/可用字节。

### 5.11 目录运营与兼容性

- 只收能在 OH 4.1/API 11 上跑的 HAP；HarmonyOS NEXT（`@kit.*`、API 12+）单独建 `next` 通道/仓库，不要混入 stable。
- 每个应用记录 `minAPIVersion`、`targetAPIVersion`、`abi`、`deviceTypes`、`permissions`（可选）。
- 对声明 `system_core`/`system_basic` 权限的 HAP 做标记：普通安装可能失败（`17700054`），不建议收录。
- 对未签名/调试签名 HAP 做标记；调试包在非开发者模式可能报 `17700052`。
- 定期跑“安装冒烟”：在目标设备上用 `hdc install` 装一次，记录结果。
- 维护 `source`/`license`，尊重原作者；不转存未授权闭源包。

---

## 6. 风险

| 风险 | 影响 | 可能性 | 缓解 |
| --- | --- | --- | --- |
| 应用内不能安装 | 用户预期落空，必须依赖 PC | 确定 | 产品文案明确“下载 + PC 安装”；首屏给安装说明 |
| PC/数据线依赖 | 无 PC 时完全不可用 | 高 | 支持无线 hdc；提供“导出 + 手动安装”兜底 |
| 本机是 debug/eng 构建 | 零售机 root/授权行为不同 | 中 | 在目标零售机复测 `hdc install`；不要假设 root |
| GitHub raw 直连失败 | 目录/下载失败 | 高 | gh-proxy/ghproxy 多镜像 + 内置快照 + 自动回退 |
| 镜像失效/限速 | 下载中断 | 高 | 镜像列表远程更新；测速；Range 续传；保留 `.part` |
| `*.workers.dev` 不可达 | 若用 Workers 必失败 | 确定 | 不用 Workers；GitHub raw/Gitee/前缀镜像 |
| GitHub API 限流 | 目录刷新失败 | 中 | 不依赖 API；只拉静态 `index.json` |
| 仓库/索引被篡改 | 分发恶意 HAP | 低-中 | 索引 ECDSA 签名 + App 内置公钥；HAP SHA256 + 签名者指纹；CI 校验 |
| 公开测试 CA 无身份约束 | 任何人都能签“可信”包 | 高 | 不把 CA 当信任根；用索引指纹/私钥签名做 allowlist |
| 恶意 HAP/zip bomb | 设备被入侵/存储耗尽 | 中 | 只装签名包；限制大小/条目；不解压不可信包；系统验签 |
| 版本降级 | 安装失败 `17700047` | 中 | 索引版本递增；设备端比较已装版本 |
| 卸载丢数据 | 用户数据丢失 | 中 | 优先 `-r` 覆盖安装；卸载前提示 |
| 调试证书过期 | 后续安装失败 | 中 | 监控 `notAfter`；CI 告警；准备重签流程 |
| API 11 应用少 | 目录内容不足 | 高 | 先收 OH 4.1 兼容包；标注 NEXT 不兼容；提供源码构建指南 |
| 厂商 `dispatchcenter` 失效 | 黑路径不可用 | 高 | 不作为产品依赖；仅研究 |
| 法律/合规 | 分发未授权应用 | 中 | 只收开源/自有/授权应用；保留 license/source；响应下架 |
| 自动安装 agent 被滥用 | 装任意 HAP | 中 | agent 校验 SHA256 + 签名者；只监听指定目录；日志审计 |

---

## 7. 里程碑与工时

按 1 名熟悉 ArkTS/OH 的开发者估算；不含等待设备/网络/签名材料的时间。

| 阶段 | 内容 | 交付 | 工时 |
| --- | --- | --- | --- |
| M0 可行性冻结 | 用测试 HAP 验证 `hdc install`、`DocumentViewPicker.save`、`zlib` 解压、`request.agent`、索引验签算法；确认产品文案 | 验证记录 + 决策 | 1d |
| M1 索引与仓库 | `index.schema.json`、`build-index.mjs`、`validate-index.mjs`、示例仓库、CI validate | 可发布的静态仓库 | 2d |
| M2 App MVP | 目录/搜索/详情/缓存/多镜像/下载/进度/SHA256/导出/安装说明 | 可安装的 AppCenter HAP | 4-5d |
| M3 PC agent | PowerShell watcher、拉取、校验、`hdc install`、结果/日志 | 一键安装闭环 | 1.5-2d |
| M4 加固 | 断点续传、失败回退、签名者展示、索引签名、兼容性过滤、错误 UX | 稳定版 | 2-3d |
| M5 发布/CI | GitHub Actions 构建/签名/发布（可选）、Gitee 镜像、文档 | v1.0 | 2d |
| 合计 |  |  | **12.5-15d** |

MVP（M0-M3）= **8.5-10d**。建议再加 20-30% 缓冲，尤其是网络/签名/设备差异。

### 7.1 MVP 验收标准

- 设备端能离线打开，显示内置快照；
- 能通过至少 2 条链路（直连/gh-proxy）拉取索引；
- 能下载 HAP，进度可见，失败可换镜像；
- SHA256/大小校验通过才允许导出/进队列；
- 能导出到用户选择目录；
- PC agent 能自动发现、拉取、`hdc install` 并输出结果；
- 安装在 LHT16 上成功，版本号正确；
- 安装失败时能显示 `hdc` 原始错误；
- 索引 CI 全绿，重复 id/哈希错误能被拒绝。

### 7.2 建议先做的验证（M0）

1. 用 kiosk 的 `entry-signed.hap` 执行 `hdc install`，确认本机可安装/覆盖安装；
2. 用 `DocumentViewPicker.save` 保存一个文件到 Download，确认 URI 可写；
3. 用 `@ohos.zlib.decompressFile` 解压签名 HAP，确认能读到 `module.json`；
4. 用 `request.agent` 在 API 11 上下载一个 10MB 文件，确认后台/进度/暂停；
5. 用 `cryptoFramework` 验证一条 ECDSA P-256 签名，确定算法字符串；
6. 在目标零售机上复测 `hdc install` 是否需要开发者模式/授权。

---

## 8. 参考链接

### 8.1 OpenHarmony 官方文档 / SDK

- 权限（system apps，含 `INSTALL_BUNDLE`）：
  <https://gitee.com/openharmony/docs/blob/OpenHarmony-4.1-Release/en/application-dev/security/AccessToken/permissions-for-system-apps.md>
- ACL 声明（调试阶段）：
  <https://gitee.com/openharmony/docs/blob/OpenHarmony-4.1-Release/en/application-dev/security/AccessToken/declare-permissions-in-acl.md>
- `@ohos.bundle.installer.d.ts`（`@systemapi`）：
  <https://gitee.com/openharmony/interface_sdk-js/blob/OpenHarmony-4.1-Release/api/%40ohos.bundle.installer.d.ts>
- `@ohos.file.hash.d.ts`：
  <https://gitee.com/openharmony/interface_sdk-js/blob/OpenHarmony-4.1-Release/api/%40ohos.file.hash.d.ts>
- `@ohos.file.picker.d.ts`：
  <https://gitee.com/openharmony/interface_sdk-js/blob/OpenHarmony-4.1-Release/api/%40ohos.file.picker.d.ts>
- `@ohos.request.d.ts`：
  <https://gitee.com/openharmony/interface_sdk-js/blob/OpenHarmony-4.1-Release/api/%40ohos.request.d.ts>
- `@ohos.security.cryptoFramework.d.ts`：
  <https://gitee.com/openharmony/interface_sdk-js/blob/OpenHarmony-4.1-Release/api/%40ohos.security.cryptoFramework.d.ts>
- `@ohos.security.cert.d.ts`：
  <https://gitee.com/openharmony/interface_sdk-js/blob/OpenHarmony-4.1-Release/api/%40ohos.security.cert.d.ts>
- `@ohos.zlib.d.ts`：
  <https://gitee.com/openharmony/interface_sdk-js/blob/OpenHarmony-4.1-Release/api/%40ohos.zlib.d.ts>
- `@ohos.bundle.bundleManager.d.ts`（`getBundleInfoForSelf`）：
  <https://gitee.com/openharmony/interface_sdk-js/blob/OpenHarmony-4.1-Release/api/%40ohos.bundle.bundleManager.d.ts>

### 8.2 开源项目

- HapStore：<https://github.com/zhailinlang/hapstore>
- HapLane Registry：<https://github.com/LeonTing1010/haplane-registry>
- Oniro App Store actions：<https://github.com/eclipse-oniro4openharmony/oniro-app-store-actions>
- HAP distribution：<https://github.com/qius-code/hap-distribution>
- OpenStore：<https://github.com/XiaoChuangll/OpenStore>
- Aptoide-OHOS：<https://github.com/PureHarmonyProject/Aptoide-OHOS>
- ondevice-hap-dev：<https://github.com/shihuan1999/ondevice-hap-dev>
- ohos-apps：<https://github.com/shihuan1999/ohos-apps>
- auto-installer：<https://github.com/likuai2010/auto-installer>
- HarmonyOS-Haps：<https://github.com/Zitann/HarmonyOS-Haps>

### 8.3 镜像 / 托管

- gh-proxy：<https://gh-proxy.com/>
- ghproxy.net：<https://ghproxy.net/>
- ghfast.top：<https://ghfast.top/>
- jsDelivr：<https://www.jsdelivr.com/>
- Gitee：<https://gitee.com/>
- Oniro App Store（参考）：<https://store.iparo.app>

---

## 附录 A：实测命令与关键输出

```powershell
$hdc = "$OHOS_TOOLS/sdk/openharmony/toolchains/hdc.exe"
$serial = "<device-serial>"

# 设备信息
& $hdc -t $serial shell "param get const.ohos.fullname"
& $hdc -t $serial shell "param get const.ohos.apiversion"
& $hdc -t $serial shell "param get const.debuggable"
& $hdc -t $serial shell "id"
& $hdc -t $serial shell "cat /sys/fs/selinux/enforce"

# 预置应用
& $hdc -t $serial shell "bm dump -n com.ohos.updateapp"
& $hdc -t $serial shell "bm dump -n com.laval.betaclub"
& $hdc -t $serial shell "bm dump -n com.laval.dispatchcenter"

# 拉起 + 截图
& $hdc -t $serial shell "aa start -a com.ohos.updateapp.MainAbility -b com.ohos.updateapp"
& $hdc -t $serial shell "aa start -a EntryAbility -b com.laval.betaclub"
& $hdc -t $serial shell "aa start -a EntryAbility -b com.laval.dispatchcenter"
& $hdc -t $serial shell "snapshot_display -f /data/local/tmp/x.jpeg"
& $hdc -t $serial file recv /data/local/tmp/x.jpeg .\x.jpeg

# 安装权限探针（不实际安装）
& $hdc -t $serial shell "bm install -p /data/local/tmp/__no_such__.hap"

# 系统组件
& $hdc -t $serial shell "bm dump -n com.ohos.UserFile.ExternalFileManager"
& $hdc -t $serial shell "bm dump -n com.ohos.filepicker"

# 拉取预置 HAP 做字符串分析（只读）
& $hdc -t $serial file recv /system/app/com.laval.dispatchcenter/DispatchCenter.hap .\DispatchCenter.hap
```

关键输出：

```text
const.ohos.fullname=OpenHarmony-4.1.7.5
const.ohos.apiversion=11
const.debuggable=1
uid=0(root) gid=0(root) ...
0
```

```text
bm install -p /data/local/tmp/__no_such__.hap
error: failed to install bundle.
code:9568269
error: install file path invalid.
```

```text
hap-sign-tool verify-app -inFile entry-signed.hap -outCertChain certchain.cer -outProfile profile.p7b
...
Signature Algorithm: SHA384withECDSA
Digest verify result: true, DigestAlgorithm: SHA-256
verify-app success
```

截图（保存在临时调研目录，未入库）：`updateapp3.jpeg`、`betaclub.jpeg`、`dispatch.jpeg`。

---

## 附录 B：`index.json` 最小示例

```json
{
  "schemaVersion": 1,
  "generatedAt": "2026-11-17T00:00:00Z",
  "channel": "stable",
  "minAppVersionCode": 1000000,
  "repo": "owner/ohos-appcenter-index",
  "mirrors": [
    { "id": "direct", "name": "GitHub 直连", "template": "" },
    { "id": "gh-proxy", "name": "gh-proxy.com", "template": "https://gh-proxy.com/{url}" },
    { "id": "ghproxy.net", "name": "ghproxy.net", "template": "https://ghproxy.net/{url}" }
  ],
  "apps": [
    {
      "id": "com.example.demo",
      "bundleName": "com.example.demo",
      "name": "Demo",
      "summary": "示例应用",
      "description": "用于验证分发链路。",
      "developer": "Example",
      "license": "Apache-2.0",
      "source": "https://github.com/example/demo",
      "category": "工具",
      "tags": ["demo"],
      "icon": "icons/com.example.demo.png",
      "deviceTypes": ["phone", "tablet"],
      "latest": {
        "versionName": "1.0.0",
        "versionCode": 1000000,
        "minAPIVersion": 10,
        "targetAPIVersion": 11,
        "abi": "arm64-v8a",
        "deviceTypes": ["phone", "tablet"],
        "sizeBytes": 1234567,
        "sha256": "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
        "hap": "apps/com.example.demo/1000000/com.example.demo-1.0.0-arm64.hap",
        "downloadUrl": "https://raw.githubusercontent.com/owner/ohos-appcenter-index/main/apps/com.example.demo/1000000/com.example.demo-1.0.0-arm64.hap",
        "signature": {
          "scheme": "openharmony-hap",
          "subject": "C=CN,O=OpenHarmony,OU=OpenHarmony Team,CN=OpenHarmony Application Release",
          "issuer": "C=CN,O=OpenHarmony,OU=OpenHarmony Team,CN=OpenHarmony Application CA",
          "fingerprintSha256": "eeb00e63401c85853f677a73c6f12ccb7c53692d44caf459994bb2ce5a47a94d",
          "notAfter": "2049-12-31T20:15:32Z"
        },
        "publishedAt": "2026-11-17T00:00:00Z",
        "releaseNotes": "首个版本",
        "installMode": "hdc"
      },
      "revoked": false
    }
  ]
}
```

---

## 附录 C：PC `hdc-agent` 伪代码

```powershell
param(
  [string]$Hdc = "$OHOS_TOOLS/sdk/openharmony/toolchains/hdc.exe",
  [string]$Serial = "",
  [string]$Bundle = "com.example.appcenter",
  [string]$WorkDir = "$env:TEMP\ohos-appcenter-agent"
)

New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null
$remoteDir = "/data/app/el2/100/base/$Bundle/haps"

while ($true) {
  try {
    $ready = & $Hdc -t $Serial shell "ls $remoteDir/*.ready.json 2>/dev/null"
    if ($LASTEXITCODE -eq 0 -and $ready) {
      foreach ($r in ($ready -split "`n" | Where-Object { $_ -match '\.ready\.json$' })) {
        $metaJson = (& $Hdc -t $Serial shell "cat $r") -join "`n"
        $meta = $metaJson | ConvertFrom-Json
        $remoteHap = $r -replace '\.ready\.json$', '.hap'
        $localHap = Join-Path $WorkDir "$($meta.bundleName)-$($meta.versionCode).hap"

        & $Hdc -t $Serial file recv $remoteHap $localHap | Out-Host
        $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $localHap).Hash.ToLower()
        if ($hash -ne $meta.sha256.ToLower()) {
          Write-Warning "SHA256 mismatch: $localHap"
          continue
        }

        # 可选：用 hap-sign-tool verify-app 校验签名者指纹
        # -r: 覆盖安装，保留应用数据；不支持时改用 bm install -r
        & $Hdc -t $Serial install -r $localHap | Out-Host
        & $Hdc -t $Serial shell "mkdir -p $remoteDir/.done && mv $r $remoteDir/.done/" | Out-Null
      }
    }
  } catch {
    Write-Warning $_
  }
  Start-Sleep -Seconds 3
}
```

---

## 附录 D：本次克隆/评估的仓库

路径：临时目录 `opencode/appcenter-research/repos/`（未入库）。

| 目录 | 来源 | 评估 |
| --- | --- | --- |
| `hapstore` | `zhailinlang/hapstore` | 最接近目标的产品；API 26/NEXT，需移植 |
| `haplane-registry` | `LeonTing1010/haplane-registry` | 索引契约/CI 校验参考 |
| `gitee-haplane-registry` | `gitee.com/LeonTing1010/haplane-registry` | Gitee 镜像可达；索引内容与 GitHub 仓一致 |
| `oniro-app-store-actions` | `eclipse-oniro4openharmony/oniro-app-store-actions` | CI 构建/签名/发布参考 |
| `hap-distribution` | `qius-code/hap-distribution` | 静态托管/Range/manifest 参考 |
| `OpenStore` | `XiaoChuangll/OpenStore` | Web 商店，服务器重，参考产品设计 |
| `ondevice-hap-dev` | `shihuan1999/ondevice-hap-dev` | 设备本机安装仍需 `bm install`/令牌 |
| `ohos-apps` | `shihuan1999/ohos-apps` | Release HAP 仓参考 |
| `Aptoide-OHOS` | `PureHarmonyProject/Aptoide-OHOS` | 空仓库，不可用 |

> 注：以上仓库只克隆到临时目录做评估，没有复制任何代码/二进制进 `ohos-device`。

---

## 附录 E：术语

- **APL**：Ability Privilege Level，应用权限等级（`normal` / `system_basic` / `system_core`）。
- **ACL**：Access Control List，允许低 APL 应用在调试 profile 中申请高等级权限；不等于系统应用。
- **HAP**：HarmonyOS/OpenHarmony Application Package，应用安装包。
- **HSP**：Harmony Shared Package，共享包。
- **`bm`**：Bundle Manager 命令行工具，`bm install` 需要 shell/root 权限。
- **`hdc`**：Host Device Connector，宿主机与设备之间的调试/文件/安装通道。
- **`hap-sign-tool`**：OpenHarmony SDK 的签名/验签工具（Java）。

---

## 核实修正

- `ohos.permission.INSTALL_BUNDLE` 的起始版本应为 **7**（原文 1.1 写 9）；等级/授权/ACL 结论不变。
- “普通应用没有任何公开 API 能触发安装”应精确为：没有公开 API 能安装**任意 HAP**；`wantConstant.Flags.FLAG_INSTALL_ON_DEMAND` 只按 ability 触发按需安装（原子化服务 API 11），不接收 HAP 路径。
- 5.8 B1 的“PC 直接读应用沙箱 HAP”仅适用于 debug/root 或 shell 可读沙箱；零售机应走应用内 HTTP（B3）或用户导出（B2）。
- 补充：`BundleInstallerHost::Install` 对 API 11 应用执行 `IsSystemApp()` + `INSTALL_BUNDLE` 双重检查；`targetApiVersion < 9` 的遗留应用才走 202 兼容分支。`bm install` 语法为 `bm install [-h] [-p path] [-u userId] [-r] [-w waitting-time]`，成功输出 `install bundle successfully.`。
- 详细依据见 `docs/research/VERIFY-INSTALL-MEDIA.md`。
