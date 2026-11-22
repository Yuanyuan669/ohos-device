# LHT16 多媒体应用调研与方案（OpenHarmony 4.1.7.5 / API 11）

> 性质：调研方案。本文只做只读实机探查与桌面调研，**不创建工程、不修改现有代码**；明天按第 7 节里程碑建工程。
> 实测时间：2026-11-17。设备：LHT16 / OpenHarmony-4.1.7.5 / API 11 / arm64-v8a / 8 GB / 1080x2408@60Hz。
> 约束：非系统应用、无系统签名；零三方依赖 ArkTS Stage；不碰 DRM。

## 0. 结论摘要（先看这 10 条）

1. **预置 `ohos.samples.distributedmusicplayer` 不能当日常音乐播放器用**。它是 API 10 的系统应用（system_core），播放列表硬编码为 `/system/etc/demo.wav` 和 `/system/etc/dynamic.wav` 两个文件，HAP 内没有 rawfile，也没有媒体库、文件选择器或 URI 入口。实测可启动、可出声，但无法播放用户自己的音乐。
2. 它是一个**分布式示例**，不是媒体产品：不使用 AVSession、不申请后台长时任务、不读媒体库。它退后台仍继续出声，是因为它是系统应用（或该 vendor 镜像未强制暂停），普通应用不能依赖这个现象。
3. **设备没有视频播放器**。`com.ohos.photos` 是唯一能播视频的预置应用；它可以播放 MP4（MPEG-4 Part 2 + AAC）的 `bootvideo.mp4`，但它是系统应用，普通应用无法复用它的媒体库全量权限。
4. **格式上限是本项目最大的硬约束**：设备注册的软件解码器只有 MP3/AAC/FLAC/Vorbis/Opus + H.264/H.263/MPEG-2/MPEG-4；硬件视频解码只有 H.264；**没有 HEVC/H.265、没有 AV1**。1080p H.264/AAC 是安全区；4K、HDR/10bit、HEVC 都要按“可能不支持”设计。
5. **后台播放必须同时接 AVSession + 长时任务**（`KEEP_BACKGROUND_RUNNING` + `audioPlayback`），否则按官方约束退后台会被强制暂停/挂起。`KEEP_BACKGROUND_RUNNING` 是 normal/system_grant，普通应用可用。
6. **AVSession 服务端可用，但系统没有播控中心 UI**：`AVSessionService` 在运行，SystemUI 全部 8 个 HAP 的 `modules.abc` 中 `avsession` 出现 0 次，系统也没有独立的媒体控制应用。因此“通知栏/锁屏播控”在本镜像上**开箱不可得**；能做的是应用内控制 + 长时任务通知，不能承诺系统级锁屏控制。
7. **媒体库权限要分三层看**：`READ_IMAGEVIDEO`、`READ_AUDIO`、`WRITE_AUDIO`、`FILE_ACCESS_PERSIST` 都是 `system_basic + ACL`，普通签名应用拿不到；`READ_MEDIA` 是 `normal + user_grant`，配合已废弃的 `mediaLibrary.getFileAssets` 仍可能读到音频/视频元数据与 fd，**必须在 M0 实测**。
8. **filepicker 可以绕过媒体库权限**：`PhotoViewPicker` / `DocumentViewPicker` / `AudioViewPicker` 不需要权限，由系统 `com.ohos.filepicker`（已预置）授予临时 URI 权限，返回 URI 后可 `fileIo.open` 拿 fd 交给 AVPlayer。但 `FILE_ACCESS_PERSIST` 是 system_basic，URI 权限**不能持久化**，要么每次重选，要么把文件复制进沙箱。
9. **推荐方案 B：自建媒体中心**（音乐+视频统一库、队列/歌单、后台播放、应用内播控）。预计 13.5 人日（含 M0 验证与测试，缓冲后 15）。方案 A 只能做“视频播放器”，音乐部分不可用；方案 C fork `cclisten` 需去掉 2 个 ohpm 依赖并重做 AVSession/权限，风险更高，不推荐作为首选。
10. **明天第一件事不是写 UI，而是 M0 验证**：READ_MEDIA 能否列音频/视频、picker URI 能否稳定拿 fd、AVSession+长时任务能否在普通签名应用上跑通、格式矩阵到底哪些能播。M0 不通过就切“picker 导入沙箱”的保守路线。

---

## 1. 调研方法与边界

- 实机：`hdc`（`$DEVECO_HOME/sdk/default/openharmony/toolchains/hdc.exe`，3.2.0f）只读探查；只做了 `aa start`、`uitest` 点击、`snapshot_display` 截图、`mediatool send` 添加测试视频、`hidumper` 查询。没有写系统分区、没有卸载/替换预置应用。
- 代码/文档：OpenHarmony 4.1-Release 官方文档；`applications_app_samples` 4.1 分支；`applications_photos` 4.1 分支；GitHub 上的 `cclisten` 等候选仓库。克隆/解压目录在临时目录 `opencode/media-research/`（仓库外，不污染本仓）。
- 设备侧“实测”与“文档推断”在文中分别标注；没有条件实测的（普通应用 READ_MEDIA、AVSession 后台）明确标为 M0 待验证。

---

## 2. 现状实测

### 2.1 设备基线

| 项 | 实测值 | 来源 |
| --- | --- | --- |
| 型号 / 产品 | LHT16 / 开发者手机 | `param get const.product.model` |
| 系统 | OpenHarmony-4.1.7.5 | `param get const.ohos.fullname` |
| API | 11 | `param get const.ohos.apiversion` |
| ABI | arm64-v8a | `param get const.product.cpu.abilist` |
| 内存 | MemTotal 7,502,556 kB（约 7.15 GiB 可用） | `/proc/meminfo` |
| 屏幕 | 1080x2408，竖屏物理方向，60 Hz | `snapshot_display` / `docs/DEVICE.md` |
| 导航 | 三键（返回/Home/任务），非手势导航 | 截图 |
| 调试 | `const.debuggable=1`、`const.secure=0`、selinux permissive | `docs/DEVICE.md` |

> 结论：8 GB 内存对 1080p 本地播放足够；4K/多路解码才是压力点。三键导航意味着全屏手势冲突比手势导航设备小，但仍要处理系统栏显隐。

### 2.2 预置分布式音乐播放器（`ohos.samples.distributedmusicplayer`）

#### 2.2.1 包信息（`bm dump -n` 摘要）

| 字段 | 值 |
| --- | --- |
| bundleName | `ohos.samples.distributedmusicplayer` |
| 版本 | 1.0.5（versionCode 1000005） |
| compileSdk | 4.0.10.19（OpenHarmony 4.0） |
| apiCompatible / target | 10 / 10 |
| isSystemApp | **true** |
| appPrivilegeLevel | **system_core** |
| appProvisionType | release |
| appDistributionType | os_integration |
| 安装位置 | `/system/app/.../Music_Demo.hap`（preinstall） |
| uid | 20010034 |
| Ability | `...MainAbility`（launcher）+ `ServiceAbility`（service 扩展） |
| backgroundModes | 0（未声明长时任务） |
| allowEnableNotification | false |
| 申请权限 | `DISTRIBUTED_DATASYNC`、`ACCESS_SERVICE_DM`、`START_ABILITIES_FROM_BACKGROUND`、`START_INVISIBLE_ABILITY` |
| 权限状态 | `[0, -1, 0, 0]`（ACCESS_SERVICE_DM 已授予；DISTRIBUTED_DATASYNC 启动时未授予，弹窗后授予；后两项已授予） |

#### 2.2.2 能力入口与启动

- launcher 入口存在（`entity.system.home`），桌面可见；也可以用命令启动。
- **短名启动失败**：`aa start -a MainAbility -b ohos.samples.distributedmusicplayer` → `error: resolve ability err.`
- **全名启动成功**：
  ```powershell
  hdc shell "aa start -b ohos.samples.distributedmusicplayer -a ohos.samples.distributedmusicplayer.MainAbility -m entry"
  ```
- 首次启动会弹“是否允许 DistributedMusicPlayer 使用多设备协同？”（`DISTRIBUTED_DATASYNC` user_grant）；应用日志随后显示 `authResults:[0]`（已授予）。UI 显示 `dynamic.wav`、时长 01:08、黑胶唱片封面。
- 启动后 `pidof` 有进程，`aa dump -a` 中 ability 状态正常。

#### 2.2.3 HAP 解剖：它到底能播什么

把 `/system/app/.../Music_Demo.hap` 拉回解压后：

- 代码：`ets/modules.abc`（126 KB），Stage 模型，`uiSyntax: ets`，`srcEntrance` 是 `.ts`。
- 资源：只有 `album.png`、`album2.png`、图标、播放/暂停/上一首/下一首 SVG，**没有 rawfile、没有 mp3/wav**。
- 字符串里写死的播放列表：
  ```
  /system/etc/demo.wav
  /system/etc/dynamic.wav
  ```
  设备上这两个文件确实存在：
  ```
  -rw-r--r-- 1 root root  7483806 2024-06-25 07:26 /system/etc/demo.wav
  -rw-r--r-- 1 root root 12086036 2024-06-25 07:26 /system/etc/dynamic.wav
  ```
- 播放实现：`AudioPlayer`（8 处）、`audioInterrupt`（1 处）、`fileIo`、`fd://`；**没有** `AVSession`、`mediaLibrary`、`photoAccessHelper`、`picker`、`backgroundTask`、`Notification`（在 `modules.abc` 中均 0 次）。
- 播放/暂停/上一首/下一首、进度条、封面旋转、蓝牙/分布式投播是它的主要功能；还有 `startAbilityContinuation`（跨端迁移）。

#### 2.2.4 播放实测

- 点击播放按钮（`uitest uiInput click 672 2082`）后：
  - 截图显示 `00:05 / 01:08`，进度条前进，按钮变为暂停。
  - `hidumper -s AudioPolicyService -a '-p'` 显示一条 `s16le 2ch 44100Hz` 的 `Status:RUNNING` 流。
- 说明：本地 WAV + AudioPlayer 通路是通的，声音正常。

#### 2.2.5 后台实测

- 播放中按 Home，`aa dump -a` 显示该 ability `state #BACKGROUND / app state #BACKGROUND`。
- 16 秒后 `AudioPolicyService -p` 仍为 `RUNNING`，说明**这个系统应用没有被强制暂停**。
- 但它没有 AVSession、没有长时任务通知；不能据此推断普通应用也能这样。普通应用必须按第 3.2 节接 AVSession + 长时任务。

#### 2.2.6 结论

| 问题 | 结论 |
| --- | --- |
| 能直接当音乐播放器用吗？ | **不能**。只能播 `/system/etc` 下两个固定 WAV，无法选文件、无法读媒体库、无播放列表导入。 |
| 能通过 Want/URI 让它播用户文件吗？ | 不能。代码里没有 URI/参数入口，播放列表是常量。 |
| 能修改它吗？ | 不能。`/system` 只读，且它是系统签名应用；普通应用无法替换/扩展。 |
| 能唤起它做“演示”吗？ | 可以，`aa start` 全名即可；只适合演示，不适合日常。 |
| 它的后台行为能复用吗？ | 不能。它是 system_core 系统应用，普通应用没有同样的豁免。 |

### 2.3 图库/媒体库（`com.ohos.photos` + `com.ohos.medialibrary.medialibrarydata`）

#### 2.3.1 Photos 包信息

| 字段 | 值 |
| --- | --- |
| 版本 | 1.0.19，compileSdk 4.1.7.1，target API 11 |
| isSystemApp | **true**（os_integration，preinstall） |
| appPrivilegeLevel | normal（但系统镜像签名使其拿到 ACL 权限） |
| 关键权限 | `READ_IMAGEVIDEO`、`WRITE_IMAGEVIDEO`、`MEDIA_LOCATION`、`PROXY_AUTHORIZATION_URI`、`START_ABILITIES_FROM_BACKGROUND` |
| 扩展 | `sysPicker/photoPicker`（PhotoViewPicker 的系统实现）、`ServiceExtAbility`、Form |
| 说明 | 有 photoPicker 扩展，说明普通应用可以通过 `PhotoViewPicker` 借用它的选择 UI 和临时授权 |

#### 2.3.2 媒体库数据现状

- 媒体库 data 应用：`com.ohos.medialibrary.medialibrarydata`，target API 9，版本 4.0.10.5，`dataShare` + `backup` 扩展，系统应用。
- `mediatool list all` 初始只有 3 张 JPG（`Photos` 表），`Audios` 表为空。
- 把 `/system/etc/graphic/bootvideo.mp4` 通过 `mediatool send` 加入后，`Photos` 表出现：
  ```
  file://media/Photo/4/VID_1794865993_000/bootvideo.mp4
  ```
  （注意：视频也放在 Photo 表/Photo URI 下，这是这套媒体库的实现方式。）
- 结论：设备媒体库可用，但**音频库为空**；视频/图片可被 Photos 索引。

#### 2.3.3 视频播放实测

- 启动 Photos（`aa start -b com.ohos.photos -a com.ohos.photos.MainAbility`），网格中出现 `00:05` 视频缩略图。
- 点进视频，点播放：出现 OpenHarmony 开机动画，`AudioPolicyService -p` 新增 `Status:RUNNING` 流。
- 该 `bootvideo.mp4` 的 MP4 box 里是 `mp4v`（MPEG-4 Part 2）+ `mp4a`（AAC），不是 H.264/HEVC。说明这条通路至少能软解 MPEG-4 Part 2 + AAC。
- 这同时证明：**系统里确实没有独立视频 App**，视频只能走 Photos；普通应用不能直接复用 Photos 的全量媒体库权限。

### 2.4 系统多媒体服务与解码能力

#### 2.4.1 在运行的 SA（`hidumper -ls` 摘要）

存在且相关：

- `AVSessionService`（音视频会话）
- `AVCodecService`（编解码）
- `MediaKeySystemService`（DRM，本项目不碰）
- `PlayerDistributedService`（分布式播放）
- `AudioPolicyService`、`audio_server`、`codec_host`、`media_service`、`av_codec_servic`

结论：API 11 的 AVSession/AVCodec 服务端是齐的；缺的是系统播控 UI（见 2.5）。

#### 2.4.2 软件编解码能力（`/system/etc/codec/codec_caps.xml`）

音频解码：

| 编码 | MIME | 备注 |
| --- | --- | --- |
| MP3 | `audio/mpeg` | 8k–96k Hz，1–2 ch |
| AAC | `audio/mp4a-latm` | AAC_LC，ADTS，8k–96k Hz |
| Vorbis | `audio/vorbis` | 1–7 ch，最高 192k Hz |
| FLAC | `audio/flac` | 1–2 ch，最高 96k Hz |
| Opus | `audio/opus` | 48k Hz，1–2 ch |

音频编码：AAC、Opus。

视频解码：

| 编码 | MIME | profile / 备注 |
| --- | --- | --- |
| H.264 | `video/avc` | Baseline/Main/High，最大 3840x2160，NV12/NV21 |
| H.263 | `video/h263` | H263Baseline |
| MPEG-2 | `video/mpeg2` | Main/Simple |
| MPEG-4 Part 2 | `video/mp4v-es` | Simple/AdvancedSimple |

视频编码：MPEG-4（最大 1920x1080）。

**没有** HEVC、VP8/VP9、AV1 的 caps 条目。

#### 2.4.3 FFmpeg/解封装实际编译内容（`libohosffmpeg.z.so` 字符串）

- 解封装器：`mov,mp4,m4a,3gp,3g2,mj2`、`matroska/webm`、`mp3`、`aac`、`flac`、`ogg`、`wav`、`ape`、`amr`、`mpegts`。
- 解码器：`aac`、`aac_latm`、`h264`、`h263`、`mpeg2video`、`mpeg4`、`vp8`、`vp9`、`amrnb`、`amrwb`、`ape`、`flac`、`mp3`、`opus`、`vorbis`。
- **没有 HEVC/H.265 解码器、没有 AV1 解码器**。

#### 2.4.4 厂商硬件解码库（`/vendor/lib64`）

- 视频：`libomx_avcdec_hw_sprd.z.so`（H.264 硬解）、`libomx_avcenc_hw_sprd.z.so`（H.264 硬编）。
- 没有 `hevc/h265/vp9/av1` 相关库。
- 结论：H.264 可硬解；HEVC/AV1 既无硬解也无软解，**在这台设备上按不支持处理**。

> 注意：媒体框架里存在 `video/hevc` 的 MIME 字符串和 `FrameDetectorH265`，这只说明框架“认识”H.265，不代表有可用解码器。能力要以 codec caps + 厂商库为准。

### 2.5 系统播控/通知/锁屏

- `AVSessionService` 在运行，但 SystemUI 全部 8 个 HAP（`SystemUI`、`StatusBar`、`DropdownPanel`、`NotificationManagement`、`ScreenLock`、`NavigationBar`、`SystemDialog`、`VolumePanel`）的 `modules.abc` 中 `avsession` 出现次数均为 **0**。
- 已安装 bundle 列表里没有 `com.ohos.mediacontroller`、`com.ohos.avsession` 之类的播控应用。
- 结论：
  - **没有系统级“播控中心”/通知栏媒体卡片/锁屏媒体控制**。
  - AVSession 仍然要接：它是后台播放约束的一部分，也为未来系统升级留接口；但不要向用户承诺锁屏控制。
  - 应用内播放控制 + 长时任务通知（系统生成“正在运行”通知）是现实方案；自定义通知可以带按钮，但不是系统媒体卡片样式。

### 2.6 权限与文件选择器

#### 2.6.1 关键权限级别（4.1 文档）

| 权限 | 级别 | 授权 | ACL | 普通应用可得？ |
| --- | --- | --- | --- | --- |
| `ohos.permission.READ_MEDIA` | normal | user_grant | - | **可以申请**（但 mediaLibrary API 已废弃） |
| `ohos.permission.READ_IMAGEVIDEO` | system_basic | user_grant | true | **否** |
| `ohos.permission.WRITE_IMAGEVIDEO` | system_basic | user_grant | true | **否** |
| `ohos.permission.READ_AUDIO` | system_basic | user_grant | true | **否** |
| `ohos.permission.WRITE_AUDIO` | system_basic | user_grant | true | **否** |
| `ohos.permission.FILE_ACCESS_PERSIST` | system_basic | system_grant | true | **否** |
| `ohos.permission.FILE_ACCESS_MANAGER` | system_basic | system_grant | true | **否** |
| `ohos.permission.KEEP_BACKGROUND_RUNNING` | normal | system_grant | - | **可以** |
| `ohos.permission.PROXY_AUTHORIZATION_URI` | system_basic | system_grant | true | **否** |

> Photos 能拿到 `READ_IMAGEVIDEO`，是因为它是系统镜像内应用（os_integration），不是普通应用可复制的路径。

#### 2.6.2 filepicker 实测/静态证据

- `com.ohos.filepicker` 已预置，版本 1.1.0.300，target API 10，`MainAbility` 声明了 `ohos.want.action.OPEN_FILE` / `CREATE_FILE`。
- 其 `module.json` 申请了 `READ_MEDIA`、`WRITE_MEDIA`、`MEDIA_LOCATION`、`FILE_ACCESS_MANAGER`、`GET_BUNDLE_INFO_PRIVILEGED`、`PROXY_AUTHORIZATION_URI` —— 它自己是系统应用，负责借用权限并给调用方授权。
- HAP 字符串里可见：
  - `FILE_PICKER`、`PATH_PICKER`
  - `grantUriPermission`、`terminateFilePicker`、`terminatePathPicker`
  - `getKeyFileSuffixFilter`、`getKeyPickTypeList`
- 结论：`DocumentViewPicker`/`PhotoViewPicker`/`AudioViewPicker` 走系统 picker，**调用方不需要媒体库权限**；picker 会给返回的 URI 授予临时读权限，可用 `fileIo.open` 拿 fd。
- 限制：`FILE_ACCESS_PERSIST` 是 system_basic，普通应用不能把 URI 权限持久化；应用重启后要么重新选，要么把文件复制进沙箱。
- `AudioViewPicker` 在 4.1 文档里注明“目前仅支持 documentPicker，audioPicker 在规划中”，实际行为可能退回文档选择器；M0 要实测。

---

## 3. 能力与格式支持（API 11）

### 3.1 AVPlayer / AudioRenderer

**AVPlayer（推荐用于音乐+视频）**

- 端到端播放：解封装、解码、音视频同步、渲染；视频需要 `XComponent` 的 SurfaceID。
- 本地资源：推荐 `fd://<fd>` 或 `fdSrc`（`AVFileDescriptor`），官方明确“支持 file descriptor，禁止 file path”。
- 支持事件：`stateChange`、`error`、`durationUpdate`、`timeUpdate`、`seekDone`、`speedDone`、`bufferingUpdate`、`audioInterrupt`、`videoSizeChange`。
- 状态机：idle → initialized → prepared → playing/paused/completed → stopped → idle/released；`reset()` 换源，`release()` 释放。
- 视频渲染：把 `surfaceId` 传给 AVPlayer，帧经 Graphic/Display HDI 上屏。
- 音频焦点：`audioInterrupt` 回调 + `audioInterruptMode`；被通话/其他媒体抢占时要暂停并决定是否恢复。

**AudioRenderer（按需）**

- 用于 PCM 输出、低时延、可视化/自定义解码；不解 MP3/AAC/FLAC 等压缩格式。
- 音乐播放用 AVPlayer 更省事；AudioRenderer 只在做可视化、均衡器或自定义解码时考虑。
- 设备上 `libaudio_renderer`、`liboffload_audio_renderer`、`libfast_audio_renderer` 都在，能力具备。

**AVMetadataExtractor / AVImageGenerator**

- 可用于读时长、标题、艺术家、专辑、封面；`AVImageGenerator` 可抓视频帧做缩略图。媒体中心做列表/封面会用到。

### 3.2 后台播放、音频焦点、AVSession

官方 4.1 约束（`avsession-overview.md` + `continuous-task.md`）：

- 所有需要后台播放的音视频应用，**必须同时接入 AVSession 和后台任务管理**；未接入的应用退后台会被强制暂停音频。
- 长时任务类型 `AUDIO_PLAYBACK`（配置项 `audioPlayback`），需要：
  - `ohos.permission.KEEP_BACKGROUND_RUNNING`（normal/system_grant）；
  - UIAbility 的 `backgroundModes: ["audioPlayback"]`；
  - `backgroundTaskManager.startBackgroundRunning(context, BackgroundMode.AUDIO_PLAYBACK, wantAgent)`；
  - 暂停/停止时及时 `stopBackgroundRunning`；
  - 系统会校验“是否真的在播放”，假申请会被管控；通知栏会出现系统长时任务通知，用户删除通知会停止任务。
- 数量限制：一个 UIAbility 同一时刻只能申请一个长时任务；一个 UIAbility 申请后，整个应用进程不被挂起。
- Stage 模型只支持 UIAbility 申请（不是 ServiceExtension）。
- 音频焦点：AVPlayer 的 `audioInterrupt` 事件；被抢占时暂停，`InterruptHint` 决定是否可恢复；不要强抢焦点。
- 本机现状：AVSessionService 在跑；SystemUI 没有 AVSession 播控（见 2.5）。所以“后台播放”可以做，“锁屏/通知播控”不能按系统能力承诺。

### 3.3 媒体库与文件访问矩阵

| 目标 | 可用路径 | 权限 | 结论 |
| --- | --- | --- | --- |
| 列图片/视频（全库） | `photoAccessHelper.getAssets` | `READ_IMAGEVIDEO`（system_basic ACL） | **普通应用不可用** |
| 列音频（全库） | `mediaLibrary.getFileAssets`（已废弃） | `READ_MEDIA`（normal user_grant） | **可能可用，M0 必测** |
| 打开音频/视频 fd | `mediaLibrary` 的 `FileAsset.open('r')` / URI | `READ_MEDIA`（文档写 READ_MEDIA or WRITE_MEDIA） | 若上一条可用，则可能直接播放 |
| 选图片/视频 | `PhotoViewPicker` | 无 | 可用；返回 URI，临时授权 |
| 选任意文件（音视频） | `DocumentViewPicker` | 无 | 可用；支持后缀过滤，返回 URI |
| 选音频 | `AudioViewPicker` | 无 | API 11 存在；4.1 文档提示可能退回 documentPicker，M0 实测 |
| 选目录 | `DocumentViewPicker` + `DocumentSelectMode`（API 11） | 无 | 能力存在；目录枚举/持久访问需实测 |
| 持久访问用户文件 | `fileshare.persistPermission` | `FILE_ACCESS_PERSIST`（system_basic ACL） | **普通应用不可用** |
| 应用沙箱内播放 | `context.filesDir` + `fs.open` + `fd://` | 无 | 可用；最稳 |
| 直接路径播放 | `avPlayer.url = '/data/...'` | - | 官方禁止 file path，必须 fd/fdSrc |

**推荐决策树（M0 验证后二选一）**

1. 若 `READ_MEDIA + mediaLibrary` 能列出音频/视频并拿到可播放 fd：
   - 用它做“统一媒体库”，URI 持久、无需复制文件；
   - 把 mediaLibrary 封装在 `MediaRepository` 接口后面，未来 API 变化只改一层。
2. 若不能：
   - 用 `DocumentViewPicker`/`AudioViewPicker` 让用户选文件或目录；
   - 首次导入时把文件复制到 `filesDir/media/{audio,video}`，建立本地索引（RDB/Preferences）；
   - 优点：权限稳定、播放稳定；缺点：占双份空间、导入慢。
3. 视频也可以单独用 `PhotoViewPicker` 选（无需权限），但音频不在 photoPicker 范围。

### 3.4 格式支持矩阵（设备证据 + 官方文档 + 建议）

**音频**

| 容器/编码 | 官方 AVPlayer 4.1 | 设备证据 | 建议 |
| --- | --- | --- | --- |
| MP3 | 支持 | `avdec_mp3`、`ff_mp3_demuxer` | **主推** |
| AAC（.aac/ADTS） | 支持 | `avdec_aac`、`ff_aac_demuxer` | **主推** |
| M4A（AAC） | 支持 | `mov,mp4,m4a` 解封装 + AAC | **主推** |
| WAV（PCM） | 支持 | `ff_wav_demuxer`；预置 demo 实际播放 | 可用 |
| OGG/Vorbis | 支持 | `ff_ogg_demuxer` + `avdec_vorbis` | 可用 |
| FLAC | 官方列表未列 | `avdec_flac` + `ff_flac_demuxer` | **可能可用，M0 实测** |
| Opus | 官方列表未列 | `avdec_opus` + `ff_ogg_demuxer` | 可能可用，48k；M0 实测 |
| APE/AMR | 未列 | ffmpeg 有解码器/解封装 | 不建议承诺 |
| HE-AAC（SBR） | 未列（caps 只写 AAC_LC） | ffmpeg aac 解码器可能支持 | 实测；不行就提示转 AAC-LC |

**视频**

| 容器/编码 | 官方 4.1 | 设备证据 | 建议 |
| --- | --- | --- | --- |
| MP4 / H.264 + AAC | 支持（必选） | `avdec_h264` + vendor H.264 硬解 | **主推** |
| MP4 / MPEG-4 Part 2 + AAC | 未重点列 | `avdec_mpeg4`；bootvideo 实测可播 | 可用（老文件） |
| MP4 / H.263、MPEG-2 | 未列 | `avdec_h263`、`avdec_mpeg2video` | 可用但少见 |
| MKV / H.264 + AAC | 官方支持 mkv | `ff_matroska_demuxer` + H.264 | 可用；字幕/多轨要自己处理 |
| TS / H.264 + AAC | 官方支持 ts | `ff_mpegts_demuxer` | 可用 |
| WebM / VP8/VP9 | 未列 | ffmpeg 有 vp8/vp9 软解 + matroska | 可能可用，1080p 软解性能待测 |
| **MP4/MKV / HEVC(H.265)** | 官方写“必选”，但本机无解码器 | codec caps 无、vendor 无、ffmpeg 无 | **按不支持处理**；必须给友好提示 |
| AV1 | 未列 | 无 | 不支持 |
| 10bit/HDR | - | caps 只有 NV12/NV21、AVC 8bit profile | 不承诺；HDR 片源可能花屏/黑屏 |
| 4K | 文档说主流分辨率 | caps 允许到 3840x2160/30fps，但 measuredFrameRate 只标 1920x1080@30，且只有 H.264 硬解 | 1080p 稳；4K 需实测，不作为 MVP 承诺 |
| AVI/FLV/WMV | 未列 | 未在解封装字符串中确认（按不支持设计） | 不承诺；M0 可抽查 |

> 结论：产品文案写“支持 MP3/AAC/M4A/WAV/OGG/FLAC（待验证）/MP4(H.264)/MKV(H.264)/TS(H.264)”，不要写“全格式”。遇到 HEVC/AV1/10bit 直接提示“设备不支持该编码，请转 H.264/AAC”。

---

## 4. 候选方案对比

### 4.1 方案 A：复用/唤起预置音乐播放器 + 自建视频播放器

- 音乐：`aa start` 唤起 `ohos.samples.distributedmusicplayer`。
- 视频：用官方 `VideoPlay` 样例（API 10）+ 文件选择器 + 全屏/横竖屏。

评价：

- 音乐部分**不可行**：预置应用只读 `/system/etc` 两个 WAV，没有 URI/Want 入口，不能读媒体库，也没有 AVSession。
- 视频部分可行：VideoPlay 样例已有 XComponent、播放/暂停、进度、倍速、切换；补 picker、AVSession（可选）、横竖屏即可。
- 工作量：4–5 人日（仅视频）。
- 风险：低（视频），但产品目标“日常多媒体体验”只完成一半。

### 4.2 方案 B：自建媒体中心（音乐 + 视频）

- 统一媒体库（音频+视频），播放列表、收藏、最近播放、搜索。
- 音乐：AVPlayer + AVSession + 长时任务 + 音频焦点。
- 视频：AVPlayer + XComponent + 手势/全屏/横竖屏 + 续播。
- 应用内播控页；系统播控不做承诺（本机没有）。

评价：

- 可控性最好，零三方依赖，权限/格式/后台都能按设备实际情况设计。
- 工作量：13.5 人日（含 M0 与测试；缓冲 15）。
- 风险：中；主要风险集中在权限/格式/后台，已在 M0 前置。

### 4.3 方案 C：fork 开源项目裁剪（以 `cclisten` 为主）

`seagazer/cclisten`：

- Apache-2.0；ArkTS Stage；`compileSdkVersion 11`、`compatibleSdkVersion 11`、`runtimeOS: OpenHarmony`，README 写明 DevEco 4.1.0.400 + full-SDK 4.1.7.5，和本机环境一致。
- 规模：51 个 ts/ets，约 3,765 行；有首页、歌单、收藏、历史、歌词、主题、播放服务、SQLite 歌单、后台任务、AVSession 雏形。
- 依赖：`@seagazer/ccplayer`、`@seagazer/cclyric`（ohpm 三方包）——**违反“零三方依赖”**，必须替换。
- 权限：`READ_MEDIA` + `READ_AUDIO`；`READ_AUDIO` 是 system_basic，普通应用拿不到；扫描走 `mediaLibrary.getMediaLibrary`（已废弃）。
- AVSession：只 `createAVSession`，没有 `setAVMetadata` / `setAVPlaybackState` / 控制器命令监听（在当前版本代码中未发现），后台/播控不完整。
- 结论：**适合作为 UI/交互/歌单/歌词的参考，不适合直接 fork 交付**。要替换播放器、歌词库、权限层、AVSession 层，工作量接近自建。

`QAQ-cmyk/OpenHarmony-video-player`：

- MIT；`runtimeOS: HarmonyOS`、API 10；学生项目，带登录/注册/网络视频列表/收藏；不是 OpenHarmony 4.1 工程，复用价值低。

`BuiDerCode/openharmony-music-player`：

- Hi3861 轻量系统 C 项目（PWM 蜂鸣器/OLED），与手机 ArkTS 无关，排除。

`openharmony/applications_photos`（4.1 分支）：

- Apache-2.0，系统图库，含视频播放；已克隆 4.1 分支核查：`compileSdkVersion 11`，`product/phone/src/main/ets/pages/VideoBrowser.ets` 用的是 ArkUI `Video` 组件 + `VideoController`，**没有 AVSession**；权限依赖 `READ_IMAGEVIDEO`/`WRITE_IMAGEVIDEO` 等系统权限，不可直接作为三方应用交付；只能参考全屏/系统栏/播放器交互。

官方 `applications_music` / `applications_video(videos)`：

- 在 gitee/github 的 `openharmony` 组织下未检索到公开仓库（`git ls-remote` 失败）；可用的官方素材是 `applications_app_samples` 与 `applications_photos`。

### 4.4 对比表

| 维度 | A 预置+视频 | B 自建媒体中心 | C fork cclisten |
| --- | --- | --- | --- |
| 音乐可用性 | 不可用（只能播 2 个系统 WAV） | 完整 | 完整（需改造） |
| 视频可用性 | 可用 | 完整 | 需另加/整合 |
| 格式支持 | 设备同一套解码器 | 同左，可控提示 | 同左（CcPlayer 封装） |
| 后台播放 | 预置应用是系统应用，不能复制 | AVSession+长时任务，可行 | 有雏形，需补全 |
| 通知/锁屏播控 | 无 | 系统无播控；仅应用内+长时任务通知 | 同左 |
| 零三方依赖 | 是 | 是 | **否**（ccplayer/cclyric） |
| 权限风险 | 低（不读库） | 中（READ_MEDIA 待测） | 高（READ_AUDIO 不可得、mediaLibrary 废弃） |
| 工作量 | 4–5 人日 | 13.5 人日（缓冲 15） | 12–15 人日，且返工风险高 |
| 适合度 | 只做视频 | **推荐** | 参考代码，不作为首选 |

---

## 5. 推荐方案（B）：自建媒体中心

### 5.1 产品范围

**MVP（第一版必须）**

- 首页：最近播放、音乐/视频入口、本地媒体数量。
- 音乐：列表/专辑/歌手（能拿到多少算多少）、播放页（封面/标题/进度/上一首/下一首/循环/随机）、队列、收藏。
- 视频：网格/列表、播放页（播放/暂停/进度/倍速/全屏/横竖屏/续播）。
- 媒体导入：媒体库扫描（若 READ_MEDIA 可用）或 picker 导入沙箱。
- 后台：音乐退后台继续播（AVSession + 长时任务）；视频退后台暂停。
- 设置：扫描目录/重新扫描、清空缓存、关于。

**后续（可选）**

- 歌词（.lrc）解析与滚动；封面抓取；睡眠定时；播放历史统计；画中画（如 API 11 可用且设备支持）；DLNA/投播（不承诺）。

**明确不做**

- DRM（`MediaKeySystemService` 存在也不接）。
- HEVC/AV1 软解、4K 转码、HDR 色调映射。
- 系统级锁屏播控/通知媒体卡片（本机 SystemUI 无 AVSession）。
- 修改/替换预置系统应用。

### 5.2 架构（Stage / ArkTS，零三方依赖）

```
entry/src/main/ets/
├─ entryability/EntryAbility.ets          // 初始化、窗口、权限申请
├─ pages/
│  ├─ Index.ets                           // Tabs：音乐/视频/最近/设置
│  ├─ MusicPlayerPage.ets                 // 音乐播放页
│  ├─ VideoPlayerPage.ets                 // 视频播放页（XComponent）
│  └─ SettingsPage.ets
├─ core/
│  ├─ PlayerEngine.ets                    // AVPlayer 状态机封装（单实例）
│  ├─ SessionController.ets               // AVSession + 长时任务 + 焦点
│  ├─ MediaRepository.ets                 // 统一媒体库接口
│  ├─ MediaLibrarySource.ets              // READ_MEDIA + mediaLibrary（可替换）
│  ├─ PickerImportSource.ets              // Document/Audio/Photo Picker 导入
│  ├─ SandboxStore.ets                    // 沙箱媒体索引/复制
│  └─ PlayQueue.ets                       // 队列/循环/随机
├─ model/                                 // MediaItem / Playlist / History
├─ components/                            // 列表项、封面、进度条、空态、错误态
└─ utils/                                 // 时间/文件/日志/权限
```

关键设计：

- **一个 AVPlayer 实例**：音乐/视频切换时 `reset()`/`release()`，避免同时占用解码器/内存。
- `PlayerEngine` 只暴露 `setSource(fd, type)`、`play/pause/seek/setSpeed/release`、状态回调；UI 不直接碰 AVPlayer。
- `SessionController`：
  - 音乐播放时创建/激活 AVSession，`setAVMetadata` + `setAVPlaybackState`；
  - 播放开始 `startBackgroundRunning(AUDIO_PLAYBACK)`，暂停/停止 `stopBackgroundRunning`；
  - 监听 `audioInterrupt`，暂停并在合适时机恢复；
  - 视频不申请长时任务（退后台暂停）。
- `MediaRepository` 接口化：`listAudio()`、`listVideo()`、`openFd(item)`、`import(files)`。底层可在 `MediaLibrarySource` 和 `PickerImportSource` 之间切换，M0 结果决定默认实现。

### 5.3 媒体库/权限策略

1. 启动时申请 `READ_MEDIA`（normal/user_grant），尝试 `mediaLibrary.getFileAssets` 查 AUDIO/VIDEO。
2. 成功：建立内存索引 + 轻量缓存（Preferences/RDB），列表直接用 `fileAsset.uri` + `open('r')` 拿 fd 播放。
3. 失败/为空：显示“导入媒体”入口：
   - 音乐：`AudioViewPicker` 或 `DocumentViewPicker`（后缀 `mp3,aac,m4a,flac,wav,ogg,opus`）；
   - 视频：`PhotoViewPicker` 或 `DocumentViewPicker`（后缀 `mp4,mkv,ts,webm`）；
   - 选中后复制到 `filesDir/media/...`，写本地索引；后续从沙箱播放。
4. 不建议依赖 `FILE_ACCESS_PERSIST`（system_basic，拿不到）。
5. 媒体库 API 已废弃：全部包在 `MediaLibrarySource` 内，未来系统移除时只换实现，不动 UI。

### 5.4 播放/后台策略

- 音乐：
  - AVPlayer + `fd://`；`audioInterrupt` 暂停；`completed` 自动下一首；`timeUpdate` 更新进度和 AVSession。
  - 进入播放即 `activate()` AVSession，设置 metadata（title/artist/album/duration/cover）。
  - 播放时申请长时任务；暂停/停止/播放结束释放。
  - 拔耳机/蓝牙断开：监听音频设备/输出设备变化（AVSession 或 audio 模块提供的路由能力），暂停而不是外放。
- 视频：
  - `XComponent` 拿 surfaceId，AVPlayer `surfaceId` 设置；`videoSizeChange` 调整宽高比。
  - 退后台/锁屏暂停；来电/焦点丢失暂停。
  - 续播：按 URI/文件大小/修改时间做 key，存 `position`。
- 通用：
  - 错误：`error` 回调 → `reset()`/`release()` → 友好提示（编码不支持/文件损坏/权限丢失）。
  - 内存：页面 `aboutToDisappear` 释放播放器；缩略图缓存上限（如 100 张/64 MB）。

### 5.5 视频 UI / 手势 / 横竖屏

- 全屏：`window.setWindowLayoutFullScreen(true)` + `setWindowSystemBarEnable([])`；退出恢复。
- 方向：进入视频默认横屏（`setPreferredOrientation(landscape)`），退出恢复竖屏；设置里可关“自动横屏”。
- 手势（三键导航设备冲突较小）：
  - 单击：显示/隐藏控制层（5s 自动隐藏）；
  - 双击：播放/暂停；
  - 左右滑：seek（显示目标时间）；
  - 上下滑（左半屏亮度/右半屏音量，若系统 API 允许）；
  - 长按：倍速（可选）。
- 控制层：播放/暂停、进度、时间、倍速（0.5/0.75/1.0/1.25/1.5/2.0）、上一部/下一部、锁定、全屏。
- 横竖屏切换时保存/恢复进度与播放状态；`XComponent` 重建要重新设置 surfaceId。

### 5.6 可复用清单（按许可证）

| 来源 | 许可 | 复用什么 | 不复用什么 |
| --- | --- | --- | --- |
| `applications_app_samples` → `BasicFeature/Media/VideoPlay`（4.1 分支） | Apache-2.0 | AVPlayer 状态机、XComponent、进度/倍速/视频切换、UI 结构 | 网络视频/WiFi 逻辑、API 10 写法按需升级 |
| `applications_app_samples` → `BasicFeature/Media/AVSession/MediaProvider` | Apache-2.0 | AVSession 创建/激活、`setAVMetadata`、`setAVPlaybackState`、play/pause 控制器命令、长时任务 | 它的固定曲目/示例数据 |
| `applications_app_samples` → `BasicFeature/Media/AVSession/VideoPlayer` | Apache-2.0 | AVSession + 视频播放的整合方式、AVCastPicker 用法（可选） | 网络 URL 列表、无本地文件的逻辑 |
| `seagazer/cclisten` | Apache-2.0 | 页面组织、歌单/收藏/历史/歌词 UI 思路、主题 | `@seagazer/ccplayer`、`@seagazer/cclyric`、`READ_AUDIO` 扫描、废弃 mediaLibrary 直接依赖 |
| `openharmony/applications_photos` | Apache-2.0 | 视频播放/图库交互参考 | 系统权限、系统签名、系统组件依赖 |
| 预置 `distributedmusicplayer` | 系统应用 | 只做“能力对照/演示” | 不能改、不能作为库、没有 URI 入口 |

> 许可证注意：Apache-2.0 复用时保留版权头/NOTICE；不要直接拷贝 GPL 项目（例如 EchoMusic）代码。

### 5.7 明确不做的技术路线

- 不改 `/system`、不替换预置应用、不申请系统签名。
- 不做 HEVC/AV1 软解（没有解码器，自己带 ffmpeg 会破坏“零三方依赖”且体积/性能不可控）。
- 不做 DRM。
- 不承诺系统锁屏播控（SystemUI 无 AVSession）。

---

## 6. 关键风险与缓解

| # | 风险 | 可能性 | 影响 | 缓解 |
| --- | --- | --- | --- | --- |
| 1 | 普通应用后台被挂起/杀 | 高 | 音乐后台断 | 必须 AVSession + `KEEP_BACKGROUND_RUNNING` + `audioPlayback`；M0 用普通签名包实测 30 分钟；暂停即停长时任务 |
| 2 | 音频焦点被通话/其他媒体抢占 | 中 | 播放中断/双声 | 处理 `audioInterrupt`；丢失时暂停；`InterruptHint` 允许时恢复；不要强行恢复 |
| 3 | HEVC/AV1 视频无法播放 | 高 | 用户大量视频打不开 | 白名单/黑名单；选文件时提示；文案明确“H.264/AAC”；不做假承诺 |
| 4 | 4K/10bit/HDR 卡顿/花屏 | 高 | 体验差/崩溃 | MVP 以 1080p 为目标；4K H.264 实测后再决定是否允许；10bit 直接提示 |
| 5 | `READ_MEDIA` + `mediaLibrary` 在普通应用不可用 | 中 | 无法全库扫描 | M0 第一项验证；失败切 picker 导入沙箱；接口层隔离 |
| 6 | `READ_IMAGEVIDEO`/`READ_AUDIO` 拿不到 | 高 | 不能全量读图库/音频 | 不申请；用 PhotoViewPicker/DocumentViewPicker；不要照抄 Photos 权限 |
| 7 | picker URI 不能持久化 | 高 | 重启后无法播放 | 复制到沙箱；或每次重选；不要依赖 `FILE_ACCESS_PERSIST` |
| 8 | 系统无播控中心/锁屏控制 | 高 | 需求“锁屏控制”无法满足 | 明确降级：应用内控制 + 长时任务通知；如必须锁屏控制，需要系统签名/定制 SystemUI，超出范围 |
| 9 | 大文件/长视频 seek 卡顿 | 中 | 拖动进度卡 | 用 fd + AVPlayer seek；测试 4 GB+/2 小时；必要时 `dataSrc` 分块；显示 loading |
| 10 | 横竖屏/全屏手势冲突 | 中 | 误操作/黑边 | 显式设置方向；全屏隐藏系统栏；退出恢复；三键导航下测试返回键 |
| 11 | 媒体库 API 废弃/未来移除 | 中 | 升级系统后失效 | Repository 接口隔离；picker/沙箱兜底 |
| 12 | 三方依赖/许可证 | 中 | 违反零依赖/合规 | 不用 ccplayer/cclyric；只用 Apache-2.0 代码并保留声明 |
| 13 | 通知权限/长时任务通知被用户删除 | 中 | 后台任务被停 | 按系统行为处理；暂停时停任务；提示用户不要删除通知 |
| 14 | 沙箱复制占空间 | 中 | 存储翻倍 | 优先 READ_MEDIA 引用播放；导入时提示占用；提供清理 |
| 15 | DRM 内容 | 低 | 无法播放 | 明确不支持；不接 MediaKeySystemService |

---

## 7. 里程碑与工时（单人，人日）

| 阶段 | 内容 | 产出/验收 | 工时 |
| --- | --- | --- | --- |
| **M0 验证** | 普通签名空壳/最小页面验证：① `READ_MEDIA` 列音频/视频并拿 fd；② `AudioViewPicker`/`DocumentViewPicker`/`PhotoViewPicker` 返回 URI 并 `fileIo.open`；③ AVSession + 长时任务退后台 30 分钟；④ 格式矩阵（MP3/AAC/M4A/FLAC/WAV/OGG/Opus/MP4 H.264/MKV H.264/TS H.264/MP4 HEVC/4K）；⑤ 音频焦点（来电/其他播放） | 一页验证报告 + go/no-go；确定媒体库默认实现 | 1 |
| **M1 工程骨架 + 媒体库** | Stage 工程、Tabs/路由、主题、`MediaRepository`、扫描/导入、元数据/封面/缩略图、空态/错误态 | 能列出/导入 100 首音频、50 个视频；搜索/排序可用 | 2.5 |
| **M2 音乐播放器** | AVPlayer 封装、队列/循环/随机、收藏、歌单、播放页、AVSession、长时任务、焦点、耳机拔出 | 后台 30 分钟不断；暂停/恢复/切歌/seek 正常；焦点丢失暂停 | 3 |
| **M3 视频播放器** | XComponent、播放/暂停/进度/倍速、全屏/横竖屏、手势、续播、错误提示 | 1080p H.264 连续 30 分钟；旋转/全屏/退出正常；HEVC 友好报错 | 3 |
| **M4 媒体中心整合** | 首页/最近播放/统一搜索、设置（扫描目录/清缓存）、性能（缩略图缓存/播放器释放）、视觉打磨 | 冷启动 < 2s；无 ANR/崩溃；页面切换不泄漏播放器 | 2 |
| **M5 设备测试与交付** | 格式矩阵回归、4K/大文件、后台/焦点/旋转、内存/功耗、文档/构建脚本 | 测试报告；可安装 HAP；已知问题清单 | 2 |
| **合计** |  |  | **13.5 人日**（建议按 15 排期） |

**MVP 可裁剪**：先做 M0 + M1（仅视频）+ M3，约 6.5 人日可交付“视频播放器”；音乐后台/歌单再迭代。若目标是“日常多媒体”，建议一次做 B。

**明天建工程的建议顺序**：

1. 建 Stage 工程（API 11，OpenHarmony，空权限）。
2. 先写 M0 验证页（一个页面 + 四个按钮：列媒体库、选文件、播放、后台测试），不要先做 UI。
3. M0 通过后再进 M1；M0 失败则直接切 picker 导入沙箱路线，不浪费时间。

---

## 8. 参考链接

### 官方文档（OpenHarmony 4.1-Release）

- Media Kit 简介 / 支持格式：<https://gitee.com/openharmony/docs/blob/OpenHarmony-4.1-Release/zh-cn/application-dev/media/media/media-kit-intro.md>
- AVPlayer 播放：<https://gitee.com/openharmony/docs/blob/OpenHarmony-4.1-Release/zh-cn/application-dev/media/media/using-avplayer-for-playback.md>
- AVSession 简介：<https://gitee.com/openharmony/docs/blob/OpenHarmony-4.1-Release/zh-cn/application-dev/media/avsession/avsession-overview.md>
- AVSession 开发：<https://gitee.com/openharmony/docs/blob/OpenHarmony-4.1-Release/zh-cn/application-dev/media/avsession/using-avsession-developer.md>
- 长时任务：<https://gitee.com/openharmony/docs/blob/OpenHarmony-4.1-Release/zh-cn/application-dev/task-management/continuous-task.md>
- 后台任务概述：<https://gitee.com/openharmony/docs/blob/OpenHarmony-4.1-Release/zh-cn/application-dev/task-management/background-task-overview.md>
- photoAccessHelper 开发准备：<https://gitee.com/openharmony/docs/blob/OpenHarmony-4.1-Release/zh-cn/application-dev/media/medialibrary/photoAccessHelper-preparation.md>
- photoAccessHelper 资源读取：<https://gitee.com/openharmony/docs/blob/OpenHarmony-4.1-Release/zh-cn/application-dev/media/medialibrary/photoAccessHelper-resource-guidelines.md>
- 文件选择器：<https://gitee.com/openharmony/docs/blob/OpenHarmony-4.1-Release/zh-cn/application-dev/reference/apis-core-file-kit/js-apis-file-picker.md>
- mediaLibrary API（已废弃但 4.1 仍在）：<https://gitee.com/openharmony/docs/blob/OpenHarmony-4.1-Release/zh-cn/application-dev/reference/apis-media-library-kit/js-apis-medialibrary.md>
- 普通应用权限：<https://gitee.com/openharmony/docs/blob/OpenHarmony-4.1-Release/zh-cn/application-dev/security/AccessToken/permissions-for-all.md>
- 系统应用权限：<https://gitee.com/openharmony/docs/blob/OpenHarmony-4.1-Release/zh-cn/application-dev/security/AccessToken/permissions-for-system-apps.md>

### 代码/样例

- OpenHarmony 应用样例（4.1）：<https://gitee.com/openharmony/applications_app_samples/tree/OpenHarmony-4.1-Release>
- VideoPlay 样例：<https://gitee.com/openharmony/applications_app_samples/tree/OpenHarmony-4.1-Release/code/BasicFeature/Media/VideoPlay>
- AVSession 样例（MediaController/MediaProvider/VideoPlayer）：<https://gitee.com/openharmony/applications_app_samples/tree/OpenHarmony-4.1-Release/code/BasicFeature/Media/AVSession>
- 图库（系统应用，含视频播放参考）：<https://gitee.com/openharmony/applications_photos/tree/OpenHarmony-4.1-Release>
- cclisten（音乐播放器，Apache-2.0）：<https://github.com/seagazer/cclisten>
- OpenHarmony-video-player（MIT，HarmonyOS API 10，参考价值低）：<https://github.com/QAQ-cmyk/OpenHarmony-video-player>

### 本机文档/脚本

- `docs/DEVICE.md`：设备版本、分区、已验证窗口 API、hdc 用法
- `docs/ENVIRONMENT.md`：hdc/SDK 路径
- `docs/REMOTE-BUILD.md`：Windows hdc + Linux 编译

---

## 9. 附录：本次实测命令与关键原始点

```powershell
$HDC="$DEVECO_HOME/sdk/default/openharmony/toolchains/hdc.exe"

# 设备
& $HDC shell "param get const.ohos.fullname; param get const.ohos.apiversion"
& $HDC shell "bm dump -a"

# 预置音乐播放器
& $HDC shell "bm dump -n ohos.samples.distributedmusicplayer"
& $HDC shell "aa start -b ohos.samples.distributedmusicplayer -a ohos.samples.distributedmusicplayer.MainAbility -m entry"
& $HDC shell "snapshot_display -f /data/local/tmp/music.jpeg"
& $HDC shell "hidumper -s AudioPolicyService -a '-p'"

# 媒体库/视频
& $HDC shell "mediatool list all"
& $HDC shell "mediatool send /system/etc/graphic/bootvideo.mp4"
& $HDC shell "aa start -b com.ohos.photos -a com.ohos.photos.MainAbility"

# 系统能力
& $HDC shell "hidumper -ls"
& $HDC shell "ls /system/lib64 | grep -i -E 'avplayer|avsession|avcodec|histreamer'"
& $HDC shell "ls /vendor/lib64 | grep -i -E 'codec|omx|hevc|h265'"
& $HDC shell "cat /system/etc/codec/codec_caps.xml"

# 权限/包
& $HDC shell "bm dump -n com.ohos.photos"
& $HDC shell "bm dump -n com.ohos.filepicker"
& $HDC shell "bm dump -n com.ohos.medialibrary.medialibrarydata"
```

关键原始点：

- 音乐 HAP：406,024 字节；`modules.abc` 126,700 字节；无 rawfile；字符串 `/system/etc/demo.wav`、`/system/etc/dynamic.wav`。
- 音乐播放：`dynamic.wav` 时长 68,372 ms（01:08）；AudioPolicy 流 `s16le 2ch 44100Hz RUNNING`。
- 视频：`bootvideo.mp4` 235,214 字节；MP4 box 为 `mp4v` + `mp4a`；Photos 可播放，音频流 RUNNING。
- 媒体库：`Audios` 表空；`Photos` 表 3 张 JPG + 1 个 MP4。
- codec_caps：音频 5 类解码；视频 4 类解码（H.264/H.263/MPEG-2/MPEG-4），无 HEVC/AV1。
- SystemUI 全部 8 个 HAP：`avsession` 字符串 0 次。
- 权限：`READ_MEDIA` normal/user_grant；`READ_IMAGEVIDEO`/`READ_AUDIO`/`FILE_ACCESS_PERSIST` system_basic/ACL。

> 说明：本文的“可用/不可用”以 2026-11-17 这台 LHT16 的镜像为准；系统 OTA 或厂商 BSP 变化后需重新跑 M0。

---

## 核实修正

- 3.4 视频表：官方 4.1 `media-kit-intro` 的 mp4 行明确列 **MPEG2、MPEG4**；原文“MPEG-4 Part 2 未重点列 / MPEG-2 未列”需修正（H.263 确实未列）。
- 3.3 / 4.1：`mediaLibrary` 的 URI“持久、无需复制文件”无官方依据；模块 `@deprecated since 9`，且依赖媒体库索引。应降级为“M0 验证，默认复制到沙箱”。
- 3.2：公开 SDK 的 AVSession 只有 provider 侧；全局 controller 按官方文档必须是系统应用，普通应用不能实现系统播控中心。
- 2.6.2：`AudioViewPicker` 官方措辞是“当前实际弹出 documentPicker 页面”，不是“audioPicker 在规划中”；行为结论不变。
- 补充：`READ_IMAGEVIDEO` / `READ_AUDIO` / `FILE_ACCESS_PERSIST` 的“普通应用不可用”是生产口径；调试 ACL 可声明，但不适合上架。Picker URI→`fs.openSync(READ_ONLY)`→fd→`AVPlayer.fdSrc` 可用，但不能把 URI 直接赋给 `AVPlayer.url`。
- 详细依据见 `docs/research/VERIFY-INSTALL-MEDIA.md`。
