# ohos-device

把硬开鸿 **LHT16**（展锐 UIS7885）开发板从 **OpenHarmony 4.1.7.5 / API 11** 往上推进，
打通**系统源码构建、镜像打包、OTA/刷机、备份回滚**这条链路。

应用开发/安装链路已经打通，代码和踩坑记录在 [`D:\ohos-kiosk`](https://github.com/Yuanyuan669/ohos-kiosk)；
本仓只管系统层。

## 现状（2026-11-15）

| 链路 | 状态 |
| --- | --- |
| 应用构建/签名/安装/启动 | 已打通（kiosk 仓，API 10 包在 API 11 设备上运行） |
| 设备连接/root/属性读取 | 已打通（hdc 1.3.0a / 3.2.0f 均可识别） |
| 分区/OTA 能力摸底 | 已完成（A/B 槽、`write_updater`、历史 OTA 608->613 成功） |
| 分区备份 | **未做**（脚本已就绪，第一次备份尚未执行） |
| 厂商新版本 OTA | **未知/缺包**（厂商升级服务存在，但是否有 API 12/26 包未知） |
| Linux 构建环境 | **本机缺**；优先用 8840U 32 GB 掌机（已装 Ubuntu），本机 WSL2 备选；安装脚本已就绪 |
| 厂商 BSP | **4.0 已公开**（`device/board/hys`、`device/soc/sprd`、`vendor/hys`、内核补丁）；**4.1/5.x/API 26 无公开分支** |
| 闭源文件 | **缺**（相机 ISP、GPU、GNSS、RIL、modem、PAC 的 `QogirN6Pro_CH.bin`/`sml-sign.bin`） |
| 签名链 / 刷机工具 | **缺**（工具文档已知，程序未在本机；OTA 验签要求厂商链） |
| 自建可启动固件 | **可编译 4.0/API 10**（补齐闭源文件后），但**低于设备当前 4.1/API 11**，不是升级 |

一句话：**能装应用，也能试着编 4.0 恢复包；但 API 26 仍卡在厂商新 BSP/OTA，公开源码只有 4.0。**

## 文档

- [docs/DEVICE.md](docs/DEVICE.md)：设备档案、分区表、OTA 历史、闭源固件兼容性判断
- [docs/ENVIRONMENT.md](docs/ENVIRONMENT.md)：本机已有工具、缺项清单、WSL/双系统选择
- [docs/FIRMWARE.md](docs/FIRMWARE.md)：系统构建/OTA/刷机/备份的可行路径、厂商询问模板、风险
- [docs/VENDOR-BUILD.md](docs/VENDOR-BUILD.md)：厂商 4.0 源码编译步骤、闭源文件清单、PAC 烧录
- [docs/REMOTE-BUILD.md](docs/REMOTE-BUILD.md)：用 8840U 32 GB 掌机做 Linux 构建机（SSH/SCP/性能）
- [docs/LOCAL-FILES.md](docs/LOCAL-FILES.md)：固件/OTA/工具/闭源文件放哪（全部不入库）
- kiosk 仓：`docs/TOOLCHAIN-NOTES.md`、`docs/PITFALLS.md`（应用侧工具链与上板踩坑）

## 快速检查

```powershell
powershell -ExecutionPolicy Bypass -File scripts/doctor.ps1
```

会检查：hdc、设备属性、SDK/hvigor/JDK、WSL/Docker/repo、磁盘/内存、厂商 BSP/OTA 文件是否存在，
并打印还缺什么。

## Linux 构建环境（优先掌机，WSL2 备选）

有 8840U 32 GB 掌机的话，优先用它编译：内存/磁盘都比本机充裕，Windows 继续负责 hdc 和烧录。
步骤见 [docs/REMOTE-BUILD.md](docs/REMOTE-BUILD.md)；先在掌机跑 `scripts/host-check.sh`。

没有掌机时用本机 WSL2：

```powershell
# 管理员 PowerShell；会启用 WSL2/虚拟机平台，可能要求重启
powershell -ExecutionPolicy Bypass -File scripts/setup-wsl.ps1

# 重启后，在 WSL 里装依赖、repo，并同步 4.0 源码（可选 --sync）
wsl -d Ubuntu-20.04 -u root bash /mnt/d/ohos-device/scripts/setup-ubuntu.sh --sync
```

三种方案（掌机/WSL2/双系统）的取舍见 [docs/ENVIRONMENT.md](docs/ENVIRONMENT.md) 3.2.1。

## 第一次备份

```powershell
powershell -ExecutionPolicy Bypass -File scripts/backup-device.ps1 -OutDir D:\ohos-backup\LHT16-20261115
```

只读备份 boot 链、NV/校准、system/vendor/product 等；默认不备份 112 GB 的 `userdata`。
脚本会生成 `SHA256SUMS.txt` 和 `manifest.txt`。

## 安全规则

- **未完成分区备份前不刷机。**
- 不写 `system` / `vendor` / `boot` / `uboot` / `trustos` / NV 分区；设备上只做只读操作。
- 不混用其他开发板/其他厂商的镜像、OTA 包、BSP。
- 固件、OTA 包、签名材料、完整序列号/MAC/IP、闭源 blobs 不入库。
- 刷机/升级期间保持供电和连接，不拔线、不断电。

## 目录

```text
docs/       设备、环境、固件路线、厂商编译文档
scripts/    doctor / backup / WSL 安装 / Ubuntu 依赖 / 闭源文件检查
```

源码树不放在本仓：按厂商 manifest 同步到 WSL 的 `~/ohos`。本仓只记录流程、工具和校验脚本。
