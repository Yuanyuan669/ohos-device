# AVScreenCapture system_core PoC（2026-11-18）

## 结论

在这台 LHT16（OpenHarmony 4.1.7.5 / API 11，工程/root 设备）上，**不需要向厂商申请**：

1. 用一个独立的测试 bundle，把 profile 的 `apl` 改为 `system_core`、`app-feature` 改为 `hos_system_app`，用 SDK 自带的 OpenHarmony test PKI 重新签名；
2. `hdc install` 直接成功，`bm dump` 显示 `appPrivilegeLevel=system_core`、`isSystemApp=true`；
3. 声明 `ohos.permission.CAPTURE_SCREEN` 后自动获得（system_grant）；
4. 原生 AVScreenCapture 在 1080x2408 RGBA 下实测 **20.9~21.1 fps**（有持续动画时），远高于 `snapshot_display` 的 ~2 fps。

5. H264 编码/推流也已跑通：x264 软编 540x1204，TCP 8766 推 Annex-B，PC ffmpeg 解码约 **20fps**。

也就是说：**系统级抓屏 + H264 推流这条路走通了**；剩下的是客户端/输入集成，而不是权限。

## PoC 工程

临时工程：`D:\ohos-screentest`（从 browser 复制，bundle `com.local.screentest`，compileSdk 11）。

- `entry/src/main/ets/pages/CapTest.ets`：启动/停止/统计 JSON，页面有 `LoadingProgress` 制造持续刷新。
- `entry/src/main/cpp/screencap.cpp`：NAPI 模块 `libscreencap.so`。
- `entry/src/main/cpp/CMakeLists.txt`：链接 `native_avscreen_capture`、`native_buffer`、`ace_napi.z`、`hilog_ndk.z`。

## 签名步骤（关键）

```bash
cd /d/ohos-screentest
export OHOS_BUNDLE=com.local.screentest
bash scripts/make-signing-material.sh
# 修改 signing/homekiosk-profile.json：
#   bundle-info.apl: normal -> system_core
#   bundle-info.app-feature: hos_normal_app -> hos_system_app
# 保持 app-distribution-type=os_integration、type=release、issuer=pki_internal
bash <重新 sign-profile 的脚本>
cp entry/build/default/outputs/default/entry-default-unsigned.hap build-artifacts/entry-unsigned.hap
bash scripts/sign.sh
hdc install -r build-artifacts/entry-signed.hap
```

验证：

```bash
hdc shell bm dump -n com.local.screentest
# appPrivilegeLevel: system_core
# isSystemApp: true
# reqPermissions: CAPTURE_SCREEN / MICROPHONE / INTERNET ...
```

注意：
- `sign-profile` 的 `-keyAlias "openharmony application profile release"` 带空格，建议写成 .sh 脚本执行；PowerShell 直接拼接参数容易把参数拆坏，报 `signAlg is required`。
- 不要拿主应用（homeime/browser）做实验；system_core 权限面很大，保持独立 bundle。

## 权限坑

- `CAPTURE_SCREEN`：system_grant，APL=system_core 后自动授予。
- `MICROPHONE`：即使调用 `OH_AVScreenCapture_SetMicrophoneEnabled(capture, false)`，`Init` 阶段服务端仍会检查麦克风权限（`InitAudioCap` → `CheckAudioCaptureMicPermission`）。因此必须声明并在运行时请求/授予 `ohos.permission.MICROPHONE`，否则 `Init` 返回 2（OPERATE_NOT_PERMIT）。
- 把 audioSampleRate 设为 0 会报 `set audioSampleRate is not support`；把 audioSource 设为 INVALID 会报 `audioSource source type error`。

## Native 调用顺序

```cpp
capture = OH_AVScreenCapture_Create();
OH_AVScreenCapture_SetCallback(capture, {onError, onAudio, onVideo});
OH_AVScreenCapture_SetMicrophoneEnabled(capture, false);
config.captureMode = OH_CAPTURE_HOME_SCREEN;
config.dataType = OH_ORIGINAL_STREAM;
config.audioInfo.micCapInfo = {48000, 2, OH_SOURCE_DEFAULT};
config.audioInfo.innerCapInfo = {48000, 2, OH_SOURCE_DEFAULT};
config.videoInfo.videoCapInfo = {0, nullptr, 0, 1080, 2408, OH_VIDEO_SOURCE_SURFACE_RGBA};
OH_AVScreenCapture_Init(capture, config);
OH_AVScreenCapture_StartScreenCapture(capture);
```

回调里：

```cpp
OH_NativeBuffer *buf = OH_AVScreenCapture_AcquireVideoBuffer(capture, &fence, &ts, &region);
OH_NativeBuffer_Config cfg; OH_NativeBuffer_GetConfig(buf, &cfg);
void *addr; OH_NativeBuffer_Map(buf, &addr);
// cfg.width/height/stride/format；实测 1080x2408 stride=4352 format=12（RGBA）
OH_NativeBuffer_Unmap(buf);
OH_AVScreenCapture_ReleaseVideoBuffer(capture);
```

## 实测数据

| 场景 | 结果 |
| --- | --- |
| 页面静态 | ~2.3 fps（只在 UI 脏区更新时出帧） |
| 页面有 `LoadingProgress` 动画 | **20.9~21.1 fps**，1080x2408，stride 4352，format 12 |
| `snapshot_display` 对照 | 400~450ms/帧，约 2.2 fps |
| 编码流模式 | `dataType=OH_ENCODED_STREAM` + `videoSource=OH_VIDEO_SOURCE_SURFACE_ES` 时 `Init` 返回 2；未走通 |

结论：AVScreenCapture 是**按合成/脏区出帧**的，不是固定 60fps；静止画面帧率低是正常现象，连续动画/视频时约 21fps。

## H264 推流（2026-11-18 已跑通）

### 硬件编码器不可用
- `codec_caps.xml` 只有 MPEG4 编码器（`avenc_mpeg4`），没有 H264 encoder。
- `OH_AVCodec_GetCapability("video/avc", true)` 返回 null；`OH_VideoEncoder_CreateByName()` 尝试 `OMX.sprd.h264.encoder` 等 7 个名字全部 null。
- 设备虽然有 `/vendor/lib64/libomx_avcenc_hw_sprd.z.so`，但它没有注册进 AVCodec/OMX 组件表，应用层拿不到。

### 软件 x264 方案
- 交叉编译 x264 静态库（`--target=aarch64-linux-ohos`），`ultrafast` + `zerolatency`，profile baseline，输入 I420，输出 Annex-B。
- 编码分辨率 **540x1204**（源 1080x2408 下采样），目标 2 Mbps。
- RGBA→I420 在采集回调里完成；x264 单线程/2 线程。

### 关键坑：stride
- `OH_NativeBuffer_Config.stride` 报 **4352**，但实际行宽是 **1080*4 = 4320**。
- 按 4352 读会让每行错位 8 像素，画面出现斜向条纹；必须用 `width*4` 作为 RGBA 行跨距。

### 实测
| 项目 | 结果 |
| --- | --- |
| 采集 | 1080x2408，20~21fps |
| 编码 | 540x1204 H264，16.7~21fps，约 1~2 Mbps |
| TCP 推流 | 端口 **8766**，Annex-B；PC 4.1s 收到 469KB |
| 解码验证 | ffmpeg 解码 65 帧/3.25s ≈ 20fps，画面正常 |

### 下一步
1. PC 客户端接 `tcp://<设备IP>:8766`，用 FFmpeg/PyAV 解码显示，替换现有 2fps `snapshot_display` 画面。
2. 接入 `uinput` 输入（现有 ohos-remote agent 已有），形成 20fps 远控。
3. 若要浏览器端：把 NAL 转 WebSocket + MSE/WebCodecs；或封装 fMP4。
4. 硬件 H264 编码器需要改 `codec_caps.xml`/注册 OMX 组件（ROM 级）后才可用；当前软编已满足 20fps。

## 风险

- system_core + isSystemApp=true 的应用权限很大，仅限自用工程设备；不要分发。
- 该方案依赖设备信任 OpenHarmony test PKI；零售机/正式版可能拒绝。
- APL 升级后若再降回 normal，可能需要卸载重装。
