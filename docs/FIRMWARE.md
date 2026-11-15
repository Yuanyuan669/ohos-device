# 系统构建、升级与固件包：可行路径与前置条件

这篇只讨论"怎么把 LHT16 从 API 11 往上走"，以及为什么纯社区源码不能直接刷。
设备事实见 [DEVICE.md](DEVICE.md)，本机缺项见 [ENVIRONMENT.md](ENVIRONMENT.md)。

## 一、结论

1. **首选厂商 OTA**。设备已经成功执行过 `updater_608-613.zip`，`write_updater`、A/B 槽、
   updater 分区都在；只要厂商给出目标版本的签名 OTA 包，这条路风险最低、工作量最小。
2. **厂商 4.0 BSP 已在 Gitee 公开**。`device/board/hys`、`device/soc/sprd`、`vendor/hys`、
   `kernel/linux/patches` 和厂商 fork 都能同步；产品名 `laphone`，可编译出
   `laphone_nosec_userdebug.pac`。但**公开分支只有 4.0/API 10**，低于设备当前的 4.1.7.5/API 11。
3. **闭源文件仍是硬前提**。相机 ISP、GPU、GNSS、RIL、modem bin/lib、`QogirN6Pro_CH.bin`、
   `sml-sign.bin` 等不在公开仓库；缺这些编译会失败或系统跑不起来。
4. **只换 system、保留旧 vendor 的混搭不可取**。大版本之间 HAL/HDF 接口、内核模块 ABI、
   SELinux 策略都可能不匹配，轻则相机/ modem/音频失效，重则不开机。
5. **闭源固件不是"永久兼容"的**。它支不支持升级，取决于厂商是否为 LHT16 出了对应版本的
   vendor 镜像/OTA。社区 API 到 26 不等于这块板能到 26。

编译/烧录的具体命令、闭源文件清单和 PAC 说明见 [VENDOR-BUILD.md](VENDOR-BUILD.md)。

## 二、一台 OpenHarmony 设备是怎么"拼"出来的

一个可启动的系统至少包含四层，缺一层都不行：

| 层 | 典型内容 | 在这台设备上的位置 |
| --- | --- | --- |
| 引导/安全 | uboot、sml、trustos、teecfg、dtb/dtbo、boot/vendor_boot | `uboot_*`、`sml_*`、`trustos_*`、`teecfg_*`、`dtb_*`、`dtbo_*`、`boot_*`、`vendor_boot_*` |
| 内核/驱动 | Linux 5.15.74 + 厂商补丁；`mali_kbase.ko`、音频 DSP、触摸、NPU、摄像头等 | `boot_*` / `vendor_boot_*` / `vendor/modules` / `odmko_*` |
| 系统用户态 | OpenHarmony framework、ArkUI、系统应用、HDF host | `system`（挂 `/`）、`product`、`sys_prod` |
| 厂商适配 | HAL 实现、闭源库、firmware、NV/校准 | `vendor`、`/vendor/lib64`、`/vendor/firmware`、`prodnv`、`nr_*`、`persist` |

源码构建对应的是"系统用户态 + 内核 + 引导"的重新组合；但**厂商适配层**通常以预编译 blobs
或独立仓库提供，不在 OpenHarmony 主仓里。

### 2.1 OpenHarmony 源码里需要哪些厂商内容

本板的实际仓库（公开 manifest `develop-phone-open-source/manifest`，分支
`OpenHarmony-4.0-Release`）：

```text
device/board/hys/laphone/          # 板级配置、PAC 打包、预编译 boot/kernel/dtb
device/soc/sprd/uis7885/           # SoC 配置、GPU/相机/GNSS/RIL 等预编译库
vendor/hys/laphone/                # 产品配置、HAL、modem、相机、RIL、闭源库
kernel/linux/patches/              # 内核补丁
```

产品配置是 `vendor/hys/laphone/config.json`，产品名 `laphone`；`device_board_hys/laphone/pac/`
下有 `uis7885_pac.sh`、`make_boot.sh`、`Script/mkpac.pl` 和 `ImageFiles/flash.cfg`。

编译入口一般是：

```bash
./build.sh --product-name <product> --ccache
```

产物通常在 `out/<product>/packages/phone/images/`，再按厂商的打包/签名流程生成刷机包或
OTA zip。具体 target 名、打包脚本、签名命令必须以目标版本和厂商 BSP 的文档为准；
本仓不会凭空写一套"看起来能跑"的命令。

### 2.2 构建宿主

OpenHarmony 官方构建链以 Linux 为主，典型要求：

- Ubuntu 20.04/22.04（WSL2 可用，但要注意内存和 I/O）
- 16 GB 内存起步，32 GB 更稳；本机 15.1 GB 偏紧
- 100 GB+ 磁盘（源码 + 预编译 + 产物）；本机 D 盘 1.29 TB 足够
- Python 3.8+、Node 14/16/18（随版本）、`repo`、git-lfs、build-essential、zip/unzip 等

本机当前没有 WSL2/Ubuntu、没有 `repo`、没有源码树；这些是"能补"的缺项，
但补完之后仍然缺厂商 BSP。

## 三、闭源固件的兼容性

### 3.1 哪些是闭源的

从设备上能直接看到的：

- `/vendor/modules`：`mali_kbase.ko`、`audio-*.ko`、`agdsp_pd.ko`、`npu_img_vha.ko`、
  `chipone_icn9922c_ts.ko`、`snd-soc-sprd-card.ko` 等
- `/vendor/firmware`：`gnssmodem.bin`、`wcnmodem.bin`、`novatek_ts_fw.bin`、摄像头 sensor 配置等
- `/vendor/lib64`：`libsprd7885_ril_adapter_1.0.z.so`、OMX/audio/camera 等厂商库
- 分区：`uboot_*`、`sml_*`、`trustos_*`、`teecfg_*`、`odmko_*`、`prodnv`、`nr_*`、`persist`、`socko_b`

这些都没有对应的开源实现；即使有内核源码，缺少 blobs 也无法恢复 modem、相机、GPU、DSP 等功能。

### 3.2 为什么不能"只升 system"

- **内核模块 ABI**：`*.ko` 与内核版本/配置（vermagic）绑定；新 system 配旧 kernel 可能加载失败。
- **HDF/HAL 接口**：OpenHarmony 大版本会改 HDF 设备模型、Audio/Camera/Display HAL 接口；
  旧 vendor 库可能找不到符号或行为不兼容。
- **SELinux/init**：新 system 的 policy 和 init 配置可能拒绝旧 vendor 服务。
- **分区布局**：`system`、`vendor`、`product`、`sys_prod` 的职责和挂载方式随版本变化。
- **OTA 签名**：updater 校验 PKCS#7 签名；没有厂商密钥，自打包会被拒。

### 3.3 闭源固件"支不支持升级"怎么判断

不要看社区版本号，直接问厂商这三个问题：

1. LHT16 是否有 **目标 OpenHarmony 版本** 的完整 BSP（含 vendor/内核/blobs）？
2. 该版本是否提供 **已签名 OTA 包或完整刷机包**？
3. 升级后 **modem/NV/相机/显示/音频** 是否仍由厂商保证？

如果答案都是"没有"，那这块板在受支持路径上就到不了 API 26；剩下的是移植/逆向，
成本和风险都远高于换一块受支持的开发板。

## 四、OTA 机制（这台设备已证明可用）

### 4.1 设备侧

```bash
# 写入升级命令并重启进 updater（路径是示例）
write_updater updater /data/updater/updater.zip

# SD 卡升级
write_updater sdcard_update

# 清除升级命令
write_updater clear
```

历史结果文件 `/data/updater/updater_result`：

```text
/data/update/ota_package/firmware/versions/updater_608-613.zip|pass||install_time=65.92|update_bi|update_bi|
```

说明 608 -> 613 的 OTA 曾成功；`update_bi` 是 A/B 升级标记。

### 4.2 包校验

`libupdateservice.z.so` 中的字符串表明升级包会做：

- zip 结构检查（EOCD、local header、data descriptor）
- PKCS#7 签名校验（`Verify zpkcs7 signature failed`）
- SHA256 摘要校验（`calc pkg sha256 digest failed`）

因此：

- **不要手改厂商 OTA zip**，签名会失效。
- **不要用别的板子的 OTA 包**，即使 SoC 相同，分区/签名/board id 也可能不同。
- 如果厂商提供的是完整刷机包（不是 OTA zip），按厂商工具和流程走，不要自己拼。

### 4.3 厂商 OTA 服务

设备参数里有：

```text
update.serverip.search = honglve.superred.com.cn
update.server.port = 16895
```

从本机可解析并连通该端口，但**没有拿到任何升级包**。这只能说明"厂商有升级服务"，
不能说明"服务上有 API 26 的 LHT16 包"。不要对生产服务做扫描/猜接口；直接问厂商要包。

## 五、推荐路线

### 路线 A：厂商 OTA（首选）

适用：厂商有目标版本的签名 OTA 包。

步骤：

1. 备份当前分区（见第六节）。
2. 向厂商确认包对应的型号、当前基线版本、目标版本、是否支持回滚。
3. 把包放到设备可读位置，按厂商说明执行 `write_updater` 或系统设置里的升级入口。
4. 升级后核对：`const.ohos.fullname`、`const.ohos.apiversion`、`const.product.oharm.version`、
   内核版本、modem/相机/显示/音频是否正常。
5. 保留原厂包和备份，确认可回滚后再长期使用。

### 路线 B：厂商 BSP + 自建（重）

适用：厂商提供完整 BSP 和签名工具，且你愿意维护一套 Linux 构建环境。

步骤：

1. 装 WSL2 + Ubuntu 22.04，配置内存/磁盘；安装 `repo` 和依赖。
2. 按目标版本 `repo init/sync` OpenHarmony 源码。
3. 叠加厂商 BSP：`device/`、`vendor/`、内核、HDF、blobs、产品配置。
4. 编译、打包、签名；先在备份好的设备上验证 boot/system/vendor 配套。
5. 通过厂商刷机工具写入；保留回滚路径。

这条路线的工作量主要在"拿到 BSP 并让它和社区源码版本对齐"，不在敲 `build.sh`。

### 路线 C：纯社区源码直接刷（不建议）

缺 UIS7885 device 适配、缺闭源 blobs、缺签名链。即使强行写入，也可能：

- 不开机（内核/DTB/分区不匹配）
- 开机但 modem/NV 丢失、相机/音频/GPU 不可用
- 无法回滚（anti-rollback 或签名拒绝）

不建议在这块唯一的板子上做这个实验。

## 六、刷机前备份

### 6.1 备份什么

至少：

- 引导/安全：`uboot_a/b`、`sml_a/b`、`trustos_a/b`、`teecfg_a/b`、`boot_a/b`、`vendor_boot_a/b`、
  `vendor_boot_updater_a/b`、`dtb_a/b`、`dtbo_a/b`、`misc`、`miscdata`
- 设备唯一数据：`prodnv`、`nr_fixnv1_a/b`、`nr_fixnv2_a/b`、`nr_modem_a/b`、`nr_phy_a/b`、
  `nr_deltanv_a/b`、`nr_runtimenv1/2`、`persist`、`calinv`
- 系统：`system`、`vendor`、`product`、`sys_prod`、`updater_a/b`、`odmko_a/b`、`l_agdsp_a/b`、
  `pm_sys_a/b`、`ch_sys_a/b`、`ise_a/b`、`isedata`
- 可选：`blackbox`、`sysdumpdb`、`logo`、`fbootlogo`、`uboot_log`、`socko_b`

`userdata` 112 GB 不建议整盘备份；按应用数据单独打包（kiosk 仓 `DEVICE.md` 有 tar 示例）。

### 6.2 怎么备份

本仓提供只读脚本：

```powershell
powershell -ExecutionPolicy Bypass -File scripts/backup-device.ps1 -OutDir D:\ohos-backup\LHT16-20261115
```

脚本会：

1. 检查设备、`/data` 空间和 PC 空间；
2. 用 `dd` 把选定分区读到 `/data/local/tmp/ohos-backup/`；
3. 拉回 PC，计算 SHA256；
4. 生成 `manifest.txt` / `SHA256SUMS.txt`，并记录当前 `param` 和 slot；
5. 删除设备侧临时文件。

**注意**：脚本只读分区，不写任何分区；但 `dd` 读取期间不要拔线、不要断电。

### 6.3 恢复

恢复比备份危险得多，必须用厂商工具/流程。不要用 `dd` 直接回写 boot/uboot/trustos，
除非厂商明确确认分区布局和签名要求。至少先确认：

- 当前 slot 和 `misc` 命令；
- 回写后 bootloader 是否验签；
- 回写顺序和断电风险。

## 七、给厂商的询问模板

```text
主题：LHT16（UIS7885）OpenHarmony 升级 / BSP / 刷机包咨询

你好，

我有一台硬开鸿 LHT16 开发者手机，当前信息：
- 型号：LHT16
- OpenHarmony：OpenHarmony-4.1.7.5 / API 11
- 厂商版本：OHarm OS 2.0，产品版本 2.0.613
- 内核：Linux 5.15.74-ab19 aarch64
- 设备曾通过 OTA 从 608 升级到 613（updater_608-613.zip）

想确认以下问题：
1. LHT16 是否有更高 OpenHarmony 版本（如 API 12/26）的已签名 OTA 包或完整刷机包？
2. 如有，是否提供对应版本的 BSP（device/vendor、内核、HDF、闭源 blobs）？
3. 自编译镜像需要什么签名工具/密钥？bootloader 是否解锁？
4. 推荐使用哪种刷机/救砖工具（SPD ResearchDownload / UDownload / fastboot）？
5. 升级后 modem/NV、相机、显示、音频是否仍受支持？是否支持回滚？
6. 能否提供原厂完整包、分区表和救砖流程？

如果目前没有新版本，也请告知 LHT16 的受支持版本上限和后续计划。

谢谢。
```

## 八、风险清单

| 风险 | 影响 | 缓解 |
| --- | --- | --- |
| 刷错包/混用其他板包 | 不开机、变砖 | 只用厂商给 LHT16 的包 |
| 丢 NV/校准 | modem/信号/射频异常 | 先备份 `prodnv`、`nr_*`、`persist` |
| 签名校验失败 | 升级被拒 | 用厂商签名包；不要手改 zip |
| anti-rollback | 无法降回旧版本 | 升级前问清策略，保留原厂包 |
| 断电/拔线 | 分区写坏 | 升级/备份期间保持供电和连接 |
| 只换 system | HAL/内核不匹配 | 不混搭大版本；用配套 vendor/boot |
| 内存不足 | 构建 OOM | WSL 限制内存 + swap，降低并发；必要时上 32 GB 或远程构建 |
