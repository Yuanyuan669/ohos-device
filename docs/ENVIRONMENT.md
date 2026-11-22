# 本机与设备现状（2026-11-22）

这份文档回答两个问题：**现在手里有什么**、**要打通系统构建/升级/固件包还缺什么**。

结论先行：应用开发链路是通的；厂商 **4.0 Release 源码/BSP 已在 Gitee 公开**，可以编译出
`laphone_nosec_userdebug.pac`，但公开分支只有 4.0/API 10，**低于设备当前的 4.1.7.5/API 11**，
而且相机/GPU/GNSS/RIL/PAC 等闭源文件仍需原厂提供。API 26 仍缺厂商 4.1/5.x/6.x 分支或新 OTA。
详见 [VENDOR-BUILD.md](VENDOR-BUILD.md)。

## 零、环境变量约定（各仓共用）

文档与脚本不再写死盘符，工具链/输出目录统一用下面几个变量；未设置时脚本按 PATH 和常见安装位置回退。

| 变量 | 含义 | 未设置时 |
| --- | --- | --- |
| `OHOS_TOOLS` | 工具链根：`sdk/`、`hvigor-3.2.4/`、`java/jdk-17/` | 按 `OHOS_HDC`/PATH 找 hdc |
| `OHOS_BASE_SDK_HOME` | SDK 根，其下是 `openharmony/`（当前版本）与 `10/`、`11/`（API 号目录） | 依次回退 `$DEVECO_HOME/sdk`、`$HOME/.ohos/sdk` |
| `DEVECO_HOME` | DevEco Studio 安装目录（自带 node/ohpm/hvigor） | 只提示缺失 |
| `OHOS_HDC` | 指定 `hdc` 可执行文件，优先级最高 | 见上 |
| `HVIGOR_USER_HOME` | hvigor 每个工程的缓存根（`~/.hvigor` 的替代） | hvigor 默认 |
| `OHOS_BACKUP` | `backup-device.ps1` 默认输出目录 | 脚本参数默认值 |
| `OHOS_BUILD` | 远端构建产物落地目录 | 脚本参数默认值 |
| `OHOS_JDK` | 构建用 JDK 路径（`set-jdk.ps1` 优先读它） | 依次回退 `OHOS_TOOLS/java/jdk-17`、`DEVECO_HOME/jbr` |
| `OHOS_WSL_ROOT` | WSL 发行版安装根（`setup-wsl.ps1`） | 脚本所在盘符下的 `wsl` 目录 |

`hvigor` 解析依赖时用的是 `NODE_PATH`（`hvigorfile.ts` 里是裸 `require('@ohos/hvigor-ohos-plugin')`），
所以构建环境必须把它指向 `$OHOS_TOOLS/hvigor-3.2.4/node_modules`；各仓的 `scripts/env.sh` 已默认设置。


PowerShell 用法：`$env:OHOS_TOOLS = '<你的工具链根>'`；Git Bash/WSL：`export OHOS_TOOLS=<你的工具链根>`。

## 一、主机

| 项 | 实测值 |
| --- | --- |
| OS | Windows 11 专业版，10.0.26200 |
| CPU | AMD Ryzen 7 9800X3D，8 核 / 16 线程 |
| 内存 | 15.1 GB |
| D 盘 | 601.9 GB 总容量，274.0 GB 可用（SDK 两份 + DevEco 装完后） |
| C 盘 | 5.8 GB 可用（不要往 C 盘装 SDK/构建缓存） |
| 虚拟化 | 固件虚拟化已开，SLAT 可用；当前 `HypervisorPresent = False` |
| WSL | **未安装**（`wsl --status` 提示需要 `wsl --install`） |
| Docker | **未安装** |
| Git | 2.53.0.windows.2 |
| Python | 3.11.9 |
| Node | 24.14.1（DevEco 自带 `$DEVECO_HOME/tools/node/node.exe`，构建优先用它） |
| CMake / Ninja | WinLibs 自带，可用于主机侧小工具，不是 OpenHarmony 构建链 |
| 7-Zip | 未安装（`tar` 可用，`tar.exe` 能读 zip/7z 的一部分格式） |

已安装的鸿蒙相关工具（2026-11-22 实测）：

| 工具 | 路径 | 版本/用途 |
| --- | --- | --- |
| DevEco Studio | `$DEVECO_HOME` | 26.0.0.865（`DS-261.23567.138.36.2600865`），NSIS 静默装到自定义目录 |
| DevEco 自带 SDK | `$DEVECO_HOME/sdk/default/openharmony` | **不存在**：26.0.0.865 安装包只带 IDE 与 tools，SDK 要自己装或用 SDK Manager 拉 |
| DevEco 自带 tools | `$DEVECO_HOME/tools/{node,ohpm,hvigor,llvm,...}` | node 24.14.1、ohpm、hvigor 都在，但 hvigor 版本与 4.x 工程不配套 |
| OpenHarmony 4.0 SDK | `$OHOS_TOOLS/sdk/openharmony-4.0-Release` | API 10，ets/toolchains 4.0.10.13，kiosk 在用 |
| OpenHarmony 4.1 SDK | `$OHOS_TOOLS/sdk/openharmony-4.1-Release` | API 11，与设备当前系统同代，media/browser/homeime/music 等在用 |
| SDK API 目录 junction | `$OHOS_TOOLS/sdk/10`、`$OHOS_TOOLS/sdk/11` | hvigor 3.2.4 需要 `$OHOS_BASE_SDK_HOME/<api>/<component>` |
| 当前 SDK 指针 | `$OHOS_TOOLS/sdk/openharmony` | junction，指向要构建的那份 SDK（`10` 或 `11`） |
| hvigor | `$OHOS_TOOLS/hvigor-3.2.4` | 3.2.4 + `@ohos/hvigor-ohos-plugin` 3.2.4，源 `repo.harmonyos.com/npm` |
| JDK | `$OHOS_TOOLS/java/jdk-17` | OpenJDK **17.0.2**（华为镜像），`JAVA_HOME` 已指向它 |
| hdc | `$OHOS_TOOLS/sdk/openharmony/toolchains/hdc.exe` | Ver 1.3.0a，能连本机开发板 |
| 签名工具 | `$OHOS_TOOLS/sdk/openharmony/toolchains/lib/hap-sign-tool.jar` | 4.0.10.13，配合 SDK 自带 `OpenHarmony.p12` 测试 PKI |

### 1.1 应用构建链路（已在本机验证）

只用命令行，不打开 IDE：

```bash
# 各仓（kiosk / media / appcenter / ...）同一套脚本
cd ohos-kiosk
bash scripts/doctor.sh          # 环境自检
bash scripts/make-signing-material.sh   # 生成 signing/*.p12|.cer|.p7b（一次性）
bash scripts/build.sh           # hvigor assembleHap -> build-artifacts/entry-unsigned.hap
bash scripts/sign.sh            # hap-sign-tool localSign -> entry-signed.hap
bash scripts/deploy.sh          # hdc uninstall/install + aa start + 截图 + hilog
```

2026-11-22 实测结果：

| 步骤 | 结果 |
| --- | --- |
| `ohos-kiosk/scripts/doctor.sh` | 17 项通过 |
| kiosk `build.sh` | BUILD SUCCESSFUL，`entry-unsigned.hap` 1,363,065 bytes |
| kiosk `sign.sh` | `Sign Hap success` + `verify: Verify success` |
| kiosk `deploy.sh` | 装到板上、`aa start` 成功、`pidof` 有进程、截图 UI 正常渲染 |
| appcenter `make-signing-material.sh` | 为 `com.local.appcenter` 签发独立证书 + Profile |
| appcenter `build.sh`/`sign.sh`/`deploy.sh` | 全部通过，商店首页在板上正常显示 |

签名链路的关键点：SDK 自带 `OpenHarmony.p12` 里有 OpenHarmony 测试 PKI 的**根 CA 与中间 CA 私钥**，
所以自签证书能被 stock 镜像信任，不需要厂商证书或 AppGallery 账号。见 `ohos-kiosk/signing/README.md`。


## 二、设备

| 项 | 实测值 |
| --- | --- |
| 型号 | 硬开鸿 LHT16（展锐 UIS7885） |
| 系统 | OpenHarmony-4.1.7.5 / API 11 / Release |
| 厂商版本 | OHarm OS 2.0，产品版本 2.0.613 |
| 内核 | Linux 5.15.74-ab19 aarch64 |
| 内存/存储 | 8 GB / 128 GB（`/data` 112 GB） |
| 连接 | `hdc list targets` 可见；旧/新 hdc 都能识别 |
| shell | root；`/` 与 `/vendor` 只读，`/data` 可写 |
| 调试属性 | `const.debuggable=1`、`const.secure=0`、SELinux permissive |
| 启动 | UFS + A/B slot，当前 `_a`；`system`/`vendor`/`product` 为单份 |
| 升级能力 | `write_updater` 可用；历史 OTA `updater_608-613.zip` 成功 |
| OTA 服务参数 | `update.serverip.search=honglve.superred.com.cn`，端口 16895（可连通） |

设备细节、分区表、OTA 证据见 [DEVICE.md](DEVICE.md)。

## 三、缺什么

### 3.1 硬阻塞（没有它就无法产出可启动的自建固件）

| 缺失项 | 说明 | 怎么补 |
| --- | --- | --- |
| 闭源预编译文件 | 相机 ISP、GPU（`libGLES_mali.z.so` 等）、GNSS、RIL、modem bin/lib、`QogirN6Pro_CH.bin`、`sml-sign.bin` 等不在公开仓库；BUILD.gn 直接引用它们 | 从原厂 license 渠道取回；用 `scripts/check-prebuilts.py` 核对 |
| 4.1/5.x/6.x BSP | 公开 manifest 只有 `OpenHarmony-4.0-Release`，没有设备当前 4.1.7.5/API 11 的分支，更没有 API 26 | 向硬开鸿索取新版本 BSP 或已签名 OTA |
| 镜像/OTA 签名链 | updater 会校验 PKCS#7 签名；没有厂商密钥，自打包大概率被拒；公开产物是 `nosec_userdebug`，不等于 OTA 免签 | 向厂商要签名工具/密钥，或直接要已签名 OTA 包 |
| 刷机/救砖工具 | 当前 PC 没有 `UpgradeDownload.exe`/`DriverSetup.exe`、fastboot；也不知道 bootloader 是否解锁 | 按厂商烧录文档下载工具；同时要救砖流程 |
| 原厂完整包/回滚包 | 没有原始固件包，刷坏后无法保证恢复 | 先备份分区，同时向厂商要原厂包 |
| 分区备份 | 尚未对 boot/NV/system/vendor 等做镜像备份 | 先跑 `scripts/backup-device.ps1`，确认校验和 |

### 3.2 构建环境（能补，但需要重启/安装）

| 缺失项 | 说明 | 怎么补 |
| --- | --- | --- |
| Linux 构建宿主 | 厂商文档要求 Ubuntu 20.04；Windows 原生不支持 | 优先用 8840U 32 GB 掌机；没有就用本机 WSL2；双系统最后考虑 |
| `repo` / git-lfs / 构建依赖 | 没有 `repo`，也没有 `build-essential`、`libssl-dev` 等 | 跑 `scripts/setup-ubuntu.sh` |
| OpenHarmony 源码 | 本机没有源码树 | 掌机/WSL 里 `repo init/sync`，预留 100 GB+ |
| 构建资源 | 本机 15.1 GB 低于厂商建议的 16 GB；掌机 32 GB 足够 | 掌机 `-j12`；本机 WSL 12 GB + swap、`-j8` |
| 构建目标 | 公开 4.0 有 `laphone` product；4.1/5.x/API 26 没有 | 4.0 可直接编译；新版本依赖厂商 BSP |

### 3.2.1 性能/性价比：掌机、WSL2 还是双系统

先看本机内存：**1 条 16 GB DDR5-6000（实际跑 4800），单通道，主板有 4 个插槽**。
9800X3D 的 CPU 单核/多核都比 8840U 强，但 15.1 GB + 单通道是完整构建的瓶颈。

| 方案 | CPU | 内存/带宽 | 改动成本 | 结论 |
| --- | --- | --- | --- | --- |
| 掌机 8840U 32 GB | 8C/16T，移动功耗，持续频率低 | 32 GB，带宽充足 | 已有，装 SSH/依赖即可 | **不花钱方案里最稳**：不会 OOM，适合完整构建 |
| 本机现状 WSL2 | 9800X3D，明显更快 | 15.1 GB 单通道，容易 OOM/吃 swap | 只装 WSL | 能跑但可能被内存拖慢，`-j8` 起步 |
| 本机加 16 GB 内存 + WSL2 | 9800X3D | 32 GB 双通道 | 一条同规格 DDR5 | **综合性价比最高**：CPU 优势释放，不用重装系统 |
| 本机双系统 | 9800X3D | 仍 15.1 GB | 缩 D 盘/改 EFI | 不推荐；加内存比换系统收益大 |

具体建议：

- **只编一两次/不想拆机**：用掌机 32 GB，慢一点但省事；Windows 负责烧录。
- **会反复编译**：给本机加一条 16 GB DDR5-6000（尽量同型号/同时序），凑 32 GB 双通道，
  然后 WSL2 分 24 GB + 16 GB swap，`-j12` 起步。这样 9800X3D + 32 GB 会明显快于 8840U。
- **不要为了内存去做双系统**：本机双系统也只有 15.1 GB，仍低于 16 GB 建议，收益不划算。
- 当前内存跑在 4800；如果主板支持 EXPO，可在稳定前提下开到 6000，但构建稳定性优先。

掌机方案的具体步骤、SSH/SCP 和性能设置见 [REMOTE-BUILD.md](REMOTE-BUILD.md)。
本机 C 盘剩 45 GB、D 盘剩 1.28 TB；如果走 WSL，VHDX 必须放 D 盘。

### 3.3 应用侧（已具备，但不能替代系统升级）

| 项 | 状态 |
| --- | --- |
| API 11 应用编译 SDK | 已装 4.1-Release（API 11），与设备系统同代 |
| API 26 应用编译 SDK | DevEco 26.0.0.865 安装包不自带 SDK（`sdk/default/openharmony` 不存在），要用 SDK Manager 或单独装 |
| API 26 运行时 | 设备只有 API 11，装不上/跑不了 API 26 应用 |
| 结论 | 想在板子上跑新 API，必须升级系统；改 `compileSdkVersion` 没用 |

### 3.4 可选/后续

- 7-Zip：处理厂商给的压缩包更方便，可装。
- USB 电流表/串口板：救砖和看 uboot 日志时有用；当前没有。
- 第二块同型号板或可恢复的备份机：刷机风险对冲；当前没有。
- CI：kiosk 仓有 self-hosted runner 模板，但未真跑；系统构建上 CI 之前先把本地链路跑通。

## 四、已经验证 / 尚未验证

已验证：

- 应用 HAP 的构建、签名、安装、启动、截图全链路（kiosk 与 appcenter 两仓，2026-11-22 本机复现）。
- 自签证书被 stock 4.1.7.5 镜像接受（无需厂商证书）。
- 设备可 root、可读分区、可读 `param`、可执行 `write_updater`。
- 厂商 OTA 曾在设备上成功执行（`updater_608-613.zip`）。
- 厂商 OTA 服务域名和端口从本机可连通。

尚未验证：

- bootloader 是否接受未签名 boot/system 镜像。
- 厂商是否提供 API 12/26 的 LHT16 BSP 或 OTA 包。
- OTA 包的签名校验在 `const.secure=0` 下是否有例外。
- 分区备份/恢复是否可用（还没做第一次备份）。
- WSL2 下 OpenHarmony 源码构建是否能在 15 GB 内存内完成。

## 五、建议的下一步顺序

1. **先备份**：跑 `scripts/backup-device.ps1`，把 boot 链、NV、system/vendor/product 备份到 D 盘，记录 SHA256。
2. **掌机做构建机**：在 8840U 掌机跑 `scripts/host-check.sh`；确认 Ubuntu 版本/内存/磁盘后，
   跑 `scripts/setup-ubuntu.sh`，同步 4.0 源码。没有掌机再退回本机 WSL2（`scripts/setup-wsl.ps1`）。
3. **补闭源文件**：按 `scripts/check-prebuilts.py` 的缺失清单补齐，直到全绿。
4. **编译验证**：产出 `laphone_nosec_userdebug.pac`，先只做校验，不急着刷。
5. **问厂商**：按 [DEVICE.md](DEVICE.md) 8.6 的清单问"LHT16 有没有 4.1/5.x/6.x 的 BSP 或 API 26 OTA 包"。
6. **不要先刷**：在拿到原厂回滚包、确认签名/解锁状态之前，不要写任何分区。
