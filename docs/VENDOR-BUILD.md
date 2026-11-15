# 厂商源码编译与烧录（LHT16 / laphone）

来源：Laval 社区两篇官方文档（2024-02 发布）：

- 开发者手机开源代码编译指导：<https://laval.csdn.net/65e01edcc8f8dc5d4626b09e.html>
- 开发者手机镜像烧录指导：<https://laval.csdn.net/65c33699dafaf23eeaee8610.html>

本文把关键步骤、版本事实和闭源文件清单落到本仓，避免每次重新翻网页。

## 0. 先看清版本：公开源码是 4.0，不是设备上的 4.1

| 项 | 值 |
| --- | --- |
| 公开 manifest | `https://gitee.com/develop-phone-open-source/manifest` |
| 公开分支 | **只有** `OpenHarmony-4.0-Release` |
| 产品名 | `laphone` |
| 设备当前系统 | OpenHarmony-4.1.7.5 / API 11 / OHarm OS 2.0.613 |
| 公开源码产物 | 4.0 Release，预期 API 10（以实际产物/刷入后 `param` 为准），`laphone_nosec_userdebug.pac` |

结论：

- 这套公开源码可以**复现 4.0 / API 10** 的 laphone 镜像，用来验证工具链、做恢复包、改 4.0 系统；
- 它**不是**把设备从 4.1/API 11 升到 API 26 的路径，编出来反而比设备当前版本旧；
- 真要 API 26，仍然需要厂商提供 4.1/5.x/6.x 的 BSP 或已签名 OTA。公开仓库目前没有这些分支。

## 1. 编译环境

厂商文档建议：

- Ubuntu 20.04
- 内存最低 16 GB
- Python 3.8
- 依赖包：

```bash
sudo apt-get update
sudo apt-get install binutils git git-lfs gnupg flex bison gperf build-essential \
  zip curl zlib1g-dev gcc-multilib g++-multilib libc6-dev-i386 \
  lib32ncurses5-dev x11proto-core-dev libx11-dev lib32z1-dev ccache \
  libgl1-mesa-dev libxml2-utils xsltproc unzip m4 bc gnutls-bin python3-pip \
  ruby libtinfo-dev libtinfo5
sudo apt-get install openjdk-17-jre-headless default-jdk libssl-dev genext2fs \
  u-boot-tools mtd-utils scons gcc-arm-none-eabi gcc-arm-linux-gnueabi
```

本机是 15.1 GB 内存，低于 16 GB 建议值；**优先用 8840U 32 GB 掌机编译**，本机 WSL2 作为备选。
掌机方案见 [REMOTE-BUILD.md](REMOTE-BUILD.md)；WSL2 见 [ENVIRONMENT.md](ENVIRONMENT.md) 和
`scripts/setup-wsl.ps1`。两者都用 `scripts/setup-ubuntu.sh` 装依赖。

## 2. 下载源码

```bash
mkdir -p ~/ohos && cd ~/ohos
repo init -u https://gitee.com/develop-phone-open-source/manifest -b OpenHarmony-4.0-Release
repo sync -c
repo forall -c 'git lfs pull'
```

manifest 结构：

- `default.xml` 引入 `chipsets/sprd7885.xml` 和 `ohos/ohos.xml`
- `chipsets/sprd7885.xml` 里的厂商仓：
  - `device_soc_sprd` -> `device/soc/sprd`
  - `device_board_hys` -> `device/board/hys`
  - `vendor_hys` -> `vendor/hys`
  - `kernel_linux_patches` -> `kernel/linux/patches`
  - 以及 `build`、`foundation/arkui/ace_engine`、`base/update/*`、`foundation/communication/wifi`、
    `drivers/*`、`base/telephony/ril_adapter` 等厂商 fork，统一 `OpenHarmony-4.0-Release`

产品配置：`vendor/hys/laphone/config.json`，产品名 `laphone`，`device_build_path`
指向 `device/board/hys/laphone`，`target_cpu=arm64`，`type=standard`。

## 3. 补全原厂闭源文件

厂商明确说明：闭源文件只能从原厂 license 客户处获取，不补齐会编译失败或系统跑不起来。
公开仓库里没有这些文件；部分目录只有 BUILD.gn 指向它们。

### 3.1 文档给出的清单（按原表）

```text
libae3.x.z.so              vendor/hys/laphone/camera/ispalg/isp_lib/libs/32/oh_libae3.x_release
libaf3.2.z.so              vendor/hys/laphone/camera/ispalg/isp_lib/libs/32
libaf3.2_le.z.so           vendor/hys/laphone/camera/ispalg/isp_lib/libs/32
libaftrigger.z.so          vendor/hys/laphone/camera/ispalg/isp_lib/libs/32
libalsc3.2.z.so            vendor/hys/laphone/camera/ispalg/isp_lib/libs/32/oh_libalsc3.2
libatm.z.so                vendor/hys/laphone/camera/ispalg/isp_lib/libs/32/oh_libatm_release
libawb3.2.z.so             vendor/hys/laphone/camera/ispalg/isp_lib/libs/32/oh_libawb3.2
libdeflicker.z.so          vendor/hys/laphone/camera/ispalg/isp_lib/libs/32/oh_libdeflicker_release
libflash.z.so              vendor/hys/laphone/camera/ispalg/isp_lib/libs/32/oh_libflash_release
libpdalgo.z.so             vendor/hys/laphone/camera/ispalg/isp_lib/libs/32
libae3.x.z.so              vendor/hys/laphone/camera/ispalg/isp_lib/libs/64
libaf3.2.z.so              vendor/hys/laphone/camera/ispalg/isp_lib/libs/64
libaf3.2_le.z.so           vendor/hys/laphone/camera/ispalg/isp_lib/libs/64
libaftrigger.z.so          vendor/hys/laphone/camera/ispalg/isp_lib/libs/64
libalsc3.2.z.so            vendor/hys/laphone/camera/ispalg/isp_lib/libs/64
libatm.z.so                vendor/hys/laphone/camera/ispalg/isp_lib/libs/64
libawb3.2.z.so             vendor/hys/laphone/camera/ispalg/isp_lib/libs/64
libdeflicker.z.so          vendor/hys/laphone/camera/ispalg/isp_lib/libs/64
libflash.z.so              vendor/hys/laphone/camera/ispalg/isp_lib/libs/64
libpdalgo.z.so             vendor/hys/laphone/camera/ispalg/isp_lib/libs/64
libjpeg_hw_sprd.z.so       device/soc/sprd/uis7885/hardware/camera/lib
libomx_avcdec_hw_sprd.z.so device/soc/sprd/uis7885/hardware/omx_il/components/video/avc/dec/hw/lib64
libomx_avcenc_hw_sprd.z.so device/soc/sprd/uis7885/hardware/omx_il/components/video/avc/dec/hw/lib64
libasnsupl.z.so            device/soc/sprd/uis7885/hardware/location/lib64
libgnssmgt.z.so            device/soc/sprd/uis7885/hardware/location/lib64
libgps.default.z.so        device/soc/sprd/uis7885/hardware/location/lib64
liblcsagent.z.so           device/soc/sprd/uis7885/hardware/location/lib64
liblcscp.z.so              device/soc/sprd/uis7885/hardware/location/lib64
liblcsmgt.z.so             device/soc/sprd/uis7885/hardware/location/lib64
liblcsmos.z.so             device/soc/sprd/uis7885/hardware/location/lib64
liblcspkcs15.z.so          device/soc/sprd/uis7885/hardware/location/lib64
liblcssc.z.so              device/soc/sprd/uis7885/hardware/location/lib64
liblcswbxml2.z.so          device/soc/sprd/uis7885/hardware/location/lib64
libsupl.z.so               device/soc/sprd/uis7885/hardware/location/lib64
QogirN6Pro_CH.bin          device/board/hys/laphone/pac/ImageFiles
liballocator.z.so          device/soc/sprd/uis7885/hardware/gpu/lib64
libGLES_mali.z.so          device/soc/sprd/uis7885/hardware/gpu/lib64
libmapper.z.so             device/soc/sprd/uis7885/hardware/gpu/lib64
cp_diskserver.bin          vendor/hys/laphone/modem/bin
libmodem_utils.z.so        vendor/hys/laphone/modem/lib64
libatci.z.so               vendor/hys/laphone/telephony/sprd_ril
librilcore.z.so            vendor/hys/laphone/telephony/sprd_ril
libril-impl.z.so           vendor/hys/laphone/telephony/sprd_ril
libril-private.z.so        vendor/hys/laphone/telephony/sprd_ril
librilutils.z.so           vendor/hys/laphone/telephony/sprd_ril
modem_control.bin          vendor/hys/laphone/modem/bin
modem_ch_info.xml          vendor/hys/laphone/modem/etc
modem_cp_info.xml          vendor/hys/laphone/modem/etc
modem_ril.ini              vendor/hys/laphone/modem/etc
modem_sp_info.xml          vendor/hys/laphone/modem/etc
sml-sign.bin               device/board/hys/laphone/pac/ImageFiles
```

### 3.2 以当前仓库的 BUILD.gn 为准

公开仓库的相机目录已经带了一部分 4.0 命名的库（`libcamAe4.0.z.so`、`libcamAf4.0.z.so` 等），
而厂商文档的表里写的是 3.x 命名。实际编译以 `BUILD.gn` 的 `source =` 为准。

本仓提供：

```bash
python3 scripts/check-prebuilts.py --root ~/ohos
```

它会扫描：

- `vendor/hys/laphone/**/BUILD.gn`
- `device/board/hys/laphone/**/BUILD.gn`
- `device/soc/sprd/uis7885/**/BUILD.gn`
- `device/board/hys/laphone/pac/ImageFiles/flash.cfg`

把所有 `source = "..."` 和 flash.cfg 引用的预编译文件逐个检查，列出缺失项。
先把闭源文件补齐，再编译。

实测（只用公开仓库的 4.0 分支）会报 56 项缺失，除了厂商文档表里的相机/GPU/GNSS/RIL/modem
和 `QogirN6Pro_CH.bin`/`sml-sign.bin`，还包括：

```text
vendor/hys/laphone/camera/sensor/sensor_drv/lib/libsensor_s5kgw1sp03.z.so
vendor/hys/laphone/camera/sensor/sensor_drv/lib/libsensor_gc8034_cxt.z.so
vendor/hys/laphone/camera/sensor/sensor_drv/lib/libsensor_gc5035_lh_m5182.z.so
device/soc/sprd/uis7885/hardware/aosp/.../mapper/2.0/lib/libmapper_passthrough2.0.z.so
device/soc/sprd/uis7885/hardware/aosp/.../mapper/2.1/lib/libmapper_passthrough2.1.z.so
```

所以以 checker 的输出为准，不要只照文档表格收文件。

## 4. 编译

```bash
cd ~/ohos
bash build/prebuilts_download.sh --skip-ssl
./build.sh --product-name laphone --ccache --no-prebuilt-sdk
```

产物：

```text
out/laphone/packages/phone/images/laphone_nosec_userdebug.pac
out/laphone/packages/phone/images/laphone_nosec_userdebug.tar.gz
```

打包脚本：

- `device/board/hys/laphone/pac/uis7885_pac.sh`
- `device/board/hys/laphone/pac/make_boot.sh`
- `device/board/hys/laphone/pac/Script/mkpac.pl`
- `device/board/hys/laphone/pac/ImageFiles/flash.cfg`

`make_boot.sh` 用仓库里的预编译 `kernel` + `dtb` 和构建出的 `ramdisk.img` / `updater.img`
生成 `boot.img`、`boot-updater.img`、`vendor_boot.img`、`vendor_boot_updater.img`；
`uis7885_pac.sh` 把 `*.img` 拷进 `ImageFiles`，再用 `mkpac.pl` 打成 PAC。

## 5. 烧录（Windows）

厂商文档：

1. 下载烧录工具（百度网盘）：
   `https://pan.baidu.com/s/1UniJM5Z6F-8TOUIHR-Cd9g`，提取码 `f3uq`
   - 2026-11-15 验证：链接有效、提取码正确；实际包内是
     `34564__UpgradeDownload_R25.21.1401.7z`（烧录工具）和 `Driver_R4.20.1601.zip`（USB 驱动）。
   - **这个链接只有工具/驱动，不含固件**；它不是 OpenHarmony 4.0 Release，也不对应某个 API。
     `R25.21.1401` 是工具版本，和 OpenHarmony 版本无关。
   - 4.0 固件是源码编译产出的 `laphone_nosec_userdebug.pac`；设备当前 4.1.7.5 则是厂商 OTA/完整包。
   - 页面摘要里另一个 `1drJz1MgYyZVgBC7L78i-Ew` / `84h6` 已失效（“链接不存在”），不要用。
   - 百度网盘需要登录/客户端，命令行无法直接拉取；下载后放到本仓 `tools/`（已被 Git 忽略）。
2. 按系统类型进入目录，双击 `DriverSetup.exe` 装驱动；
3. 双击 `UpgradeDownload.exe`；
4. 手机**关机、不插线**；点工具栏开始；同时按住**音量加 + 电源**，插入数据线；
5. 工具进入下载模式，选择 PAC（`laphone_nosec_userdebug.pac`）开始烧录；
6. 完成后退出下载模式。

注意：

- 烧录工具是 Windows 程序；WSL2 里编译、Windows 里烧录是最顺的组合。
- 刷机会覆盖分区；先按 [DEVICE.md](DEVICE.md) 第七/八节做备份。
- 公开源码产物是 **4.0 / API 10**，比设备当前 4.1.7.5 / API 11 旧。不要在没有原厂回滚包的情况下
  直接把它刷到日常设备上。

## 6. 这对"升到 API 26"意味着什么

| 路线 | 可行性 |
| --- | --- |
| 公开 4.0 源码 + 闭源文件，编译 laphone PAC | 可复现 4.0/API 10；不是升级 |
| 公开源码改到 4.1/5.x/API 26 | 没有对应 device/vendor/内核分支，工作量和风险都很大 |
| 厂商新 OTA 包 | 唯一低风险升级路径；需要厂商提供 |
| 厂商新 BSP | 可自建新版本；需要厂商提供 4.1/5.x/6.x 分支和闭源文件 |

所以基础环境值得搭：它能验证工具链、产出恢复包、让你熟悉 PAC 打包；但不要把它当成 API 26 的捷径。
真正升级仍要向厂商确认新版本 BSP/OTA。

## 7. 下一步

1. 装 WSL2 + Ubuntu 20.04（推荐，见 [ENVIRONMENT.md](ENVIRONMENT.md)）。
2. 跑 `scripts/setup-ubuntu.sh` 装依赖、`repo`，同步 4.0 源码。
3. 把闭源文件按清单放到对应目录，跑 `scripts/check-prebuilts.py` 直到全绿。
4. 编译出 `laphone_nosec_userdebug.pac`，先只做备份/校验，不急着刷。
5. 同时向厂商要 4.1/5.x/6.x 的 BSP 或 OTA；那才是 API 26 的路。
