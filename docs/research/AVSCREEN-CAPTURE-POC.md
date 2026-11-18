# AVScreenCapture system_core PoC（2026-11-18）

## 结论

在这台 LHT16（OpenHarmony 4.1.7.5 / API 11，工程/root 设备）上，**不需要向厂商申请**：

1. 用一个独立的测试 bundle，把 profile 的 `apl` 改为 `system_core`、`app-feature` 改为 `hos_system_app`，用 SDK 自带的 OpenHarmony test PKI 重新签名；
2. `hdc install` 直接成功，`bm dump` 显示 `appPrivilegeLevel=system_core`、`isSystemApp=true`；
3. 声明 `ohos.permission.CAPTURE_SCREEN` 后自动获得（system_grant）；
4. 原生 AVScreenCapture 在 1080x2408 RGBA 下实测 **20.9~21.1 fps**（有持续动画时），远高于 `snapshot_display` 的 ~2 fps。

也就是说：**系统级抓屏这条路走通了**；剩下的是 H264 编码/推流实现，而不是权限。

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
| 编码流模式 | `dataType=OH_ENCODED_STREAM` + `videoSource=OH_VIDEO_SOURCE_SURFACE_ES` 时 `Init` 返回 2；暂未走通 |

结论：AVScreenCapture 是**按合成/脏区出帧**的，不是固定 60fps；静止画面帧率低是正常现象，连续动画/视频时约 21fps。

## 下一步（H264 推流）

1. 设备有 `libomx_avcenc_hw_sprd.z.so`（硬件 AVC 编码器），但 `codec_caps.xml` 只列了解码器；可通过 MediaCodec/AVCodec native API 创建 `video/avc` 编码器验证。
2. 直接用 RGBA NativeBuffer 喂硬件编码器（避免 CPU 转码），输出 H264 Annex-B / AVCC。
3. 通过 WebSocket 二进制帧推 NAL；客户端用 WebCodecs/TinyDecoder 解码；带宽约 2~8 Mbps。
4. 若 `OH_ENCODED_STREAM` 能走通则更省事，需要进一步确认 `videoSource`/buffer 布局；当前版本返回 2。

## 风险

- system_core + isSystemApp=true 的应用权限很大，仅限自用工程设备；不要分发。
- 该方案依赖设备信任 OpenHarmony test PKI；零售机/正式版可能拒绝。
- APL 升级后若再降回 normal，可能需要卸载重装。
