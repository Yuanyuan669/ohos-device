# docs/research 索引

LHT16（OpenHarmony-4.1.7.5 / API 11）四个应用方向的调研与核实报告。总路线图见 [`../APP-ROADMAP.md`](../APP-ROADMAP.md)。

## 一句话索引

| 文档 | 一句话 |
| --- | --- |
| [APP-BROWSER.md](APP-BROWSER.md) | 预置 `com.ohos.nweb` 只是引擎载体、`ohos.samples.browser1` 不能被外部调用，结论是新写零依赖 ArkWeb 壳，约 12.5 人日，单标签约 356 MiB。 |
| [APP-FILETRANSFER.md](APP-FILETRANSFER.md) | 预置 miniserve 是 root+全 `/data`+无鉴权的危险外壳；推荐手机内 `TCPSocketServer`（8080）+PC 浏览器，约 7~9 人日、MVP 3.5~4.5，hdc 脚本兜底。 |
| [APP-MEDIA.md](APP-MEDIA.md) | 预置音乐播放器只播两个系统 WAV、图库不可复用；推荐自建媒体中心（AVPlayer+AVSession+长时任务），约 13.5 人日，设备无 HEVC/AV1。 |
| [APP-APPCENTER.md](APP-APPCENTER.md) | 普通应用无法安装 HAP（`INSTALL_BUNDLE` 为 `system_core`/`@systemapi`），推荐设备端下载校验+PC `hdc-agent` 安装，约 12.5~15 天、MVP 8.5~10。 |
| [VERIFY-BROWSER-TRANSFER.md](VERIFY-BROWSER-TRANSFER.md) | 逐条核实浏览器/传输结论：`@kit.ArkWeb`、incognito、下载续传、`TCPSocketServer` 无 `bind`、后台任务语义等 12 项修正。 |
| [VERIFY-INSTALL-MEDIA.md](VERIFY-INSTALL-MEDIA.md) | 逐条核实安装/媒体结论：`INSTALL_BUNDLE` 起始版本为 7、无 install action、picker URI 只读不可持久化、官方格式表修正。 |

## 阅读顺序

1. `APP-FILETRANSFER.md` → `APP-MEDIA.md` → `APP-BROWSER.md` → `APP-APPCENTER.md`（按依赖从低到高）
2. 每读完一份，立即读对应的核实报告（前两份读 `VERIFY-BROWSER-TRANSFER.md`，后两份读 `VERIFY-INSTALL-MEDIA.md`），以核实结论覆盖正文。
3. 最后读各文档末尾的 `## Spike 实测` 与 `## 核实修正`（设备侧证据优先级最高）。
4. 汇总成果见 `../APP-ROADMAP.md`：结论速览、共同组件、Phase 0~4、风险表、Q1~Q12、不做的事、被推翻的判断清单。
