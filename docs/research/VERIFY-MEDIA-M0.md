# 媒体 M0 实测（LHT16 / OpenHarmony 4.1.7.5 / API 11）

日期：2026-11-17  
工程：`D:\ohos-media`，bundle `com.local.media`（test-CA 普通应用）  
测试素材：ffmpeg 生成 5 s / 440 Hz 合成样本（320x240 视频），推到应用沙箱 `files/media` 后逐个播放 2 s。

## 1. 格式矩阵（AVPlayer + `fdSrc`）

| 文件 | 容器/编码 | 结果 | duration | 2 s 内 position | 备注 |
| --- | --- | --- | --- | --- | --- |
| tone.flac | FLAC | OK | 5000 ms | 1940 ms | |
| tone.m4a | AAC (m4a) | OK | 5000 ms | 1945 ms | |
| tone.mp3 | MP3 | OK | 5041 ms | 1951 ms | |
| tone.ogg | Vorbis (ogg) | OK | 5000 ms | 1945 ms | |
| tone.opus | Opus (ogg 容器) | OK | 5006 ms | 1943 ms | |
| tone.wav | PCM | OK | 5000 ms | 1940 ms | |
| tone_h264.mkv | H.264 + AAC (mkv) | OK | 5023 ms | 1946 ms | 需要 surfaceId |
| tone_h264.mp4 | H.264 + AAC | OK | 5000 ms | 1941 ms | 需要 surfaceId |
| tone_h264.ts | H.264 + AAC (ts) | OK | 5089 ms | 2721 ms | 需要 surfaceId |
| tone_hevc.mp4 | H.265/HEVC + AAC | 黑屏 | 5000 ms | 1942 ms | **320x240 小分辨率可播**，4K/10bit 未测 |

结论：API 11 上 **10/10 全部可播**；HEVC 不是“必然不支持”，小分辨率可用（具体是软解还是硬解未区分）。风险转移到 4K/HDR/10bit 与大码率，不是容器格式。

## 2. 后台播放（P0-9）

- 页面播放 `tone.mp3` 后：`avsession: created+activated tag=media-m0-audio`，`backgroundTaskManager: startBackgroundRunning OK mode=AUDIO_PLAYBACK`。
- 切到「笔记」应用后持续 98 s 采样：position 持续增长并按 5 s 循环重播，`state=playing bg=yes`，进程 `pidof com.local.media` 一直存活。
- 结论：**AVSession + `audioPlayback` 后，后台播放不会被 1 s 暂停**（此前无 AVSession 时实测约 1.1 s 被 PauseAudioStream）。30 分钟长稳仍需在 M1 联调时补测。

## 3. Picker（P0-7 / P0-8）

- `DocumentViewPicker` 能正常打开（“我的手机” → Download / Documents）。
- 但测试机这两个目录显示「0 项」：直接把 mp3 拷进 `/storage/media/100/local/files/Docs/{Documents,Download}` 并 chown 后仍不索引，说明 picker 依赖媒体库/文件管理索引，**本轮无法自动化选到文件**。
- 代码已实现 picker 多选 → fd 读取 → 复制到沙箱；**picker URI→fd 播放仍待人工验证**（用户可用文件管理/下载一个文件后手点一次）。
- READ_MEDIA + mediaLibrary 全库扫描未测（模块已废弃）。

## 4. 权限与工程

- `module.json5`：`ohos.permission.KEEP_BACKGROUND_RUNNING` + `backgroundModes: ["audioPlayback"]`；安装与运行无额外授权弹窗。
- 播放/暂停/seek 与视频 surface（`XComponent` + `surfaceId`）链路均工作。
- 每次 `hdc install -r` 会把默认输入法重置为 Kika，测试后已用脚本恢复 `com.local.homeime`。

## 5. 对 Phase 2 的影响

- M0 go：媒体中心可行；优先做 **音频播放器 + 视频全屏**，格式白名单直接按上表，HEVC 先提示“小分辨率可用、4K 未知”。
- M0 未闭环项：picker 真机选文件（需人工/文件管理造一个文件）、30 分钟后台长稳、4K/10bit HEVC、DRM（不做）。
- 下一步（M1/M2）：picklist 列表 + 导入复制 + 播放进度/后台恢复 + 通知播控（SystemUI 无 AVSession 播控，需自绘或等系统）。


## 修正（2026-11-17）：HEVC 黑屏根因

- M0 的 “HEVC OK” 只看了解码状态/进度，未核对画面，属误判。
- 复测：H264 320x240 正常出蓝帧；HEVC 320x240（hvc1、Main、8bit）进度到 5s 但 surface 全黑。
- 设备镜像 `/system/etc/codec/codec_caps.xml` 注册的视频解码器只有 `avdec_h264 / h263 / mpeg2video / mpeg4`，**没有 HEVC**；`/vendor/lib64`、`/system/lib64` 也搜不到 HEVC 解码库。
- 结论：**LHT16 系统镜像不支持 HEVC 解码**，应用层无法修复；AVPlayer 只播了音轨/走了时间轴。后续如需 HEVC，只能换带解码器的镜像或用软解方案。
