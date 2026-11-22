# 设备档案：硬开鸿 开发者手机（LHT16）

这份文档记录"板子到底是什么状态"，避免每次重新猜版本、重新踩同一批属性名和路径的坑。

数值是 2026-11-15 在本机用 `hdc shell param get ...` 现读的，不是抄官网。公开仓库里已把序列号、MAC、局域网 IP 脱敏；本地需要时用 `hdc list targets` / `ip addr` 现读。

## 一、身份与系统版本

| 项 | 值 | 备注 |
| --- | --- | --- |
| 型号 | LHT16 | `const.product.model` |
| 产品名 | 开发者手机 | `const.product.name` |
| OpenHarmony | OpenHarmony-4.1.7.5 | `const.ohos.fullname` |
| API Level | 11 | `const.ohos.apiversion` |
| 发布类型 | Release | `const.ohos.releasetype` |
| 厂商系统版本 | OHarm OS 2.0 | `const.product.software.version` |
| 厂商产品版本 | 2.0.613 | `const.product.oharm.version`；设置里显示的版本号 |
| ArkCompiler | 11.0.2.0 | `const.ark.version` |
| 安全补丁 | 2024/04/01 | `const.ohos.version.security_patch` |
| ABI | arm64-v8a | `const.product.cpu.abilist` |
| 厂商字段 | `const.product.manufacturer = laval.csdn.net` | 镜像里就这么写的，照录 |
| 序列号 | `<SERIAL>` | 本地用 `hdc list targets` 读取 |
| 设备 UDID | 不记录 | `const.product.devUdid`，不入库 |

注意：网上/包装文档写的是"出厂 OpenHarmony 4.0"，实际到手镜像已经是 4.1.7.5 / API 11。kiosk 工程的 `compatibleSdkVersion` 仍写 10，API 10 的包在 API 11 上向下兼容，实测可装可跑。

## 二、硬件

| 项 | 值 |
| --- | --- |
| SoC | 展锐 P7885（UIS7885，5G） |
| 内存 | 8 GB（`/proc/meminfo` total 7502556 kB） |
| 存储 | 128 GB；`/data` 112 GB，已用约 6.4 GB |
| 屏幕 | 6.58" FHD；RenderService 报 1080x2408 @60Hz（竖屏物理方向） |
| 无线 | wlan0，MAC `<MAC>`，DHCP 地址 `<DEVICE_IP>/24` |
| 内核 | Linux 5.15.74-ab19 aarch64，构建于 2024-06-25 |
| 根分区 | `/` 为 ext4 只读；shell 虽是 uid=0，也别假设系统可写 |

## 三、开发与调试状态

- 开发者模式已开，USB 调试已开（设置 -> 关于本机 -> 连点版本号 -> 开发者选项）。
- `hdc list targets` 能列出序列号；两台 hdc 客户端都能识别这块板子：
  - SDK 4.0 自带 hdc：`$OHOS_TOOLS/sdk/openharmony/toolchains/hdc.exe`，Ver 1.3.0a
  - DevEco 26 自带 hdc：`$DEVECO_HOME/sdk/default/openharmony/toolchains/hdc.exe`，Ver 3.2.0f
- shell 身份是 root；除 `/data` 与沙箱外大多只读。
- 系统里没有 `getprop` / `getparam` / `curl` / `wget`，取属性用 `param get <key>`。
- `const.debuggable = 1`、`const.secure = 0`，内核 cmdline 里 `androidboot.selinux=permissive`。
  这说明当前是工程/调试型镜像，但不能据此推断 bootloader 一定接受未签名镜像。

## 四、常用命令

```bash
# 读版本/属性
T=$(hdc list targets | head -n 1)
HDC=/d/ohos-tools/sdk/openharmony/toolchains/hdc.exe
"$HDC" -t "$T" shell "param get const.ohos.fullname"
"$HDC" -t "$T" shell "param get const.ohos.apiversion"
"$HDC" -t "$T" shell "param get const.product.software.version"

# 安装/卸载/启动
MSYS_NO_PATHCONV=1 "$HDC" -t "$T" install -r build-artifacts/entry-signed.hap
"$HDC" -t "$T" shell "aa start -a EntryAbility -b com.local.homekiosk"
"$HDC" -t "$T" shell "pidof com.local.homekiosk"
"$HDC" -t "$T" uninstall com.local.homekiosk

# 截图（Git Bash 必须关路径转换）
"$HDC" -t "$T" shell "snapshot_display -f /data/local/tmp/s.jpeg"
MSYS_NO_PATHCONV=1 "$HDC" -t "$T" file recv /data/local/tmp/s.jpeg "$(cygpath -w /tmp/s.jpeg)"

# 日志
"$HDC" -t "$T" shell "hilog -x -T HomeKiosk | tail -n 40"
```

免线调试、推照片等细节见 kiosk 仓的 `docs/TOOLCHAIN-NOTES.md`、`docs/PITFALLS.md` 和 `scripts/`。

## 五、这台设备上已经验证过的

- API 10 的应用包可以安装、启动，`pidof` 能拿到进程号。
- 四个窗口相关 API 均返回成功：`setPreferredOrientation(landscape)`、`setWindowLayoutFullScreen`、
  `setWindowSystemBarEnable([])`、`setWindowKeepScreenOn(true)`。
- 截图 2408x1080 横屏，时钟/日期/天气/照片/信息源/备忘卡片正常渲染。
- 天气：主源 open-meteo 在当前网络被出口 reset，自动切 wttr.in 后拿到实时温度。
- 照片：两张示例 PNG 写入应用沙箱后能轮播。
- 应用信息：bundleName `com.local.homekiosk`，versionName 1.0.0，versionCode 1000000。
  沙箱根：`/data/app/el2/100/base/com.local.homekiosk/`
  照片目录：`/data/app/el2/100/base/com.local.homekiosk/haps/entry/files/photos`
  属主：`20010025:20010025`（root 直写文件后必须 chown 成这个属主，否则应用读不到）。

## 六、已知设备侧现象（不是应用的问题）

- `/data/log/faultlog/faultlogger` 里有别的应用留下的崩溃记录：
  `jscrash-com.minkiapps.ets.news`、`appfreeze-com.wathinst.ohbili`，与本工程无关。
- `route -n` 只显示直连路由，看不到默认网关，但设备实际能出网（策略路由）。
- 属性表很精简，缺项就用 `param get <key>` 试。

## 七、分区与启动槽（2026-11-15 实测）

设备是 UFS（`/dev/block/sda`，119.2 GiB，逻辑/物理扇区 4096），带 A/B 启动槽，当前 `sprdboot.slot_suffix=_a`。

关键分区（`sgdisk -p /dev/block/sda`）：

| 分区 | 大小 | 说明 |
| --- | --- | --- |
| `system` | 2.9 GiB | 单份，不是 A/B；挂载到 `/`（`/usr`） |
| `vendor` | 800 MiB | 单份；闭源 HAL、内核模块、firmware 都在这里 |
| `product` | 800 MiB | 单份 |
| `sys_prod` | 100 MiB | 单份 |
| `boot_a` / `boot_b` | 64 MiB ×2 | A/B |
| `vendor_boot_a` / `vendor_boot_b` | 100 MiB ×2 | A/B |
| `vendor_boot_updater_a` / `_b` | 20 MiB ×2 | updater 模式启动用 |
| `updater_a` / `updater_b` | 64 MiB ×2 | updater 镜像 |
| `dtb_a` / `dtb_b` | 8 MiB ×2 | A/B |
| `dtbo_a` / `dtbo_b` | 8 MiB ×2 | A/B |
| `uboot_a` / `uboot_b` | 3 MiB ×2 | 引导 |
| `trustos_a` / `trustos_b` | 6 MiB ×2 | TEE |
| `sml_a` / `sml_b` | 1 MiB ×2 | 安全监控 |
| `teecfg_a` / `teecfg_b` | 1 MiB ×2 | TEE 配置 |
| `misc` | 4 MiB | 启动/升级命令 |
| `miscdata` | 1 MiB | 杂项数据 |
| `persist` | 2 MiB | 持久化 |
| `prodnv` | 64 MiB | 产品/NV 校准，刷机时必须备份 |
| `nr_fixnv1_a/b`、`nr_fixnv2_a/b` | 50 MiB ×4 | 射频 NV，设备唯一，刷机时必须备份 |
| `nr_modem_a/b`、`nr_phy_a/b` | 50 MiB ×4 | 调制解调器/NV |
| `nr_runtimenv1/2` | 55 MiB ×2 | 运行时 NV |
| `nr_deltanv_a/b` | 1 MiB ×2 | NV 增量 |
| `l_agdsp_a/b` | 6 MiB ×2 | 音频 DSP |
| `pm_sys_a/b`、`ch_sys_a/b` | 1/16 MiB ×2 | 电源/充电 |
| `ise_a/b`、`isedata` | 4/4/34 MiB | ISE |
| `calinv` | 15 MiB | 校准 |
| `odmko_a/b` | 25 MiB ×2 | ODM 内核模块 |
| `socko_b` | 75 MiB | 单份 |
| `metadata` | 16 MiB | 元数据 |
| `blackbox` | 500 MiB | 日志/黑匣子 |
| `sysdumpdb` | 10 MiB | 转储 |
| `logo` / `fbootlogo` | 8 MiB ×2 | 开机 logo |
| `uboot_log` | 16 MiB | 引导日志 |
| `userdata` | 112.5 GiB | `/data`（f2fs） |

`/vendor/modules` 里是闭源/厂商内核模块，例如 `mali_kbase.ko`、`audio-*.ko`、`agdsp_pd.ko`、
`chipone_icn9922c_ts.ko`、`npu_img_vha.ko`；`/vendor/firmware` 里有摄像头、触摸、GNSS、WCN 等固件。
这些是"闭源固件部分"的直接证据，也是换 OpenHarmony 大版本时的主要兼容性风险。

## 八、系统升级、刷机与 OTA 现状（2026-11-15 实测）

### 8.1 设备自带升级能力

- `/system/bin/write_updater` 存在，支持：
  - `write_updater updater /data/updater/updater.zip`：写入升级命令并重启进 updater
  - `write_updater sdcard_update`：SD 卡升级
  - `write_updater user_factory_reset`：恢复出厂
  - `write_updater clear`：清除升级命令
  - `write_updater updater_para`：写升级参数
- `/data/updater/updater_result` 里有一条**成功**的历史记录：
  `updater_608-613.zip|pass||install_time=65.92|update_bi|update_bi|`
  说明厂商曾通过 OTA 包把系统从 608 升到 613；设备具备可用的 A/B 升级链路。
- `/data/update/ota_package/firmware/versions/` 是 OTA 包落盘目录，当前为空。
- `update.serverip.search = honglve.superred.com.cn`，`update.server.port = 16895`，这是厂商的升级服务参数。
- `updater_sa`、`update_service`、`module_update_service` 都在运行。

### 8.2 OTA 包不是随便打的 zip

`libupdateservice.z.so` 里能读到的关键字符串：

- `VerifyUpgradePackage`、`Verify zpkcs7 signature failed`、`Parse zip package signature failed`
- `Failed to VerifyUpgradePackage`、`calc pkg sha256 digest failed`
- `--update_package=%s`、`--sdcard_update`
- `/data/service/el1/public/update`、`/ota_package`

结论：升级包是带 PKCS#7 签名的 zip；updater 会校验签名和摘要。没有厂商签名链，自己打的包大概率过不了校验。
`const.secure=0` / `const.debuggable=1` 不能替代这个校验，除非厂商明确说明该镜像关闭了升级包验签。

### 8.3 因此，升级路线分三种

1. **厂商 OTA（首选）**：向硬开鸿要 LHT16 对应新版本的 OTA zip / 完整包，按厂商说明升级。
   这是唯一已经在这台设备上被证明跑通的路径（608 -> 613）。
2. **厂商 4.0 BSP + 自建（可验证工具链）**：Gitee 上 `develop-phone-open-source/manifest`
   的 `OpenHarmony-4.0-Release` 分支包含 `device/board/hys`、`device/soc/sprd`、`vendor/hys`、
   内核补丁和 `laphone` 产品配置；补齐闭源文件后可编译出 `laphone_nosec_userdebug.pac`。
   但产物是 **4.0/API 10**，比设备当前 4.1.7.5/API 11 旧，不是升级包。详见
   [VENDOR-BUILD.md](VENDOR-BUILD.md)。
3. **直接拿社区 master 刷（不建议）**：没有 UIS7885 的 device 适配和闭源 blobs，镜像无法匹配
   `/vendor` 的 HAL/内核 ABI；即使强行写入，也可能不启动、丢 modem/NV、或无法回滚。
4. **要 API 26**：需要厂商提供 4.1/5.x/6.x 的 BSP 或已签名 OTA；公开仓库目前没有这些分支。

### 8.4 闭源固件到底支不支持升级

- 闭源部分不是"一个版本永久通用"的。`uboot`、`trustos`、`modem/NV`、`agdsp`、`mali_kbase.ko`、
  摄像头/触摸/GNSS firmware 都与 SoC、内核 ABI、HDF/HAL 接口绑定。
- 小版本 OTA 通常由厂商同时更新 `system` 和 `vendor`/`boot`，所以能保持配套；
  大版本（例如 API 11 -> API 12/26）一般需要厂商发布新的 vendor 镜像和内核模块。
- 只换 `system`、保留旧 `vendor` 的"混搭"在 OpenHarmony 大版本间不受支持，HAL 接口、SELinux 策略、
  内核模块 vermagic 都可能对不上。
- 所以"闭源固件支不支持升级"取决于厂商是否为 LHT16 出了对应版本的 BSP/OTA，而不是社区源码版本。

### 8.5 刷机前必须做的事

1. **先备份**：至少备份 boot/vendor_boot/dtb/dtbo/uboot/trustos/sml/misc/persist/prodnv/NV 分区，
   以及 system/vendor/product/sys_prod/updater/odmko。`userdata` 单独按应用数据备份。
   本仓 `scripts/backup-device.ps1` 提供只读备份流程；未备份前不要刷。
2. **记录版本**：`param get` 的 fullname / apiversion / software.version / oharm.version / 安全补丁 / 内核。
3. **确认回滚**：问厂商要原厂完整包、刷机工具、救砖流程；确认 anti-rollback 是否存在。
4. **确认签名**：OTA 包/镜像是否必须厂商签名；bootloader 是否解锁；`fastboot`/SPD 工具是否可用。
5. **不要混包**：不要用其他 UIS7885 板子或其他厂商的镜像。

### 8.6 给厂商的索取清单

- LHT16 / UIS7885 对应目标 OpenHarmony 版本的 **BSP**：`device/`、`vendor/`、内核源码/配置、HDF 驱动、闭源 blobs。
  明确问：除了公开的 `OpenHarmony-4.0-Release`，是否有 4.1/5.x/6.x 分支或私有 manifest？
- 该版本的 **完整刷机包** 和 **OTA 增量包**（含签名），以及包格式说明。
- **签名工具/密钥**（如果允许自编译）：镜像签名、OTA 包签名、profile 签名。
- **刷机/救砖工具**：SPD ResearchDownload / UDownload / fastboot 中的哪一种；驱动；操作手册。
- **分区表**、**slot 切换/回滚**说明、**anti-rollback** 策略。
- **bootloader 解锁状态**与解锁方法；`const.secure=0` 的实际含义。
- 目标版本的 **release notes**：API level、内核版本、已知问题、是否支持 modem/相机/显示等。

## 九、不要进公开仓库的东西

- 完整序列号、MAC、内网 IP、`const.product.devUdid`；
- `signing/` 下的 `.p12` / `.cer` / `.p7b`；
- 固件镜像、OTA 包、SDK 压缩包（体积大且有版权/分发限制）；仓库里只记版本号和 SHA256；
- `/data` 下抓出来的任何用户数据；
- 厂商提供的闭源 blobs、密钥、内部工具。

## 变更记录

- 2026-11-15 首次建立；记录实测版本、硬件、调试状态、已验证行为与刷机备份原则。
- 2026-11-15 迁入 ohos-device；补充 A/B 分区表、OTA 历史、updater 验签证据、闭源固件兼容性判断与厂商索取清单。
