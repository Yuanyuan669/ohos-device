# 投屏与远程控制调研（LHT16 / OpenHarmony 4.1 / API 11）

日期：2026-11-17

## 结论

| 方向 | 可行性 | 说明 |
| --- | --- | --- |
| 设备画面投到电视（Miracast/AirPlay/Cast） | **不可行（第三方）** | 屏幕采集是系统权限；无 WFD/HDCP 组件 |
| DLNA 媒体推送（仅音视频 URL） | 可行（小工具） | 应用层 SSDP + HTTP，不需要采集屏 |
| PC 远程查看+控制本机 | **可行** | 走 hdc：`snapshot_display` 截图 + `uinput/uitest` 注入，root/debuggable 即可 |
| 设备端系统级投屏 App（开源方案） | 不适用 | 现有项目要 Full SDK/系统签名或 OH 5.0+ |

## 关键证据

- `CAPTURE_SCREEN` 权限：SDK 权限表里 `availableLevel = system_core`（system_grant），普通 test-CA 应用无法申请。
- API 11 公共 SDK 无 `@ohos.screenCapture` / `AVScreenCapture`；只有 `@ohos.screenLock`。
- 设备存在 `/bin/snapshot_display`、`/bin/uinput`、`/bin/uitest`，hdc shell 为 root。
- 快照性能（1080x2408 JPEG）：
  - 10 张设备内耗时 3.23s（约 3.1 fps），单张 87KB，`hdc file recv` 57ms → 含传输约 2.6 fps。
  - 540x1200 单张 30KB，5 张 1.91s（约 2.6 fps），缩小分辨率不提速（编码/管线开销为主）。
- 输入注入：`uitest uiInput tap/swipe/inputText` 已在自动化和本机控制中反复验证；`uinput` 支持 `-M` 鼠标、`-K` 键盘、`-T` 触摸。
- 无线：hdc 支持 TCP 模式（现有 `scripts/tcp-mode.sh`），可脱离 USB 远控。
- 硬件编码：`/vendor/lib64/libomx_avcenc_hw_sprd.z.so` 存在（H264 硬编），但公共 SDK 没有屏幕采集源，暂时用不上。

## 开源项目对比

| 项目 | 星 | 路线 | 对本机 |
| --- | --- | --- | --- |
| scrcpy | 大 | Android adb + 设备端 server | 不适用（adb/server 协议不同） |
| guoxiucai/ohos-scrcpy-app | 22 | 设备端**系统 HAP**（Full SDK、系统签名）+ Flutter 客户端 | ✗ 需要系统签名 |
| luodh0157/OpenHarmony_Scrcpy | 5 | OH **5.0+ root**，C-API 采集 server + Python 客户端 | ✗ 版本不满足 |
| taxiao213/hnscrcpy | 23 | HarmonyOS NEXT，H.264 + gRPC over hdc，JavaFX 客户端 | ✗ 面向 NEXT |
| snowlyg/ohscrcpy | 7 | Windows 工作台，HDC/ADB，内测 | 参考交互；未知 4.1 支持 |
| MiracleCast / uxplay | — | Linux Miracast / AirPlay 接收端 | 不能作为 OH 发送端 |

结论：现有开源方案大多依赖系统签名或 OH5+；本机可走“**PC 侧 hdc 客户端**”这条空档。

## 推荐项目：ohos-remote（PC 侧远程控制）

- 形态：Windows 桌面（Tauri/Python+Qt 均可），不做设备端 App、不申请系统权限。
- 功能：
  - hdc 设备发现（USB / `hdc tconn` 无线），多设备
  - 实时画面：`snapshot_display` 循环 + 本地 JPEG 解码显示（2~3 fps，可调分辨率/质量）
  - 鼠标/触摸/键盘注入：`uinput`（优先）或 `uitest uiInput`
  - 文件 push/pull、应用安装、shell、日志
  - 快捷操作：主页/返回/旋转/音量/电源（hdc 可用命令）
- 指标预期：延迟 300~500ms，2~3 fps，无音频；适合远程操作/演示，不适合看视频。
- 工作量：MVP 3~5 人日；后续若追求 30fps，需要 root 设备端 native server（display HDI 取帧 + H264 硬编 + hdc 端口转发），风险高且强绑定 OH 版本。

## 投屏方向建议

1. **Miracast/AirPlay/Cast：暂缓**。等系统签名/ROM 支持；否则只能做“DLNA 媒体推送”这种非镜像功能。
2. **DLNA 小工具（可选）**：本地媒体库选片 → SSDP 发现电视 → AVTransport 推送，工作量 2~3 人日，价值有限（TV 自带投屏通常已覆盖）。
3. 若拿到系统签名或厂商合作，再评估设备端采集 + 编码 + Miracast/WFD。

## 风险

- 依赖 root/debuggable；零售机可能没有 hdc root。
- 快照帧率低、无音频；不同 OH 版本 `uinput` 参数可能不同。
- hdc TCP 暴露调试权限，需要配对/防火墙提示。
