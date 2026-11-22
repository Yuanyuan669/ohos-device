# HAP 安装与媒体权限核实（LHT16 / OpenHarmony 4.1.7.5 / API 11）

- 核实日期：2026-11-17
- 范围：只做源码 / SDK d.ts / 官方 4.1-Release 文档核实，不连接、不操作设备。
- 本地 SDK：
  - `$OHOS_TOOLS/sdk/openharmony-4.1-Release`（API 11 公开 SDK，下称“4.1 SDK”）
  - `$OHOS_TOOLS/sdk/11`（另一份 API 11 SDK，用于交叉确认）
- 远端依据：`OpenHarmony-4.1-Release` 分支的 `docs`、`interface_sdk-js`、`security_access_token`、`bundlemanager_bundle_framework`。
- 结论标记：**一致** / **文档需修正** / **未找到** / **未验证（不碰设备）**。

## 0. 结论速览

| 问题 | 本轮结论 | 关键依据 |
| --- | --- | --- |
| 普通 API 11 应用能否安装任意 HAP？ | **不能**。`@ohos.bundle.installer` 是 `@systemapi`，且不在公开 SDK；`INSTALL_BUNDLE` 为 `system_core`。 | installer d.ts；4.1 系统应用权限文档；`BundleInstallerHost::Install` 的 `IsSystemApp()` 检查 |
| 有没有公开的 install action / Want？ | **未找到** `ohos.want.action.*install*`；`filePicker` 只返回 URI，不安装。 | 公开 action 常量表；grep.app 0 命中；`filePicker` 文档 |
| 是否存在“按需安装”公开入口？ | 有 `wantConstant.Flags.FLAG_INSTALL_ON_DEMAND`，但它只按 bundle/ability 触发按需安装，**不接收 HAP 路径**，不能安装任意 HAP。 | `@ohos.app.ability.wantConstant` 文档与 d.ts |
| PC 代理安装是否可行？ | **可行**：`hdc install [-r|-s] src`、`hdc file recv/send`；设备侧 `bm install -p <path> [-u userId]`。前提是 hdc 连接 + 调试授权；从应用沙箱取 HAP 仅在 debug/root 或应用主动导出/HTTP 时成立。 | hdc 4.1 工具帮助；`bm-tool.md` |
| 普通应用能不能播放用户选的音视频？ | **能**。Picker（Photo/Audio/Document）不需要媒体库权限，返回临时只读 URI；`fs.openSync(uri, READ_ONLY)` 拿 fd 后给 `AVPlayer.fdSrc`。 | `use-picker.md`；`select-user-file.md`；`AVFileDescriptor` |
| 能不能全库浏览音视频？ | **没有稳定的普通应用路径**：`photoAccessHelper.getAssets` 需要 `READ_IMAGEVIDEO`（system_basic）；音频全库只剩已废弃的 `mediaLibrary`（`READ_MEDIA` normal）。 | 权限文档；`photoAccessHelper.d.ts`；`mediaLibrary.d.ts` |
| 能不能持久化 Picker URI？ | **不能（生产）**。`fileshare.persistPermission` 需要 `FILE_ACCESS_PERSIST`（system_basic）。可行做法是复制进沙箱。 | `@ohos.fileshare.d.ts`；权限文档 |
| 后台播放要求？ | 必须同时接 **AVSession + 长时任务 `audioPlayback`**；`KEEP_BACKGROUND_RUNNING` 为 normal。Stage 模型只能 UIAbility 申请，一个 UIAbility 同时一个。 | `continuous-task.md`；`avsession-overview.md` |
| 官方 AVPlayer 格式？ | 音频 m4a/aac/mp3/ogg/wav；视频 mp4/mkv/ts（H.264、H.265 为必选，mp4 另列 MPEG2/MPEG4）。FLAC/Opus/AV1 未列。 | `media-kit-intro.md#supported-formats-and-protocols` |

---

## 1. HAP 安装路径

### 1.1 `@ohos.bundle.installer.d.ts` 是否 `@systemapi`

**结论：是 `@systemapi`，且公开 SDK 不提供该文件。**

依据（`interface_sdk-js` 4.1-Release）：

| 符号 | 标注 | 说明 |
| --- | --- | --- |
| `declare namespace installer` | `@systemapi` / `@since 9` | 整个命名空间是系统 API |
| `getBundleInstaller()` / `getBundleInstallerSync()` | `@systemapi` | 非系统应用调用会抛 `202 Permission denied, non-system app called system api` |
| `BundleInstaller.install(...)` | `@systemapi` + `@permission ohos.permission.INSTALL_BUNDLE` | 错误码含 `201`、`202`、`17700011`、`17700054` 等 |
| `BundleInstaller.uninstall/recover` | `@systemapi` | 同样要求 `INSTALL_BUNDLE` / `UNINSTALL_BUNDLE` / `RECOVER_BUNDLE` |

链接：<https://gitee.com/openharmony/interface_sdk-js/blob/OpenHarmony-4.1-Release/api/%40ohos.bundle.installer.d.ts>

公开 SDK 核实：

- `$OHOS_TOOLS/sdk/openharmony-4.1-Release/ets/api/@ohos.bundle.installer.d.ts` → **不存在**
- `$OHOS_TOOLS/sdk/11/ets/api/@ohos.bundle.installer.d.ts` → **不存在**
- `ets\kits\@kit.AbilityKit.d.ts` 未导出 `installer`
- 全 `ets\api\*.d.ts` 中未出现 `bundle.installer`

> 结论：普通工程不能直接从公开 SDK `import installer from '@ohos.bundle.installer'`；即使自行补 d.ts 绕过编译，运行时仍有 `@systemapi` 检查。

### 1.2 `ohos.permission.INSTALL_BUNDLE` 的等级与 ACL

依据（4.1 系统应用权限文档 + `security_access_token` 源码）：

| 字段 | 值 | 依据 |
| --- | --- | --- |
| Permission level | `system_core` | `permissions-for-system-apps.md` 的 `ohos.permission.INSTALL_BUNDLE` 节 |
| Authorization mode | `system_grant` | 同上；`permission_map.cpp` 中为 `false`（注释：`true-user_grant/false-system_grant`） |
| Enable via ACL | `true` | 同上（ACL 仅调试阶段可用） |
| Valid since | **7** | 英文/中文 4.1 文档均写 `7` |
| 普通应用可得？ | 生产不可得；调试 ACL 可声明，但不改变系统应用身份 | ACL 文档；`BundleInstallerHost::Install` 的 `IsSystemApp()` |

链接：

- <https://gitee.com/openharmony/docs/blob/OpenHarmony-4.1-Release/en/application-dev/security/AccessToken/permissions-for-system-apps.md>
- <https://gitee.com/openharmony/docs/blob/OpenHarmony-4.1-Release/zh-cn/application-dev/security/AccessToken/permissions-for-system-apps.md>
- <https://gitee.com/openharmony/security_access_token/blob/OpenHarmony-4.1-Release/frameworks/common/src/permission_map.cpp>（`INSTALL_BUNDLE` 在第 126 行附近，值为 `false`）
- ACL 仅调试：<https://gitee.com/openharmony/docs/blob/OpenHarmony-4.1-Release/en/application-dev/security/AccessToken/declare-permissions-in-acl.md>

补充核实：

- 4.1 分支的 `services/accesstokenmanager/permission_definitions.json` 本轮拉取只有 13 条增量定义（如 `INSTALL_SANDBOX_BUNDLE`），**未覆盖** `READ_MEDIA` / `INSTALL_BUNDLE` 等目标权限；因此等级以官方权限文档为准，grant mode 用 `permission_map.cpp` 交叉确认。
- 公开 SDK 中没有 `permissions.json` / `permission_definitions.json`（4.1 与 11 两份 SDK 均未找到）。

**`@systemapi` 202 检查的代码级证据**：

`bundlemanager_bundle_framework` 的 `BundleInstallerHost::Install`：

```cpp
if (!BundlePermissionMgr::IsSystemApp() &&
    !BundlePermissionMgr::VerifyCallingBundleSdkVersion(Constants::API_VERSION_NINE)) {
    APP_LOGE("non-system app calling system api");
    statusReceiver->OnFinished(ERR_BUNDLE_MANAGER_SYSTEM_API_DENIED, "");
    return false;
}
if (!BundlePermissionMgr::IsSelfCalling() &&
    !BundlePermissionMgr::VerifyCallingPermissionForAll(Constants::PERMISSION_INSTALL_BUNDLE) && ...) {
    APP_LOGE("install permission denied");
    statusReceiver->OnFinished(ERR_APPEXECFWK_INSTALL_PERMISSION_DENIED, "");
    return false;
}
```

- `BundlePermissionMgr::IsSystemApp()` 通过调用方 token 的系统应用标记判断；ACL 只解决“权限等级”，不会把 HAP token 变成系统应用。
- `VerifyCallingBundleSdkVersion(API_VERSION_NINE)` 是兼容分支：`targetApiVersion < 9` 的遗留应用会跳过 202。**本项目 API 11 不适用**；理论上“API ≤8 + 调试 ACL”可绕过 202，但要求调试签名/ACL，不能作为产品方案，也未实测。
- `IsSystemApp()` 对非 HAP token（`TOKEN_SHELL` / `TOKEN_NATIVE`）返回 `true`，这解释了为什么 `hdc shell`/`bm` 可以走安装通道；但仍需 `INSTALL_BUNDLE`。

链接：

- <https://gitee.com/openharmony/bundlemanager_bundle_framework/blob/OpenHarmony-4.1-Release/services/bundlemgr/src/bundle_installer_host.cpp>
- <https://gitee.com/openharmony/bundlemanager_bundle_framework/blob/OpenHarmony-4.1-Release/services/bundlemgr/src/bundle_permission_mgr.cpp>

> 对原文档：`INSTALL_BUNDLE` 的“起始版本 9”需修正为 **7**；其余等级/授权/ACL 结论一致。

### 1.3 普通应用是否有任何公开 API 能触发安装

**结论：没有“安装任意 HAP”的公开 API。** 仅有以下接近项，但都不是通用安装器：

| 入口 | 实际能力 | 是否可用于任意 HAP |
| --- | --- | --- |
| `@ohos.bundle.installer` | 系统 API；`install(hapFilePaths, ...)` | 否（`@systemapi` + `INSTALL_BUNDLE`） |
| `wantConstant.Flags.FLAG_INSTALL_ON_DEMAND` | “Install the ability if it has not been installed”；文档标注原子化服务 API 11 | 否（按 ability/bundle 触发按需安装，不接收 HAP 路径） |
| `@ohos.file.picker` / `filePicker` | 选择/保存文件，返回 URI | 否（只返回 URI） |
| `@system.package` | `hasInstalled()` 查询 | 否（查询，且是系统 API） |
| `@ohos.security.certManager` | `installPrivateCertificate()` | 否（证书，不是 HAP） |
| `@ohos.app.ability.childProcessManager` | 启动应用自己的 child process（API 11） | 否（不是 shell，不能执行 `bm`） |
| `@ohos.process` | 进程信息/环境，无 `exec`/`runCmd` | 否 |

Want action 核实：

- 4.1 公开 action 常量 `@ohos.ability.wantConstant.d.ts` 中没有 install action（有 `viewData`、`sendData`、`scanMediaFile` 等，均非安装）。
- `@ohos.app.ability.wantConstant.d.ts` 中只有 `FLAG_INSTALL_ON_DEMAND`，没有 `ohos.want.action.install`。
- 本轮在公开 SDK / 公开文档检索 **未找到** `ohos.want.action.*install*`；grep.app 对 `ohos.want.action.install` 为 0 命中（辅助证据，不是官方结论）。
- 设备侧“没有处理 `application/vnd.ohos.hap` / `openharmony.package` 的组件”是原文档的实机观察；本轮不碰设备，未复测。

> 结论：普通 API 11 应用无法用公开 API 把任意 HAP 交给系统安装。原文档“应用内不能一键安装”成立；但“没有任何公开 API 能触发安装”建议改为“没有公开 API 能安装任意 HAP”，并把 `FLAG_INSTALL_ON_DEMAND` 作为按需安装的边界说明。

### 1.4 `bm install` 参数、返回值与 PC 代理可行性

依据：<https://gitee.com/openharmony/docs/blob/OpenHarmony-4.1-Release/en/application-dev/tools/bm-tool.md>

```bash
bm install [-h] [-p path] [-u userId] [-r] [-w waitting-time]
```

| 参数 | 必填 | 说明 |
| --- | --- | --- |
| `-p` | 是 | HAP 路径；可一次指定多个 HAP |
| `-u` | 否 | 目标用户 ID；默认当前用户 |
| `-r` | 否 | 覆盖安装；默认就是覆盖模式 |
| `-w` | 否 | 安装前等待时间，5s–600s，默认 5s |

返回值/输出：

- 成功：`install bundle successfully.`
- 失败：`error: failed to install bundle.` + `code:<错误码>` + `error: <原因>`（原文档实测 `9568269 install file path invalid` 即此格式）。

`bm` 的定位是调试工具，文档明确要求“先获取 hdc，再 `hdc shell` 运行”。

宿主机 hdc 4.1 工具帮助（`$OHOS_TOOLS/sdk/openharmony-4.1-Release/toolchains/hdc.exe help`）：

```text
file send [option] local remote       - Send file to device
file recv [option] remote local       - Recv file from device
install [-r|-s] src                   - Send package(s) to device and install them
shell [COMMAND...]                    - Run shell command
```

**PC 代理安装方案可行性**：

1. **可行**：PC 端 `hdc file recv` 取 HAP → 校验 SHA256/签名 → `hdc install` 或 `hdc shell bm install -p /data/local/tmp/x.hap`。
2. **前提**：hdc 连接可用 + 开发者模式/USB 调试授权 + HAP 签名可被设备信任。
3. **沙箱读取限制**：从应用沙箱 `filesDir` 直接 `hdc file recv` 在 debug/root（本机）可行；零售机上 shell 通常读不到应用沙箱。零售机建议：
   - App 内起本地 HTTP 服务让 PC 拉取（原文档 B3）；
   - 或 `DocumentViewPicker.save()` 导出到用户选择的公共目录后再 `hdc install`（原文档 B2）。
4. **权限通道**：`bm` 由 shell/root 启动；`IsSystemApp()` 对 shell token 返回 true，跳过 202；但仍需 `INSTALL_BUNDLE`。本机 root shell 实测有权限；零售机需复测。

> 对原文档：B1 的“PC 读应用沙箱”结论应限定为 **debug/root 或 shell 可读沙箱**；零售机应把 B3/导出作为主路径。

---

## 2. 媒体权限

### 2.1 关键权限等级与 ACL

依据：4.1 普通应用权限文档、系统应用权限文档、`permission_map.cpp`。

| 权限 | 等级 | 授权方式 | ACL | 起始版本 | 普通应用（生产）可得？ |
| --- | --- | --- | --- | --- | --- |
| `ohos.permission.READ_MEDIA` | `normal` | `user_grant` | 不需要 | 7 | **可以申请**（但 `mediaLibrary` 模块已废弃） |
| `ohos.permission.WRITE_MEDIA` | `normal` | `user_grant` | 不需要 | 7 | **可以申请** |
| `ohos.permission.READ_IMAGEVIDEO` | `system_basic` | `user_grant` | `true` | 9 | **否**（调试 ACL 可，但不适合上架） |
| `ohos.permission.WRITE_IMAGEVIDEO` | `system_basic` | `user_grant` | `true` | 9 | **否** |
| `ohos.permission.READ_AUDIO` | `system_basic` | `user_grant` | `true` | 9 | **否** |
| `ohos.permission.WRITE_AUDIO` | `system_basic` | `user_grant` | `true` | 9 | **否** |
| `ohos.permission.FILE_ACCESS_PERSIST` | `system_basic` | `system_grant` | `true` | 11 | **否**（调试 ACL 可） |
| `ohos.permission.FILE_ACCESS_MANAGER` | `system_basic` | `system_grant` | `true` | 9 | **否** |
| `ohos.permission.PROXY_AUTHORIZATION_URI` | `system_basic` | `system_grant` | `true` | 10 | **否** |
| `ohos.permission.KEEP_BACKGROUND_RUNNING` | `normal` | `system_grant` | 不需要 | 8 | **可以** |

链接：

- 普通应用权限：<https://gitee.com/openharmony/docs/blob/OpenHarmony-4.1-Release/en/application-dev/security/AccessToken/permissions-for-all.md>
- 系统应用权限：<https://gitee.com/openharmony/docs/blob/OpenHarmony-4.1-Release/en/application-dev/security/AccessToken/permissions-for-system-apps.md>
- grant mode 源码：<https://gitee.com/openharmony/security_access_token/blob/OpenHarmony-4.1-Release/frameworks/common/src/permission_map.cpp>
- ACL 仅调试：<https://gitee.com/openharmony/docs/blob/OpenHarmony-4.1-Release/en/application-dev/security/AccessToken/declare-permissions-in-acl.md>

> 说明：`READ_IMAGEVIDEO` / `READ_AUDIO` / `FILE_ACCESS_PERSIST` 的“普通应用不可用”是**生产口径**；调试 profile 通过 ACL 可以声明，但 ACL 文档写明只适用于调试阶段。

### 2.2 普通应用取音视频的公开路径

| 目标 | 公开 API | 权限 | 结论 |
| --- | --- | --- | --- |
| 全库列图片/视频 | `photoAccessHelper.getPhotoAccessHelper(context).getAssets(...)` | `READ_IMAGEVIDEO` | 生产不可用（system_basic） |
| 全库列音频 | `mediaLibrary.getMediaLibrary(context).getFileAssets(...)` | `READ_MEDIA` | 权限可得，但模块 `@deprecated since 9`；运行时需 M0 |
| 选图片/视频 | `picker.PhotoViewPicker` / `photoAccessHelper.PhotoViewPicker` | 无 | 可用，返回临时只读 URI |
| 选音频 | `picker.AudioViewPicker` | 无 | 可用；4.1 文档注明当前实际弹出 documentPicker 页面 |
| 选任意文件 | `picker.DocumentViewPicker` | 无 | 可用；`fileSuffixFilters` 可过滤后缀 |
| 选目录 | `DocumentSelectOptions.selectMode = DocumentSelectMode.FOLDER`（API 11） | 无 | 能力存在；目录枚举需 M0 |
| 持久访问 | `fileshare.persistPermission/activatePermission` | `FILE_ACCESS_PERSIST` | 生产不可用 |
| 沙箱内播放 | `context.filesDir` + `fs.open` + `AVPlayer.fdSrc` | 无 | 最稳 |

关键 d.ts / 文档：

- `@ohos.file.photoAccessHelper.d.ts`
  - `class PhotoViewPicker`：无 `@permission`（公开选择器）。
  - `PhotoAccessHelper.getAssets`：`@permission ohos.permission.READ_IMAGEVIDEO`。
  - `function getPhotoAccessHelper(context: Context)`：`@StageModelOnly`、`@since 11`。
- `@ohos.multimedia.mediaLibrary.d.ts`
  - `declare namespace mediaLibrary`：`@deprecated since 9`，`@useinstead ohos.file.picker`。
  - `getMediaLibrary(context: Context)`：`@StageModelOnly`，仍存在。
  - `MediaLibrary.getFileAssets(options)`：`@permission ohos.permission.READ_MEDIA`，`@deprecated since 9`。
  - `FileAsset.open(mode)`：`@permission READ_MEDIA or WRITE_MEDIA`，返回 fd。
- `@ohos.file.picker.d.ts`
  - `class AudioViewPicker`：`@since 9`，无权限标注。
  - `class DocumentSelectOptions`：`fileSuffixFilters`、`maxSelectNumber`、`selectMode`（API 11）。
  - `enum DocumentSelectMode`：`FILE` / `FOLDER` / `MIXED`（API 11）。
- 官方 Picker 文档：<https://gitee.com/openharmony/docs/blob/OpenHarmony-4.1-Release/en/application-dev/security/AccessToken/use-picker.md>
- 选择文件：<https://gitee.com/openharmony/docs/blob/OpenHarmony-4.1-Release/en/application-dev/file-management/select-user-file.md>
- 持久授权：<https://gitee.com/openharmony/docs/blob/OpenHarmony-4.1-Release/en/application-dev/file-management/app-file-authorization.md>
- Picker API：<https://gitee.com/openharmony/docs/blob/OpenHarmony-4.1-Release/en/application-dev/reference/apis-core-file-kit/js-apis-file-picker.md>

补充：

- `mediaLibrary` 的 `getFileAssets` 只能列“媒体库已索引”的资源；原文档设备实测 `Audios` 表为空。即接口可用也不等于能发现用户文件。
- `photoAccessHelper.getAssets` 的替代路径要求 `READ_IMAGEVIDEO`，比旧 `READ_MEDIA` 更高；这使“全库音频/视频”对普通应用更不可行。
- `PhotoViewPicker` / `AudioViewPicker` / `DocumentViewPicker` 的调用方**不需要**媒体库权限，权限由系统 picker 进程借用并给调用方临时授权。

### 2.3 filePicker 选中 URI 能否给 AVPlayer（fd 方式）

**结论：能，但不能把 URI 直接赋给 `AVPlayer.url`；正确路径是 URI → `fs.openSync(uri, READ_ONLY)` → fd → `AVPlayer.fdSrc`。**

官方流程（`select-user-file.md` 的音频/图片/文档三节一致）：

```ts
import fs from '@ohos.file.fs';

let file = fs.openSync(uri, fs.OpenMode.READ_ONLY);
// file.fd 即文件描述符
// 用完 closeSync(file)
```

AVPlayer 接收 fd：

```ts
avPlayer.fdSrc = { fd: file.fd };
// AVFileDescriptor: { fd: number; offset?: number; length?: number }
```

依据：

- `@ohos.multimedia.media.d.ts` 的 `interface AVFileDescriptor { fd: number; offset?: number; length?: number; }`
- `AVPlayer.fdSrc?: AVFileDescriptor`
- `AVPlayer.url?: string` 注释只写网络 `http://xxx`；`media-kit-intro.md` 明确“Local VOD：支持 file descriptor，不支持 file path”。
- `select-user-file.md` 明确 `AudioViewPicker` 返回 URI，读权限只读，用 `fs.openSync(uri, fs.OpenMode.READ_ONLY)` 拿 FD，再基于媒体服务播放。

限制：

- Picker 返回的是**临时只读授权**；应用重启后不再保证可用。
- 持久化需要 `fileshare.persistPermission` + `FILE_ACCESS_PERSIST`（system_basic），普通应用生产不可用。
- 需要长期保留的媒体，建议复制到 `context.filesDir` 沙箱后自建索引；这是无权限、最稳的路径。
- 播放期间保持 fd 有效，`release()` 后再 `closeSync`。

### 2.4 媒体权限 workaround 结论

- **播放用户选中的音视频：有 workaround**。Picker 不需要 `READ_IMAGEVIDEO` / `READ_AUDIO`；URI→fd→`AVPlayer.fdSrc` 即可。
- **全库浏览：没有干净的普通应用路径**。图片/视频全库需要 system_basic；音频全库只剩废弃的 `mediaLibrary`（`READ_MEDIA`），且依赖媒体库索引。
- **持久访问：没有生产路径**。`FILE_ACCESS_PERSIST` 是 system_basic；只能复制进沙箱。
- **可选线索**：`@ohos.ability.wantConstant.d.ts` 有 `ACTION_SCAN_MEDIA_FILE = 'ohos.want.action.scanMediaFile'`（`@deprecated since 9`），文档描述为“请求媒体扫描器扫描文件并加入媒体库”。它可能帮助把文件加入媒体库，但已废弃且依赖系统扫描器，本轮未验证，不作为结论。

---

## 3. 播放能力

### 3.1 AVPlayer 支持格式（官方 4.1）

依据：<https://gitee.com/openharmony/docs/blob/OpenHarmony-4.1-Release/en/application-dev/media/media/media-kit-intro.md#supported-formats-and-protocols>

**协议 / 本地播放**

| 场景 | 官方说明 |
| --- | --- |
| Local VOD | 支持 file descriptor，**不支持 file path** |
| Network VOD | HTTP / HTTPS / HLS |
| Live webcasting | HLS |

**音频容器**

| 容器 | 编码 |
| --- | --- |
| m4a | AAC |
| aac | AAC |
| mp3 | MP3 |
| ogg | VORBIS |
| wav | PCM |

> 官方 4.1 列表**没有** FLAC、Opus、APE、AMR、HE-AAC；设备上即使有对应解码器，也不属于官方承诺。

**视频容器 / 编码**

| 容器 | 视频编码 | 音频编码 | 分辨率 |
| --- | --- | --- | --- |
| mp4 | H.265（10+）、H.264、**MPEG2、MPEG4** | AAC、MP3 | 4K/1080p/720p/480p/270p 等主流分辨率 |
| mkv | H.265（10+）、H.264 | AAC、MP3 | 同上 |
| ts | H.265（10+）、H.264 | AAC、MP3 | 同上 |

必选编码：**H.265（10+）Yes、H.264 Yes**。官方未列 AV1、VP8/VP9、WebM。

> 对原文档：APP-MEDIA 的视频表把 MPEG-4 Part 2 写成“未重点列”、MPEG-2 写成“未列”，与 4.1 官方 mp4 行不符；官方 **mp4 明确列了 MPEG2、MPEG4**（H.263 确实未列）。需修正表格。
>
> 设备侧“无 HEVC 解码器、bootvideo 为 mp4v+mp4a”是本轮未复测的设备证据；官方“H.265 必选”与设备能力不冲突——设备可以不实现可选/受芯片限制，产品应按“不支持 HEVC”提示。

### 3.2 AVSession 在 API 11 的公开能力

**公开 SDK（provider 侧）**：`@ohos.multimedia.avsession.d.ts`

| 能力 | 公开符号 | 说明 |
| --- | --- | --- |
| 创建会话 | `createAVSession(context, tag, type)` | `type: 'audio' \| 'video' \| 'voice_call'`；无 `@systemapi` |
| 元数据 | `setAVMetadata(data)` | 标题/时长/专辑等 |
| 播放状态 | `setAVPlaybackState(state)` | 状态/速度/位置等 |
| 激活 | `activate()` / `deactivate()` | 会话生效/失效 |
| 控制回调 | `on('play'/'pause'/'stop'/'playNext'/'playPrevious'/'fastForward'/'rewind'/'seek'/'setSpeed'/'setLoopMode'/...)` | 接收系统 controller 命令 |
| 自身 controller | `getController()` | 返回当前会话自己的 `AVSessionController` |

**不在公开 SDK / 系统侧**：

- 全局 controller 能力（如 `getAllSessionDescriptors`、`createController`）不在公开 `ets/api` d.ts 中；官方 `local-avsession-overview.md` 明确：“The controller must be a system application. A third-party application can be a provider.”
- 因此普通应用可以“被控制”（provider），不能实现系统播控中心/全局控制器。
- 本机 SystemUI 是否有媒体卡片/锁屏播控，属于设备侧观察；本轮不碰设备，未复测。

链接：

- <https://gitee.com/openharmony/docs/blob/OpenHarmony-4.1-Release/en/application-dev/media/avsession/avsession-overview.md>
- <https://gitee.com/openharmony/docs/blob/OpenHarmony-4.1-Release/en/application-dev/media/avsession/local-avsession-overview.md>
- <https://gitee.com/openharmony/docs/blob/OpenHarmony-4.1-Release/en/application-dev/media/avsession/using-avsession-developer.md>

### 3.3 后台长时任务 `audioPlayback` 的要求

依据：<https://gitee.com/openharmony/docs/blob/OpenHarmony-4.1-Release/en/application-dev/task-management/continuous-task.md>

| 要求 | 官方说明 |
| --- | --- |
| 权限 | `ohos.permission.KEEP_BACKGROUND_RUNNING`（normal / system_grant） |
| 配置 | UIAbility 的 `module.json5` 中 `backgroundModes: ["audioPlayback"]` |
| 启动 | `backgroundTaskManager.startBackgroundRunning(context, BackgroundMode.AUDIO_PLAYBACK, wantAgent)` |
| 停止 | 暂停/停止时 `stopBackgroundRunning(context)` |
| 模型 | Stage 模型只支持 **UIAbility** 申请（不是 ServiceExtension） |
| 数量 | 一个 UIAbility 同一时刻只能申请一个长时任务 |
| 进程 | 一个 UIAbility 申请后，整个应用进程不被挂起 |
| 校验 | 系统会校验是否真的在执行对应任务；假申请（如申请 AUDIO_PLAYBACK 但不播放）会**终止应用进程** |
| 通知 | 系统会给长时任务附加通知；用户删除通知，系统自动停止任务 |
| AVSession | **只有接入 AVSession 的音视频应用**才能申请 `AUDIO_PLAYBACK` 长时任务；否则退后台会被强制暂停音频 |

d.ts：

- `@ohos.resourceschedule.backgroundTaskManager.d.ts`：`startBackgroundRunning(context, bgMode, wantAgent)` 带 `@permission ohos.permission.KEEP_BACKGROUND_RUNNING`；`BackgroundMode.AUDIO_PLAYBACK = 2`。
- `@ohos.multimedia.avsession.d.ts`：`createAVSession`、`setAVMetadata`、`setAVPlaybackState`、`activate`、控制回调。

> 对原文档：后台播放结论一致；建议把“假申请会被管控”写得更准确——官方是“系统终止应用进程”。

---

## 4. 对照两份文档

### 4.1 `APP-APPCENTER.md`

| 原文档位置/结论 | 核实结果 | 处理 |
| --- | --- | --- |
| 1.1 表：`INSTALL_BUNDLE` “起始版本 9” | **错误**，官方 4.1 文档为 **7** | **文档需修正** |
| 1.1：`INSTALL_BUNDLE` level `system_core`、`system_grant`、ACL true | 一致 | 保留 |
| 1.1：ACL 只适用于调试、不改变 `isSystemApp` | 一致（ACL 文档 + `IsSystemApp()` 代码） | 保留，可补代码依据 |
| 1.1：非系统应用调用系统 API 抛 202 | 一致（API 11）；但代码有 `targetApiVersion < 9` 兼容分支 | 建议补充边界，不改结论 |
| 1.2：`@ohos.bundle.installer` 是 `@systemapi`、不在公开 SDK | 一致（4.1/11 SDK 均无该文件） | 保留 |
| 1.3：`com.laval.dispatchcenter` 是唯一带 `INSTALL_BUNDLE` 的应用 | 设备侧结论，本轮未复测 | 标注“设备侧，未复测” |
| 1.4：root shell `bm install` 返回 9568269 而非 201/202 | 设备侧结论；代码显示 shell token 走 `IsSystemApp()==true` | 保留；零售机需复测 |
| 1.5：没有“点 HAP 安装”的公共路径 | 与“未找到 install action / handler”一致 | 保留 |
| 1.6：`bm install` 可行、`hdc install` 可行 | 一致；`hdc install [-r|-s] src` 已由 4.1 hdc 帮助确认 | 保留，补充参数 |
| 1.6：第三方装机工具转交（`openharmony.package`） | **未找到**公开定义/处理器；设备侧原文档未发现 | 保留为“探测+降级” |
| 5.8 B1：PC 读应用沙箱 HAP | **需限定**：debug/root 或 shell 可读沙箱；零售机通常不可读 | **文档需修正** |
| 1.0 摘要：普通应用没有任何公开 API 能触发安装 | 需精确化：没有任意 HAP 安装 API；存在 `FLAG_INSTALL_ON_DEMAND`（按需安装 ability） | **文档需修正表述** |
| 1.0 摘要：唯一真·一键是系统应用/刷 ROM | 对“设备端一键”成立 | 保留 |
| 附录 E：`bm install` 需要 shell/root 权限 | 一致（shell token 可跳过 202，但需 `INSTALL_BUNDLE`） | 保留 |

### 4.2 `APP-MEDIA.md`

| 原文档位置/结论 | 核实结果 | 处理 |
| --- | --- | --- |
| 2.6.1 表：`READ_MEDIA` normal/user_grant、ACL“-” | 一致 | 保留 |
| 2.6.1 表：`READ_IMAGEVIDEO` / `READ_AUDIO` / `FILE_ACCESS_PERSIST` system_basic、ACL true | 一致 | 保留；补“调试 ACL 可，生产不可” |
| 2.6.1 表：`KEEP_BACKGROUND_RUNNING` normal/system_grant | 一致 | 保留 |
| 2.6.2：Picker 调用方不需要媒体库权限、返回临时只读 URI、`fs.open` 拿 fd | 一致 | 保留 |
| 2.6.2：`FILE_ACCESS_PERSIST` system_basic，普通应用不能持久化 | 一致 | 保留 |
| 2.6.2：`AudioViewPicker` 当前退回 documentPicker | 一致（官方原文 “currently, a documentPicker page is displayed”）；“audioPicker 在规划中”是转述 | 建议改原文措辞 |
| 3.1：AVPlayer 本地资源用 fd、不用 file path | 一致（`media-kit-intro` Local VOD） | 保留 |
| 3.1：AVPlayer 支持事件列表 | 一致（d.ts/文档有 `stateChange`、`error`、`durationUpdate`、`timeUpdate`、`seekDone`、`speedDone`、`volumeChange`、`bufferingUpdate`、`audioInterrupt`） | 保留 |
| 3.2：后台必须 AVSession + 长时任务；`audioPlayback` 权限/配置/限制 | 一致 | 保留；补“假申请终止进程” |
| 3.2：AVSession 公开能力 | 需补：公开 SDK 只有 provider 侧；全局 controller 是系统应用 | **文档需补充** |
| 3.3：`photoAccessHelper.getAssets` 需 `READ_IMAGEVIDEO`，普通应用不可用 | 一致（生产口径） | 保留；补“调试 ACL 可” |
| 3.3：`mediaLibrary.getFileAssets` 已废弃、`READ_MEDIA` normal、可能可用 | 一致；模块 `@deprecated since 9`，4.1 仍有 API 文档；运行时需 M0 | 保留，补“依赖媒体库索引” |
| 3.3 表：`mediaLibrary` 路径“URI 持久、无需复制文件” | **未找到**官方依据；`FileAsset.uri` 跨重启可用性未说明 | **文档需修正/降级** |
| 3.4 音频表：MP3/AAC/M4A/WAV/OGG 支持；FLAC/Opus 未列 | 一致 | 保留 |
| 3.4 视频表：MP4/H.264、MKV/H.264、TS/H.264 支持 | 一致 | 保留 |
| 3.4 视频表：MP4/MPEG-4 Part 2 “未重点列” | **错误**：官方 mp4 行明确列 MPEG4 | **文档需修正** |
| 3.4 视频表：MP4/MPEG-2 “未列” | **错误**：官方 mp4 行明确列 MPEG2 | **文档需修正** |
| 3.4 视频表：HEVC 官方必选但设备无解码器 | 官方“H.265 必选”一致；设备能力未复测 | 保留，标注设备侧 |
| 3.4 视频表：4K 官方主流分辨率 | 一致 | 保留 |
| 3.4 视频表：AV1 未列 | 一致 | 保留 |
| 4.1 方案 A：mediaLibrary 可用则做统一媒体库 | 需降级为“M0 验证”；模块废弃 + 媒体库索引依赖 | 建议改写 |
| 5.3/5.7：普通应用媒体权限/路径 | 与 2.1/2.2 一致 | 保留 |

### 4.3 明确的“文档需修正”清单

1. **APP-APPCENTER 1.1**：`ohos.permission.INSTALL_BUNDLE` 起始版本 **9 → 7**。
2. **APP-APPCENTER 1.0/1.1**：“普通应用没有任何公开 API 能触发安装” → “没有公开 API 能安装任意 HAP；`FLAG_INSTALL_ON_DEMAND` 只按 ability 触发按需安装，不接收 HAP 路径”。
3. **APP-APPCENTER 5.8 B1**：“PC 直接读应用沙箱 HAP”需限定为 debug/root 或 shell 可读沙箱；零售机应走应用内 HTTP 或用户导出。
4. **APP-MEDIA 3.4**：MP4 的 MPEG-4 Part 2 / MPEG-2 官方 **有列**，不是“未重点列/未列”。
5. **APP-MEDIA 3.3 / 4.1**：`mediaLibrary` 的 URI“持久、无需复制文件”无官方依据，应降级为“M0 验证，默认复制到沙箱”。
6. **APP-MEDIA 3.2**：AVSession 公开 SDK 只覆盖 provider；全局 controller 必须是系统应用。
7. **APP-MEDIA 2.6.2**：`AudioViewPicker` 的官方措辞是“当前实际弹出 documentPicker 页面”，不是“audioPicker 在规划中”。

---

## 5. 未找到 / 未验证

| 项 | 状态 |
| --- | --- |
| `ohos.want.action.*install*` | **未找到**（公开 action 常量表无；grep.app 0 命中；设备侧原文档未发现 handler） |
| 公开 SDK 的 `permissions.json` / `permission_definitions.json` | **未找到**（4.1 与 11 SDK 均无） |
| 4.1 `permission_definitions.json` 覆盖目标权限 | **未找到**（4.1 分支文件仅 13 条增量；等级改用官方权限文档） |
| ACL 会改变 `isSystemApp` 的官方说明 | **未找到**；代码显示 `IsSystemApp()` 与权限校验分离，ACL 不改变 HAP token 的系统应用标记 |
| `mediaLibrary` URI 跨应用重启可用的官方说明 | **未找到** |
| `mediaLibrary` 在 API 11 运行时一定可用 | **未验证**；4.1 仍保留 API 文档，但模块 `@deprecated since 9`，且依赖媒体库索引 |
| `hdc install` 对开发者模式/USB 调试授权的官方 4.1 文档条款 | **未在本轮找到**（hdc 帮助只给命令语法） |
| 设备侧 SystemUI 是否有 AVSession 播控/媒体卡片 | **未验证**（本轮不碰设备） |
| `openharmony.package` 的公开 MIME/处理器 | **未找到**公开定义；设备侧原文档未发现 handler |
| 本机 `com.laval.dispatchcenter` 的安装行为 | **未复测**（原文档设备侧结论） |

---

## 6. 依据清单

### 6.1 SDK / 源码

- `$OHOS_TOOLS/sdk/openharmony-4.1-Release/ets/api/@ohos.multimedia.media.d.ts`
  - `interface AVFileDescriptor`、`AVPlayer.fdSrc`、`AVPlayer.url`
- `$OHOS_TOOLS/sdk/openharmony-4.1-Release/ets/api/@ohos.multimedia.mediaLibrary.d.ts`
  - `namespace mediaLibrary`（`@deprecated since 9`）、`getMediaLibrary(context)`、`MediaLibrary.getFileAssets`、`FileAsset.open`
- `$OHOS_TOOLS/sdk/openharmony-4.1-Release/ets/api/@ohos.file.photoAccessHelper.d.ts`
  - `getPhotoAccessHelper`、`PhotoAccessHelper.getAssets`、`class PhotoViewPicker`
- `$OHOS_TOOLS/sdk/openharmony-4.1-Release/ets/api/@ohos.file.picker.d.ts`
  - `AudioViewPicker`、`DocumentViewPicker`、`DocumentSelectOptions`、`DocumentSelectMode`
- `$OHOS_TOOLS/sdk/openharmony-4.1-Release/ets/api/@ohos.multimedia.avsession.d.ts`
  - `createAVSession`、`setAVMetadata`、`setAVPlaybackState`、`activate`
- `$OHOS_TOOLS/sdk/openharmony-4.1-Release/ets/api/@ohos.resourceschedule.backgroundTaskManager.d.ts`
  - `startBackgroundRunning`、`BackgroundMode.AUDIO_PLAYBACK`
- `$OHOS_TOOLS/sdk/openharmony-4.1-Release/ets/api/@ohos.fileshare.d.ts`
  - `persistPermission`、`activatePermission`，`@permission FILE_ACCESS_PERSIST`
- `$OHOS_TOOLS/sdk/openharmony-4.1-Release/ets/api/@ohos.app.ability.wantConstant.d.ts`
  - `FLAG_INSTALL_ON_DEMAND`
- `$OHOS_TOOLS/sdk/openharmony-4.1-Release/ets/api/@ohos.ability.wantConstant.d.ts`
  - 公开 action 常量列表（无 install）
- `$OHOS_TOOLS/sdk/openharmony-4.1-Release/toolchains/hdc.exe help`
  - `install [-r|-s] src`、`file send/recv`

### 6.2 官方 4.1 文档

- 系统应用权限：<https://gitee.com/openharmony/docs/blob/OpenHarmony-4.1-Release/en/application-dev/security/AccessToken/permissions-for-system-apps.md>
- 普通应用权限：<https://gitee.com/openharmony/docs/blob/OpenHarmony-4.1-Release/en/application-dev/security/AccessToken/permissions-for-all.md>
- ACL：<https://gitee.com/openharmony/docs/blob/OpenHarmony-4.1-Release/en/application-dev/security/AccessToken/declare-permissions-in-acl.md>
- Picker：<https://gitee.com/openharmony/docs/blob/OpenHarmony-4.1-Release/en/application-dev/security/AccessToken/use-picker.md>
- 选择文件：<https://gitee.com/openharmony/docs/blob/OpenHarmony-4.1-Release/en/application-dev/file-management/select-user-file.md>
- 持久授权：<https://gitee.com/openharmony/docs/blob/OpenHarmony-4.1-Release/en/application-dev/file-management/app-file-authorization.md>
- Picker API：<https://gitee.com/openharmony/docs/blob/OpenHarmony-4.1-Release/en/application-dev/reference/apis-core-file-kit/js-apis-file-picker.md>
- `bm` 工具：<https://gitee.com/openharmony/docs/blob/OpenHarmony-4.1-Release/en/application-dev/tools/bm-tool.md>
- Media Kit 格式：<https://gitee.com/openharmony/docs/blob/OpenHarmony-4.1-Release/en/application-dev/media/media/media-kit-intro.md#supported-formats-and-protocols>
- AVPlayer：<https://gitee.com/openharmony/docs/blob/OpenHarmony-4.1-Release/en/application-dev/media/media/using-avplayer-for-playback.md>
- AVSession：<https://gitee.com/openharmony/docs/blob/OpenHarmony-4.1-Release/en/application-dev/media/avsession/avsession-overview.md>
- Local AVSession：<https://gitee.com/openharmony/docs/blob/OpenHarmony-4.1-Release/en/application-dev/media/avsession/local-avsession-overview.md>
- 长时任务：<https://gitee.com/openharmony/docs/blob/OpenHarmony-4.1-Release/en/application-dev/task-management/continuous-task.md>
- mediaLibrary API（已废弃但 4.1 仍有）：<https://gitee.com/openharmony/docs/blob/OpenHarmony-4.1-Release/en/application-dev/reference/apis-media-library-kit/js-apis-medialibrary.md>

### 6.3 源码

- installer d.ts：<https://gitee.com/openharmony/interface_sdk-js/blob/OpenHarmony-4.1-Release/api/%40ohos.bundle.installer.d.ts>
- 权限 grant mode：<https://gitee.com/openharmony/security_access_token/blob/OpenHarmony-4.1-Release/frameworks/common/src/permission_map.cpp>
- 安装系统应用检查：<https://gitee.com/openharmony/bundlemanager_bundle_framework/blob/OpenHarmony-4.1-Release/services/bundlemgr/src/bundle_installer_host.cpp>
- 系统应用判定：<https://gitee.com/openharmony/bundlemanager_bundle_framework/blob/OpenHarmony-4.1-Release/services/bundlemgr/src/bundle_permission_mgr.cpp>
