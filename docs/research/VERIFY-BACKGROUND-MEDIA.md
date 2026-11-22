# 后台存活与 AVPlayer fd 播放实机验证（LHT16 / OpenHarmony 4.1.7.5 / API 11）

- 验证日期：2026-11-17
- 设备：LHT16（开发者手机），`const.ohos.fullname = OpenHarmony-4.1.7.5`，`const.ohos.apiversion = 11`
- 被测包：`com.local.spikebg`（由 `ohos-kiosk` 模板复制出的临时 spike，API 10 编译、普通调试签名）
- 目的：确认（1）前台 `TCPSocketServer` 监听 8080 是否可用；（2）`AVPlayer` 用 rawfile fd 是否可播；（3）切到其他应用后进程 / 端口 / 音频是否存活。
- hdc：`$OHOS_TOOLS/sdk/openharmony-4.0-Release/toolchains/hdc.exe`（设备在线，root shell）

## 0. 结论速览

| 问题 | 实测结果 |
| --- | --- |
| 前台 TCP 8080 能否监听 | **能**。`listen({address:'0.0.0.0',port:8080,family:1})` 立即成功；`netstat` 显示 `0.0.0.0:8080 LISTEN`。 |
| `getRawFd` + `AVPlayer.fdSrc` 能否播放 rawfile WAV | **能**。1 s / 8 kHz / 单声道 PCM WAV 正常播放，状态序列 `initialized → prepared → playing → completed → playing`。 |
| 切后台后进程是否被杀 / 挂起 | **未被杀、未被挂起**（至少 45 s）。pid 不变，JS `setInterval` 每 2 s 继续打印。 |
| 切后台后 8080 是否仍监听 | **仍监听**。T+15 s、T+45 s 两次 `netstat` 都是同一 pid 的 `LISTEN`。 |
| 切后台后音频是否仍 playing | **否**。`onBackground` 后约 1.1 s 系统 `PauseAudioStream`，AVPlayer 变为 `paused`（`time` 冻结 853 ms），**没有 `stopped`**；回前台后也**不自动恢复播放**。 |

## 1. Spike 构造

1. 复制模板（排除 `build/`、`build-artifacts/`、`signing/`、`watchdog-logs/`、`feed/`、`assets/`、`.git/`、`.hvigor/`）到临时目录 `opencode/spike-bg`。
2. `AppScope/app.json5` 的 `bundleName` 改为 `com.local.spikebg`。
3. 用 Python 生成 1 s、8 kHz、单声道、16 bit PCM（440 Hz 正弦）的 `entry/src/main/resources/rawfile/test.wav`（16044 B）。
4. `entry/src/main/ets/pages/Index.ets` 全量替换：`aboutToAppear` 里启动 TCP server 和 AVPlayer，页面用 `Scroll + Text` 显示时间戳日志；`setInterval(2000)` 打印 `player.state` 与 `currentTime` 作为存活心跳。
5. 签名：
   ```bash
   OHOS_BUNDLE=com.local.spikebg bash scripts/make-signing-material.sh
   OHOS_BUNDLE=com.local.spikebg bash scripts/build.sh
   OHOS_BUNDLE=com.local.spikebg bash scripts/sign.sh
   ```
6. 安装启动：
   ```powershell
   hdc install -r build-artifacts\entry-signed.hap
   hdc shell hilog -r
   hdc shell aa start -a EntryAbility -b com.local.spikebg
   ```

## 2. 步骤与观测

### 2.1 前台：监听 + 播放

启动后约 6 s 截图，页面日志：

```text
08:39:09  spike start
08:39:09  TCP listen OK 0.0.0.0:8080
08:39:09  rawfd fd=51 offset=1069360 length=16044
08:39:09  AVPlayer state=initialized
08:39:09  AVPlayer state=prepared
08:39:09  AVPlayer prepare OK
08:39:09  AVPlayer state=playing
08:39:09  AVPlayer play OK
08:39:10  AVPlayer state=completed
08:39:10  AVPlayer state=playing
08:39:10  AVPlayer replay OK
...
```

hilog（`hdc shell hilog -x | grep -E 'spikebg|AVPlayer'`）同步出现 `timeUpdate 115/216/.../1000`，说明确实在走解码时钟。

### 2.2 端口与 pid

```powershell
hdc shell "netstat -tlnp 2>/dev/null | grep 8080"
hdc shell pidof com.local.spikebg
```

```text
tcp        0      0 0.0.0.0:8080            0.0.0.0:*               LISTEN      2987/com.local.spikebg
2987
```

### 2.3 切后台（笔记）

```powershell
hdc shell aa start -a MainAbility -b com.ohos.note
```

- `08:39:24.989` `HomeKiosk: ability background`
- `08:39:25.594` `C02b12/AFWK: [PauseAudioStream : 584]PauseAudioStream SUCCESS, sessionId: 16`
- `08:39:26.126` `[spikebg] AVPlayer state=paused`

T+15 s：

```text
tcp        0      0 0.0.0.0:8080            0.0.0.0:*               LISTEN      2987/com.local.spikebg
2987
08:39:37.456  [spikebg] tick state=paused time=853
```

T+45 s：

```text
tcp        0      0 0.0.0.0:8080            0.0.0.0:*               LISTEN      2987/com.local.spikebg
2987
08:40:15.486  [spikebg] tick state=paused time=853
```

即：进程号未变、8080 未断、JS 定时器未停（说明应用进程没有被挂起/冻结），但 AVPlayer 停在 `paused`，`currentTime` 一直 853 ms，全程没有 `stopped`。

补充：`aa start` 把 spike 拉回前台后（`08:40:26.753 ability foreground`），心跳仍是 `tick state=paused time=853`，**系统不会自动恢复播放**。

### 2.4 两个 AVPlayer API 细节（踩坑记录）

1. **`fdSrc` 赋值是异步迁移到 `initialized`**：赋值后立刻 `prepare()` 会报
   `current state is not stopped or initialized, unsupport prepare operation`。
   正确做法是在 `stateChange == 'initialized'` 回调里再 `prepare()`，成功后 `play()`。
2. **不要在 `initialized` 之前设置 `loop`**：会触发
   `Operate Not Permit: current state is not prepared/playing/paused/completed, unsupport loop operation`。
   本次改为在 `state === 'completed'` 时再次 `play()` 实现循环。

## 3. 结论

1. **前台可监听**：API 10 编译的普通应用在 API 11 设备上 `TCPSocketServer.listen(0.0.0.0:8080)` 一次成功，root shell 可看到 `LISTEN` 与对应 pid。
2. **AVPlayer fd 可播**：`resourceManager.getRawFd()` 返回 `{fd, offset, length}` 可直接赋给 `fdSrc`，rawfile WAV 解码/播放正常；无需 `url` 或复制到沙箱。
3. **后台短时存活**：仅切到其他应用、未申请任何长时任务时，进程在 45 s 内未被杀也未被挂起，8080 持续监听，JS 定时器持续运行。
4. **后台音频会被系统暂停**：没有 AVSession + `audioPlayback` 长时任务时，切后台约 1 s 内 AVPlayer 被音频子系统暂停（`paused`，非 `stopped`）；回前台需业务代码显式 `play()`，否则一直停住。

## 4. 对方案的影响

- **文件传输（APP-FILETRANSFER）**：8080 服务在“切到其他应用”后至少 45 s 仍可用，PC 侧短连接/轮询是可行的；但不能据此承诺长时间后台常驻。长时间传输仍应申请长时任务（`dataTransfer`）或保持前台，并准备“进程被回收后端口消失”的探测与重连。
- **媒体中心（APP-MEDIA）**：rawfile / 沙箱 / picker fd 都能直接播，播放器实现无额外障碍。但“后台继续放音乐”必须按已验证的官方要求接 **AVSession + `audioPlayback` 长时任务**；否则系统会暂停音频（本 spike 已复现）。同时要在 `onForeground`/`audioInterrupt` 回调里显式恢复 `play()`。
- **“假在线”文案（Q7）**：端口存活与应用存活一致，可用 pid/端口探测作为在线判据；但熄屏、长时间（>45 s）与低内存回收尚未覆盖，阈值仍需更长的实测。
- **Q5**：本次只证明“未申请长时任务的普通包会被暂停”，30 分钟是否终止、假申请是否杀进程仍需专门验证。

## 5. 清理与恢复

```powershell
hdc uninstall com.local.spikebg
hdc shell aa start -a EntryAbility -b com.local.homeime
hdc shell uinput -T -c 540 2119      # 进入“选择输入法”，homeime 单选已选中
hdc shell "hidumper -s InputMethodService -a -a"
```

- 卸载结果：`uninstall bundle successfully.`；随后 `bm dump -n com.local.spikebg` 报
  `error: failed to get information and the parameters may be wrong.`，`pidof` 为空，8080 无监听。
- 输入法：`hidumper` 中 `com.local.homeime/ServiceExtAbility` 为 `"isCurrentIme": "true"`（另两个为 `false`），已恢复。
- 临时工程目录 `opencode/spike-bg` 在取完证据后删除；`ohos-kiosk`、`ohos-homeime`、`trading-master` 未做任何修改。
