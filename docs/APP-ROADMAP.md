# LHT16 应用总路线图（OpenHarmony 4.1.7.5 / API 11）

> 依据：`docs/research/` 下 4 份方向调研 + 2 份核实/Spike 报告。凡正文与「核实修正 / Spike 实测」冲突，一律采用修正后结论（清单见文末 §9）。
> 版本 v1.0（2026-11-17）｜性质：路线图，不含代码，不新建/修改任何工程。

## 1. 总目标与硬约束

**一句话目标**：在 LHT16 上用普通测试 CA 签名的零依赖 ArkTS 应用，依次交付「文件互传 → 媒体中心 → 浏览器 → 应用分发中心」四件可用工具。

| 约束 | 内容 | 对方案的硬性影响 |
| --- | --- | --- |
| 设备 | LHT16，`OpenHarmony-4.1.7.5`，API 11，`arm64-v8a`，1080x2408，8 GB | 所有 API 以 API 11 公开 SDK 为准；12+/NEXT 接口、`@kit` 新能力不可用 |
| 签名 | 普通 test-CA（SDK `OpenHarmony.p12` 链签，`isSystemApp=false`） | 不能安装 HAP、不能持久化 picker URI、不能写公共目录、不能成为默认浏览器 |
| 依赖 | 零三方 npm/ohpm/native 库，纯 ArkTS Stage | WebDAV/SMB、二维码解码、HEVC 软解、第三方商店类库一律排除 |
| 网络 | 不稳：GitHub raw 时通时断，`gh-proxy.com`/`ghproxy.net` 可用，`*.workers.dev` 不可达 | 一切远端资源必须多前缀镜像 + 内置离线快照 + 失败切换，禁止 Workers/CDN 单点 |
| 系统 | 只读 `/system`，不刷机、不改分区、不 root 改造；`miniserve` 保持关闭 | 预置应用只能"参考"，不能复用/替换；能力缺口靠自建或 PC 侧补 |

## 2. 四方向结论速览

| 方向 | 推荐方案 | 关键实测结论 | 最大风险 | 工作量(人日) | 依赖 |
| --- | --- | --- | --- | --- | --- |
| 浏览器 | **B：新写 ArkWeb 壳**（地址栏+3 标签+书签/历史/下载+错误页） | 普通 test-CA 应用可创建 `Web`（rawfile+JS+https 全通）；单标签 ≈356 MiB；引擎 Chromium 114；无离屏/预渲染/`onOverrideUrlLoading` | 内存叠加与 114 引擎站点兼容 | **12.5**（含 1 buffer） | 系统 `libweb_engine.so`+`nwebspawn`；`filepicker`/`request` |
| 文件互传 | **A：手机内 HTTP 服务**（`TCPSocketServer` 0.0.0.0:8080 + PC 浏览器）；C 兜底，B′ 备选 | 普通应用 8080 监听+PC 连接实测通过；80 不可能（`ip_unprivileged_port_start=1024`）；预置 miniserve 是 root+全 `/data`+无鉴权 | 前台优先；实测切后台 45s 进程/8080 仍存活（息屏/长时未验证）；明文 HTTP | **7~9**（MVP 3.5~4.5） | 仅 `INTERNET`(normal)；同网段 Wi-Fi |
| 媒体中心 | **B：自建媒体中心**（音乐+视频统一库） | 设备仅软解 MP3/AAC/FLAC/Vorbis/Opus + H.264/H.263/MPEG-2/MPEG-4，硬解仅 H.264；无 HEVC/AV1；SystemUI 无 AVSession 播控；后台须 AVSession+`audioPlayback` | 格式覆盖不足与全库权限拿不到 | **13.5**（建议按 15 排；视频-only 约 6.5） | `filepicker`；`AVSessionService`/`AVCodecService` |
| 应用中心 | **B：设备端下载/校验/导出 + PC `hdc-agent` 安装** | 应用内安装必失败（`INSTALL_BUNDLE` 为 `system_core`/`@systemapi`，202）；本机无 HAP 安装 handler/文件管理器；root shell 的 `bm install`/`hdc install` 可用 | 无 PC 即完全不可用；零售机 hdc 授权未知 | **12.5~15**（MVP 8.5~10） | PC agent + hdc；GitHub 仓 + 镜像 |

## 3. 共同基础组件（优先做成 4 个 App 共用的本地件）

| 组件 | 能力 | 关键实现（均已验证/有依据） | 复用方 |
| --- | --- | --- | --- |
| `SignTool` 签名与装机 | 重签 + 安装 + 回滚 | `OpenHarmony.p12` 三级链（Root→App CA→App）、10 年 profile、`bundle-name` 对齐、`hdc install -r`；沿用现有 deploy 脚本 | 全部 |
| `MirrorFetcher` 镜像下载 | 竞速、切换、续传 | 前缀模板 `template.replaceAll("{url}", url)`；内置 direct/gh-proxy/ghproxy 默认值，镜像表随索引远程更新；用真实文件 Range 测速；`.part`+rename | 浏览器下载、应用中心、媒体封面 |
| `Store` preferences 持久化 | 小数据模型 | 单 store，JSON + `schemaVersion`；写入走内存态 + 300ms debounce `flush()`；历史/索引上限（如历史 500 条）；临时文件+rename 防半截 | 浏览器、应用中心、媒体索引 |
| `ErrorKit` 错误页/重试 | 统一失败面 | 错误码只有裸数字（无 `netErrorList`）：页面只显示数字+`getErrorInfo()`；15s 主文档超时；重试 ≤2 次；状态机 `IDLE→RESOLVING→DOWNLOADING→VERIFYING→READY→FAILED` | 全部 |
| `UiKit` 统一 UI 规范 | 一套交互语言 | ArkUI 零依赖：Tab ≤3/4、列表+空态+错误态+进度、深色跟随、三键导航安全区、`setWindowKeepScreenOn` 共享态横幅 | 全部 |

## 4. Phase 0：验证收尾（开工前必须先证伪/确认）

合计按各文档 M0 原估 **3.5 人日**（浏览器 1.0 / 传输 0.5 / 媒体 1 / 应用中心 1）；浏览器 R1 与传输 8080 已由 Spike 销账，实际剩余更少。**未过项不得进入对应 Phase。**

| # | 必须确认的事 | 来源 | 不过怎么办 |
| --- | --- | --- | --- |
| P0-1 | 签名 HAP 的 `hdc install -r` 真装成功（非仅权限探针） | 应用中心 M0 | 整个 Phase 4 形态退回 F（纯下载站） |
| P0-2 | `DocumentViewPicker.save` 可写、`select` 只读可读、批量 `newFileNames` 可用 | 传输/应用中心/媒体 | 去掉批量导出，改单文件循环 |
| P0-3 | `FilePicker 1.1.0.300` 是否支持 `DocumentSelectMode.FOLDER` | 传输 M0 #5 | 删除"选目录"设计 |
| P0-4 | `request.agent`（BACKGROUND）下载 10 MB：进度/暂停/后台不中断回调 | 应用中心 M0 | 大文件退回 `downloadFile`，文案去掉"后台下载" |
| P0-5 | `cryptoFramework` 验 ECDSA P-256 的算法字符串 | 应用中心 M0 | 索引验签降级为 Phase 4 之后 |
| P0-6 | `zlib` 解压签名 HAP 能读到 `module.json`（签名块在 ZIP 末尾） | 应用中心 M0 | 放弃本地解包校验，只做 SHA256 |
| P0-7 | `READ_MEDIA`+`mediaLibrary` 能否列音频/视频并拿 fd（模块已废弃） | 媒体 M0 | 默认走 picker 导入沙箱<br>【已验证 2026-11-17（相关）：picker 导入路径在 `com.local.media` 上不通（URI→fd=13900001），`READ_MEDIA`+`mediaLibrary` 本身仍未测，见 `research/VERIFY-MEDIA-M0.md`】 |
| P0-8 | picker URI→`fs.openSync(READ_ONLY)`→fd→`AVPlayer.fdSrc`；**不可**把 URI 赋给 `url` | 媒体 M0 | 无替代，必须成立<br>【已验证 2026-11-17：**前半段不成立**。picker 返回 `file://docs/storage/Users/currentUser/Download/x.mp3`，`fs.openSync` 13900001 EPERM、`copyFileSync` 13900002；后半段确认：URI 给 `AVPlayer.url` 报 401"not fd:// or network address"。改用 hdc 推送 + chown/660 进 `filesDir/media` 后 fdSrc 正常】 |
| P0-9 | AVSession+`audioPlayback` 退后台 30 分钟不断；假申请会被终止进程 | 媒体 M0 | 音乐不做后台承诺<br>【已验证 2026-11-17：普通签名包 + `KEEP_BACKGROUND_RUNNING`（system_grant 静默授予）+ `AVSession.activate` + `startBackgroundRunning(AUDIO_PLAYBACK)`，切到「笔记」后 ≥76 s `pid` 不变、`state=playing`、position 持续（0↔5000 循环）；系统出了媒体通知。30 分钟与"假申请杀进程"未测】 |
| P0-10 | 格式矩阵：FLAC/Opus/WebM(VP8/VP9)/MP4 H.264/MKV/TS/HEVC/4K 逐项实测 | 媒体 M0 | 白名单收缩，HEVC 直接友好报错<br>【已验证 2026-11-17：flac/m4a/mp3/ogg/opus/wav + h264 的 mkv/mp4/ts + **hevc mp4** 共 10/10 `fdSrc` prepare+play 成功、duration 正确；视频须先给 `surfaceId`。WebM(VP8/VP9)、4K、长时压测未测】 |
| P0-11 | 80 端口 `listen` 的失败错误码与耗时（预期 201/2303199） | 传输 M0 #3 | 仅记录，不影响 8080 主方案 |
| P0-12 | 熄屏/切后台后 PC 请求多久失败、恢复后端口是否仍在 | 传输 M0 #2 | 决定超时阈值与"假在线"文案 |
| P0-13 | `setWindowKeepScreenOn(true)` 生效且退页恢复 | 传输 M0 #6 | 传输期改用引导文案 |
| P0-14 | 普通应用 `setDownloadDelegate`+`startDownload` 全链路（50 MB） | 浏览器 M4 前置 | 下载降级为"复制链接" |
| P0-15 | 第三方输入法软键盘是否遮挡地址栏 | 浏览器 R8 | 地址栏移到底部或滚动避让 |

## 5. Phase 1：文件传输（最低依赖、最快可用）

**第一件事：先交付 C（`hdc` 兜底脚本，0.5~1 人日）拿到"今天就能传"的基线，同时并行 A 的 P0-11~P0-13 三项。** 理由：C 零 App 开发、零端口、零局域网暴露，且已有 `push-photos.sh` 先例（root 写沙箱 + chown/660 + 失败退 `/data/local/tmp`）。

> **2026-11-17 进展（MVP 已落地）**：`D:\ohos-transfer`（bundle `com.local.transfer`，commit `b9aa390`）。
> 已实现并实测：自动监听 `0.0.0.0:8080` + 6 位 PIN；PC 浏览器（同网段 192.168.31.x）打开页面拖拽上传/列表/下载；
> 5 MB 中文名上传→下载 SHA256 一致；错误 PIN 返回 401；退出（terminateSelf）后端口释放；切后台 45 s 端口与进程仍存活。
> `scripts/transfer.sh` 的 hdc `push/list/pull` 已实测（含 chown 660）。
> 剩余：M3 picker 导入联调、M4 限速/锁定/空闲停、M5 大文件与 Wi-Fi 抖动；GitHub 仓库待建后推送。

| 里程碑 | 内容 | 人日 | 验收 |
| --- | --- | --- | --- |
| M0 | 6 条空壳验证（8080/PC curl/80 失败/picker 读写/批量存/FOLDER/keep-screen-on） | 0.5 | 6 条有记录，失败项有替代方案 |
| M1 | HTTP 核心：增量解析、路由、`PUT /u/<name>` 流式上传、`GET /f/<id>` 流式下载、错误码、连接管理 | 1.5~2 | PC 双向传 100 MB；断连不崩；头/体上限生效 |
| M2 | UI：开始/停止、IP:端口、6 位码、收件箱、进度、keep-screen-on、前后台处理 | 1.5 | 完成一次 PC↔手机互传；退后台自动停 |
| M3 | 文件：picker 多选、批量导出、文件名清洗、磁盘余量、临时文件原子落盘 | 1 | 中文/emoji 正确；`../x` 被拒 |
| M4 | 安全：PIN 会话、限速锁定、10 分钟空闲停、只暴露 inbox | 0.5~1 | 错码 5 次锁定；未配对 401/403 |
| M5 | 实机联调：Chrome/Edge、1 GB、多文件、Wi-Fi 抖动、并发、发热 | 1.5 | 验收清单通过 |
| M6 | 文档/打包/回滚 | 0.5 | README + USB `fport` 模式 + 排障 |

**合计 7~9 人日，MVP（M0~M2）3.5~4.5。** 硬性设计：80 端口永不出现；`listen()` 无 `bind()`；上传用原始 PUT 免 multipart；端口占用固定 `2303198`。

## 6. Phase 2：媒体中心

前置：P0-7~P0-10 全部有结论；`MediaRepository` 先定接口，底层在 `MediaLibrarySource`（若可用）与 `PickerImportSource`（默认，复制进 `filesDir/media`）间可切换。

| 里程碑 | 内容 | 人日 | 验收 |
| --- | --- | --- | --- |
| M0 | 权限/后台/格式/焦点五项验证页 | 1 | go/no-go + 默认实现选定 |
| M1 | 工程骨架 + 媒体库：扫描/导入、元数据/封面/缩略图、空态/错误态 | 2.5 | 100 音频 + 50 视频可列可搜 |
| M2 | 音乐：AVPlayer 封装、队列/循环/随机、收藏、AVSession、长时任务、焦点、拔耳机 | 3 | 后台 30 分钟不断；切歌/seek 正常 |
| M3 | 视频：`XComponent`、倍速、全屏/横竖屏、手势、续播、错误提示 | 3 | 1080p H.264 连播 30 分钟；HEVC 友好报错 |
| M4 | 整合：首页/最近/搜索/设置、性能（缩略图缓存、播放器释放） | 2 | 冷启动 <2s；无 ANR/泄漏 |
| M5 | 设备回归与交付 | 2 | 格式矩阵/4K/大文件/功耗报告 |

**合计 13.5 人日（按 15 排期）；视频-only 裁剪（M0+M1 仅视频+M3）约 6.5。** 明确降级：无系统锁屏/通知播控，只做应用内控制 + 长时任务通知。

## 7. Phase 3：浏览器

前置：M0 已完成主要证伪（R1 不成立），只需补 P0-14/P0-15。工程新建（建议 `com.local.browser`），参考 `applications_app_samples` Browser 与 `OHBrowser` 思路，**不 fork**。

| 里程碑 | 内容 | 人日 | 验收 |
| --- | --- | --- | --- |
| M0 | 空壳：`$rawfile` 主页 + https + UA/RSS/首屏 + `preferences`/`picker`/`request` import | 1.0 | 无 201/202；RSS 入档 |
| M1 | 地址栏 + `UrlResolver`（不再强拼 https）、前进/后退/刷新/停止、进度、标题、错误回调 | 2.0 | http/https/`IP:端口` 均可；冷启动 <2s 到首帧 |
| M2 | 3 标签上限、非活动销毁、会话恢复 | 1.5 | 切换无白屏；切走 5s 后 RSS 明显下降 |
| M3 | 书签/历史（preferences） | 1.5 | 重启数据完整；1000 次导航不卡 |
| M4 | 下载：delegate + 进度/暂停/继续/取消 + 沙箱 + picker 导出 + 直链 `request` | 2.0 | 50 MB 成功并可导出 |
| M5 | 上传/`onWindowNew`/深色/错误页/SSL 二次确认 | 1.5 | 上传成功；`window.open` 不崩 |
| M6 | 安全与打磨：导航白名单、`mixedMode`、release 关调试、清数据、对比测试 | 2.0 | 单标签 RSS ≤300 MiB；无崩溃 |
| buffer | 联调/签名/文档 | 1.0 | — |

**合计 12.5 人日。** 关键路径 M0→M1→M2；下载不得转交 `@ohos.request`（两套 API 无集成），仅在 `onDownloadStart` 取直链 URL 时可用。

## 8. Phase 4：应用分发中心（依赖 PC agent）

前置：P0-1~P0-6 通过；仓库/索引可用（`index.json` schema v1 + `validate-index.mjs`）。设备端只做"下载器+校验器+安装队列"，安装永远由 PC 执行。

| 里程碑 | 内容 | 人日 | 验收 |
| --- | --- | --- | --- |
| M0 | 可行性冻结：`hdc install`、`save`、`zlib`、`request.agent`、验签算法 | 1d | 验证记录 + 文案定稿 |
| M1 | 索引与仓库：schema、`build/validate-index`、示例仓、CI validate | 2d | 静态仓库可发布 |
| M2 | App MVP：目录/搜索/详情/内置快照/多镜像/下载/进度/SHA256/导出/安装说明 | 4~5d | 可安装的 AppCenter HAP |
| M3 | PC agent：轮询沙箱 `.ready.json`、拉取、复核、`hdc install -r`、写回结果 | 1.5~2d | 一键闭环 |
| M4 | 加固：续传、失败回退、签名者展示、索引签名、兼容过滤、错误 UX | 2~3d | 稳定版 |
| M5 | 发布/CI：Actions 构建或仅校验、Gitee 镜像、文档 | 2d | v1.0 |

**合计 12.5~15 天，MVP（M0~M3）8.5~10 天，另加 20~30% 缓冲。** 安装验收：`hdc` 原始错误必须原样上屏（`17700047` 降级 / `17700048` / `17700011` 验签）。

## 9. 风险登记表

| 风险 | 概率 | 影响 | 缓解 | 触发信号 |
| --- | --- | --- | --- | --- |
| 视频格式不覆盖（HEVC/AV1/10bit/4K） | 高 | 中 | 白名单+选文件即提示；文案只写实测格式 | 用户报黑屏/仅声音 |
| 无 PC 时应用中心完全不可用 | 确定 | 高 | 首屏即写"需电脑安装"；提供导出+hdc 命令复制 | hdc 未连接/授权弹窗 |
| 明文 HTTP 被同网段嗅探或爆破 | 高 | 高 | 6 位码+会话 Cookie+限速+空闲停；敏感场景 USB `fport` | 陌生 IP 高频 `/pair` |
| 后台被终止（传输/音乐） | 中 | 中 | 传输：实测切后台 45s 存活，仍按前台+亮屏设计；音乐：AVSession+`audioPlayback`（实测无它约 1s 暂停） | 30s 后 PC 超时；音乐骤停 |
| Web 单标签内存 ~356 MiB | 高 | 中 | 3 标签硬上限、非活动销毁、轻量主页 | RSS >300 MiB 或整机卡顿 |
| 镜像失效/限速 | 高 | 中 | 多前缀镜像+内置快照+`.part` 续传+测速 | 索引刷新连续 2 次失败 |
| Chromium 114 站点白屏 | 中 | 中 | 记录不兼容清单；不做 polyfill | 白屏且无 errorCode |
| picker URI 会话后失效 | 高 | 中 | 媒体默认复制沙箱；导出即时复制 | `fs.open` 报权限/坏文件号 |
| 零售机 hdc 授权/root 差异 | 中 | 高 | 目标零售机复测；准备 B2/B3 路径 | `hdc install` 未授权 |
| 预置 miniserve 被误开 | 中 | 严重 | 保持 `miniserve.started=0`；公共 Wi-Fi 禁用 | 8080 之外的 `:80` LISTEN |
| 测试证书过期 | 中 | 中 | 监控 `notAfter`；准备重签流程 | 安装报 `17700011` |
| 索引/仓库被篡改 | 低-中 | 高 | HAP SHA256+签名者指纹；可选 ECDSA 索引签名 | 哈希与 index 不符 |

## 10. 未决问题（Q1~Q12）

| # | 问题 | 为什么阻塞 | 怎么验证 | 验证成本 |
| --- | --- | --- | --- | --- |
| Q1 | `READ_MEDIA`+`mediaLibrary` 在普通应用运行时是否真能列音频/视频并拿 fd | 决定媒体库默认实现（全库浏览 vs picker 导入） | M0 一页按钮：申请→`getFileAssets`→`open` | 含媒体 M0（1 人日） |
| Q2 | `FilePicker 1.1.0.300` 是否支持 FOLDER 选择与目录枚举 | 决定"选目录导入"是否保留 | M0 实机点选 | 含传输 M0（0.5） |
| Q3 | 普通应用 Web 下载 delegate 全链路是否可用 | 浏览器 M4 能否成立 | 空壳加载可下载页→50 MB | 含浏览器 M0 |
| Q4 | 第三方输入法是否遮挡地址栏 | 决定浏览器 UI 定稿 | 真机软键盘+`expandSafeArea` | 含浏览器 M1 |
| Q5 | `audioPlayback` 30 分钟是否被终止、假申请是否杀进程 | 决定是否承诺后台音乐 | 普通签名包实测 | 含媒体 M0<br>【已验证 2026-11-17（部分）：未接 AVSession/`audioPlayback` 的普通包切后台约 1 s 被系统暂停 AVPlayer（`paused`，无 `stopped`），进程未杀，回前台不自动恢复；30 分钟终止与假申请杀进程未测】 |
| Q6 | FLAC/Opus/WebM VP8/VP9 1080p 软解性能 | 决定格式白名单 | 逐格式播放+掉帧观察 | 含媒体 M0 |
| Q7 | 熄屏/切后台后 8080 连接多久失败、端口是否保留 | 决定超时阈值与"假在线"文案 | PC 侧定时 curl | 含传输 M0<br>【已验证 2026-11-17（部分）：切到其他应用后 15 s/45 s 进程仍存活、8080 仍 `LISTEN`（同 pid）、JS 定时器继续；熄屏与 PC 侧连接成功率未测】 |
| Q8 | `request.agent` BACKGROUND 是否真后台续传、回前台能否补齐进度 | 决定大文件与 AppCenter 下载策略 | 10 MB 任务切后台再回 | 含应用中心 M0（1d） |
| Q9 | `cryptoFramework` ECDSA P-256 的正确算法字符串 | 决定索引签名能否做 | 固定向量验签 | 含应用中心 M0 |
| Q10 | `zlib` 能否解压签名 HAP 并读 `module.json` | 决定本地包元信息校验 | 用 kiosk 签名包试解 | 含应用中心 M0 |
| Q11 | 零售机 `hdc install` 的授权/开发者模式要求 | 决定 Phase 4 是否能交付给非开发用户 | 目标零售机复测 | 0（换机测试） |
| Q12 | Chromium 114 的站点兼容边界 | 决定浏览器"可用"的定义与选型取舍 | 抽样 20 个常用站点分级 | 含浏览器 M6 |

## 11. 明确不做的事

- **相机/电话/短信**：与四方向无关；相机仅供扫码，而 API 11 无二维码解码且零依赖不可引入。
- **DRM**：`MediaKeySystemService` 存在也不接。
- **系统签名安装/刷机/改 `/system`**：不做系统应用、不替换预置应用、不写系统分区。
- **root 改造与复用 `miniserve`**：root + 全 `/data` + 无鉴权 + 可上传，保持关闭。
- **HEVC/AV1 软解、4K 转码、HDR 映射、格式 polyfill**：无解码器，自带库违背零依赖。
- **WebDAV/SMB/`rcp`**：API 11 无对应方法/模块，CIFS 需 root。
- **默认浏览器接管、系统级锁屏播控、应用内静默安装**：均需系统应用或系统签名。
- **二维码扫码配对、`*.workers.dev`、jsDelivr 主链路、GitHub API 做目录**：依赖不成立或受限流。

## 12. 被推翻/修正的原判断（以核实与 Spike 为准）

| 原判断 | 修正后 |
| --- | --- |
| `@kit.ArkWeb` 为 12+ 不可用 | 4.1.7.5 SDK 已有，等同 `@ohos.web.webview` 别名 |
| API 11 无真正 incognito | `incognitoMode`(11)+`isIncognitoMode()` 可用，仅隔离 Web 存储/Cookie |
| Web 调试仅 debug 构建可开 | 无构建类型限制，只要求 `INTERNET`+`hdc fport`；建议 release 关闭 |
| 无跨进程下载续传 | 有 `serialize/deserialize/resumeDownload`，但需应用存活，非系统托管 |
| 错误码 -2/-6 有固定语义 | 无枚举，仅裸数字，页面只显示码+描述 |
| 示例浏览器 README 过期/强拼 https（通用） | 仅限 master 与 3.2/4.0；设备 1.0.15 属 3.2 代故实机结论成立 |
| `TCPSocketServer` 需 `bind` 后 `listen` | 无 `bind()`，`listen(NetAddress)` 内部完成 bind+listen |
| 长时任务"仍会挂起进程" | 官方为"降低终止概率、仍可能终止"，假申请会被终止进程 |
| `uploadFile/downloadFile` 后台可继续 | 传输可由系统代理，但**后台不支持回调**；仅 `agent.BACKGROUND` 明确不受影响 |
| `INSTALL_BUNDLE` 起始版本 9 | 起始版本为 **7**（等级/ACL 结论不变） |
| 普通应用没有任何公开 API 能触发安装 | 无"安装任意 HAP"的 API；`FLAG_INSTALL_ON_DEMAND` 仅按 ability 触发 |
| PC 可直接读应用沙箱 HAP | 仅 debug/root 或 shell 可读；零售机走应用内 HTTP 或用户导出 |
| `mediaLibrary` URI 持久、无需复制 | 无官方依据，降级为 M0 验证，默认复制进沙箱 |
| MP4 的 MPEG-2/MPEG-4 Part 2 官方未列 | 4.1 `media-kit-intro` 的 mp4 行明确列出两者（H.263 确实未列） |
| AVSession 可做系统播控 | 公开 SDK 只有 provider；全局 controller 必须是系统应用 |
| `AudioViewPicker`"audioPicker 在规划中" | 官方措辞为"当前实际弹出 documentPicker 页面" |
| picker URI "Web 直接读取即可"（通用） | `select` 只读、不可持久化（`FILE_ACCESS_PERSIST` 为 system_basic+ACL） |
## 11. Phase 2 M0 实测（2026-11-17）

- 工程：`D:\ohos-media`（`com.local.media`），AVPlayer + `fdSrc` + XComponent surface。
- **格式矩阵 10/10 通过**：FLAC/M4A/MP3/OGG(Vorbis)/OPUS/WAV/MKV(H.264)/MP4(H.264)/TS(H.264)/**HEVC(320x240)**。
  HEVC 小分辨率可播，风险收缩到 4K/10bit/大码率；不是容器格式问题。
- **后台播放**：AVSession + `audioPlayback` 后切到笔记，98 s 内 position 持续增长、`state=playing bg=yes`、进程存活（无 AVSession 时约 1.1 s 被暂停）。
- **Picker**：UI 能打开，但测试机 Documents/Download 显示 0 项（外部拷入不索引），picker→fd 仍需人工点一次验证。
- 结论：Phase 2 进入 M1（媒体库/导入复制）与 M2（音频播放器 UI+后台恢复），视频全屏放 M3。
- 详见 `docs/research/VERIFY-MEDIA-M0.md`。
## 12. 代码仓库（2026-11-17）

- 快传：https://github.com/Yuanyuan669/ohos-transfer （main `8947274`）
- 媒体：https://github.com/Yuanyuan669/ohos-media （main `e3c294f`）
- 浏览器 / 应用中心：目录已预建（`D:\ohos-browser`、`D:\ohos-appcenter`），GitHub 空仓库待推。
- 说明：两个仓库都保留了 GitHub 模板的 `LICENSE`（Initial commit），本地 `main` 已 rebase 并跟踪 origin。

- **2026-11-17 M2 完成**：音频播放器（音频列表、播放/暂停/seek、上下曲、播完自动下一首、后台播放），提交 `fca73b1`；修复 fdSrc 异步 initialized 导致的 5400102。

- **2026-11-17 M3 部分完成**：视频播放（H264 MP4/MKV/TS）+ 竖向沉浸全屏，commit `d9d0551`。坑：全屏按钮不可放状态栏、视频区插入导致列表坐标下移、强制横屏在本机变半屏。**修正 M0 结论：HEVC 可播放但 surface 黑屏**，待查。

- **2026-11-17 快传 M4/M5**：PIN 连续 5 次错误锁定 60s（`cb3952a`）；上传改为流式落盘、8GB 上限（`bfde246`），100MB 往返 SHA256 一致。HEVC 黑屏暂缓，转浏览器/应用中心。

- **2026-11-17 HEVC 结案**：`codec_caps.xml` 仅注册 h264/h263/mpeg2/mpeg4，无 HEVC 解码器与库，LHT16 系统镜像不支持 HEVC，应用层不可修；M0 的 HEVC OK 为误判（已更正）。

- **2026-11-17 HEVC 软解原型**：libde265 静态库 + 自带 MP4 解复用 + PixelMap 渲染，320x240/25fps 出画，渲染约 12.8fps（`42532a3`）；文档见 `ohos-media/docs/HEVC-SOFTDECODE.md`。后续若产品化需 XComponent+EGL 原生渲染提升帧率。

- **2026-11-17 Phase3 浏览器 M0**：`com.local.browser` 空壳 + Web 本地主页 + 地址栏/偏好；实测本地 45ms、example 226ms、Bing 228ms，PSS ~108MiB；自定义 UA 生效。commit `e8efc33`（本地，GitHub 仓库未建）。坑：ArkTS 无正则字面量、Web 回调对象类型需接口、rawfile 的 `resource://` 不能写进地址/偏好。

- **2026-11-17 浏览器 M1**：前进/后退/刷新/停止/主页、URL 规范化、错误覆盖层（-105 实测）、`aa start --ps url` 外部拉起；后退 13ms、前进 1ms、刷新 219ms。坑：字形缺失改中文按钮、startUrl 与 rawfile 竞态。commit（本地）。

- **2026-11-17 浏览器 M2**：3 标签上限/新建关闭切换、切标签销毁 Web、tabs+active 会话恢复；实测切换直载 379ms、重启恢复 2 标签。RSS 不降（Web 引擎缓存，API11 无 purge），记录为限制。


## Phase 5：远程控制（ohos-remote，PC 侧）

- 依据：`docs/research/APP-CAST-REMOTE.md`。投屏（Miracast/AirPlay）受 `CAPTURE_SCREEN=system_core` 与无 WFD 组件限制，第三方不可行；PC 侧 hdc 远控可行。
- 范围：设备发现（USB/TCP）、`snapshot_display` 画面（约 2~3 fps）、`uinput/uitest` 注入、文件 push/pull、shell/日志、常用按键。
- 里程碑：M0 hdc 封装+设备列表（0.5d）；M1 画面循环+缩放（1d）；M2 输入映射（1d）；M3 文件/应用/shell（1d）；M4 无线+打包（0.5~1d）。
- 非目标：音频、30fps 视频、系统级投屏。
- 可选后备：DLNA 媒体推送小工具（2~3d，价值有限）。

- **拓展备忘（DLNA 媒体推送）**：应用层 SSDP 发现电视 + `AVTransport` 推 URL，手机跑本地 HTTP 提供媒体；只推音视频/图片，不镜像，无需系统权限，2~3 人日。作为 Phase 5 可选后备，优先级低。

- **2026-11-17 ohos-remote MVP**：`D:\ohos-remote`，Python/Tkinter + hdc；设备发现、`snapshot_display` 实时画面（2.0 fps，1080x2408）、点击/拖拽/文本、文件上传、装 HAP、Shell、无线 tconn。无音频；依赖 uitest；本机验证画面与上传通过。commit（本地 `f5e03a7`，GitHub 仓库待建）。

- **2026-11-18 ohos-remote 打磨**：返回/主页键码实测（2/1，uinput）；PyInstaller 打包 30MB exe 可用（2.1fps）；agent 一键启动脚本。中文输入/TLS/开机自启仍待办。
