# 开发者手机公开镜像汇总（2026-11-15 搜索）

只记录实际搜到的资源，标注来源和适用代际。**刷错代际/型号有变砖风险**，刷前先核对。

## 一、先确认你是第几代

官方第二代（2024-04）相对第一代的差异：

- 代工厂宇龙酷派
- 120 Hz 高刷屏
- 前/后摄升级
- 支持快充
- 电源键指纹
- 双 nano SIM

当前这台 LHT16 实测是 **60 Hz、`const.telephony.slotCount=1`（单卡）**，因此按参数判断是**第一代**。
如果你看到的机器是 120 Hz/双卡/电源键指纹，那就是第二代，不能刷一代包。

## 二、官方 Laval 镜像

### 2.1 OH 4.0 / OH 4.1（两代都有）

页面：<https://laval.csdn.net/65f40ca1857a901a0ff9a123.html>

第二代：

| 版本 | 链接 | 提取码 |
| --- | --- | --- |
| B613_OH 4.1 | <https://pan.baidu.com/s/18zB3C_eL8Elx02CJXfZdIQ?pwd=r8ww> | r8ww |
| B608_OH 4.1 | <https://pan.baidu.com/s/1TcdFcdjjVhrpUnUFri3N0g?pwd=sb99> | sb99 |
| B605_OH 4.1 | <https://pan.baidu.com/s/19DjYIFQskhbqIxgZgH66fQ?pwd=h1kf> | h1kf |
| B503_OH 4.0 | <https://pan.baidu.com/s/1wXQSFv0h1DAvoyNEzvO2hQ?pwd=2g7f> | 2g7f |

第一代：

| 版本 | 链接 | 提取码 |
| --- | --- | --- |
| 613_OH 4.1 | <https://pan.baidu.com/s/1bNv6yM-8D2ZEa1TlXPtbNA?pwd=yc8s> | yc8s |
| 608_OH 4.1 | <https://pan.baidu.com/s/1y-tIfGnZPJzrYKj5MemTmg?pwd=njb4> | njb4 |
| 605_OH 4.1 | <https://pan.baidu.com/s/1ylM8a3TkKWOePQ0x_iyu2A?pwd=mggu> | mggu |
| 319_OH 4.0 | <https://pan.baidu.com/s/1ouA3fsjiZ-wp8PEI8JtSyA?pwd=d4tu> | d4tu |
| 318_OH 4.0 | <https://pan.baidu.com/s/1wIvJ3wZot1uprN3r9bqA-w?pwd=a1du> | a1du |
| 309_OH 4.0 | <https://pan.baidu.com/s/1YC0RVocw88HLmi50ATMnEQ?pwd=351r> | 351r |

**第一代 613_OH 4.1** 就是这台设备当前系统的官方回滚包，刷社区新镜像前建议先下载保留。

### 2.2 OH 5.0（只支持第二代）

页面：<https://laval.csdn.net/674535e6522b003a54704cf5.html>

页面明确写 **OH 5.0 仅支持第 2 代开发者手机**。

| 版本 | 链接 | 提取码 |
| --- | --- | --- |
| B703_OH 5.0.0 | <https://pan.baidu.com/s/1ZFeY6iIKPRMSO_s3ZU-wdQ?pwd=rz5r> | rz5r |
| B710_OH 5.0.0 | <https://pan.baidu.com/s/1PRs5SwUstCZihPiOHYUkow?pwd=na67> | na67 |

第一代没有官方 5.0 包，不要拿二代包刷一代。

## 三、社区镜像（非官方）

### 3.1 一代开发者手机 OpenHarmony 6.1 LTS

B 站视频：<https://www.bilibili.com/video/BV1mfTd6REYn/>
标题：`【全网首发】 一代开发者手机 OpenHarmory 6.1 LTS版本体验`
UP：`_北方方`

简介里的镜像：

```text
通过网盘分享的文件：laphone_nosec_userdebug.zip
链接: https://pan.baidu.com/s/1xuB56hPsHMcZsNyTvw8ZOg?pwd=u569
提取码: u569
```

2026-11-15 实测：链接有效，提取码 `u569` 校验通过。视频评论里有人反馈“成功刷进去了，LTS 确实比 release 好”。

注意：

- 这是**社区移植/体验包**，不是 Laval 官方发布；
- 标题写的是**一代**，按本机参数判断对得上；二代不要刷；
- 6.1 Release 的 Public SDK 是 **API 23**（6.1.0.31），不是 API 26；
- 相机/modem/GPU/指纹等功能是否完整未知，作者没有公开详细适配说明；
- 刷前必须备份，并保留第一代官方 613 回滚包（`yc8s`）；
- 包名是 `.zip`，里面可能是 PAC 或分区镜像，下载后先看目录结构，再用 `UpgradeDownload`。

### 3.2 其他社区线索

- 6.0 Release 点亮视频：<https://www.bilibili.com/video/BV1f8qsBbE9c/>（简介没有公开镜像链接）
- 6.1 Release 点亮视频：<https://www.bilibili.com/video/BV18zAfzrEuf/>（简介没有公开镜像链接）
- Gitee“开发者手机衍生版”组织：<https://gitee.com/openharmony_phone>
  - 基于 OH 4.0 分支，62 个仓库；
  - 页面底部“固件下载”链接 `https://pan.baidu.com/s/1yzcUIPgRYPFF8YVsnEPXGA?pwd=azsg` 实测**已失效**；
  - 没有 6.1/7.0 分支。

## 四、目前没找到的

- 开发者手机（一代/二代）的 **OpenHarmony 7.0 / API 26** 公开镜像；
- 一代的官方 5.0/6.x 包；
- 6.1 LTS 的官方适配说明、已知问题列表、签名/回滚说明。

所以“微信群里有人装上的新镜像”，最可能就是上面这个 **一代 6.1 LTS 社区包**。
它能把 API 11 直接拉到 API 23，跨度很大；但不是官方包，风险要自己承担。

## 五、刷前检查清单

1. 确认代际：一代（60Hz/单卡）还是二代（120Hz/双卡/电源键指纹）。
2. 下载并解压社区包，确认里面是 PAC 还是分区镜像；不要混用二代包。
3. 先跑 `scripts/backup-device.ps1`，备份 boot/NV/system/vendor 等。
4. 下载第一代官方 613 回滚包（`yc8s`）并解压备用。
5. 用厂商 `UpgradeDownload` + 驱动刷入；保持供电，不拔线。
6. 刷完核对 `const.ohos.fullname`、`const.ohos.apiversion`、modem/相机/显示/音频/指纹。
7. 如果关键硬件不可用，回滚 613 官方包。

## 六、安全性 / 可玩性 / 与 API 26 的差距

### 6.1 这个社区 6.1 LTS 镜像的安全性

包名 `laphone_nosec_userdebug` 已经说明了性质：

- `nosec`：不走安全启动/安全镜像链，刷入门槛低，但也没有 verified boot 保护；
- `userdebug`：调试构建，通常 `const.debuggable=1`，可能开放 root/hdc，SELinux 也可能是 permissive；
- 非官方发布：没有 Laval 的签名、OTA 链、安全补丁承诺；构建来源和改动无法完整验证；
- 厂商闭源 blobs 仍是旧的：相机/modem/GPU/TEE 等即使能跑，也不等于有安全更新；
- 没有官方 OTA：后续安全补丁要重新找作者/重新刷，不能指望自动更新。

结论：**适合折腾/离线实验，不适合当日常主力机或登录重要账号。**
刷前至少做：备份、保留 613 回滚包、隔离网络、不要放个人数据；刷后检查
`const.debuggable`、`const.secure`、安全补丁日期、`getenforce`、是否有未知预装应用。

### 6.2 API 23 本身

OpenHarmony 6.1 Release 的 Public SDK 是 **6.1.0.31 / API 23**，6.1 被定为 LTS（长期支持）。
API 23 本身有现代权限模型、沙箱、证书/密钥、后台限制、分布式和 ArkWeb 等能力，
比 API 11 完整得多；作为 LTS，稳定性和补丁周期也比追新版本更可控。

但“API 23 安全”不等于“这个镜像安全”：镜像里的 vendor 部分、调试开关、预装内容、
是否合并了最新安全补丁，都需要单独确认。

### 6.3 API 26 比 API 23 多了什么

本机 DevEco 26 的 API 26 SDK 里，带 `@since 24/25/26` 标注的接口约有 4400 处（按注解粗略统计，
不是唯一 API 数）。主要集中在：

- 多媒体：`@ohos.multimedia.image`、`camera`、`media`、`audio` 大量新接口；
- ArkUI/窗口：`@ohos.arkui.dialog`、`UIContext`、`window.floatView`、`uiMaterial`、
  `SelectionContainer`、`LayoutAlgorithm` 等新组件/布局/弹窗/悬浮窗能力；
- ArkWeb：`@ohos.web.webview` 新接口；
- 连接：`@ohos.nearlink.*`（星闪）、`FusionConnectivity.ranging`、`busManager.serial`；
- 安全/企业：`permissions.d.ts` 新权限、`security.cert`、`cryptoFramework`、
  `security.privacyComputation`、`enterprise.*`（设备/应用/安全策略）；
- 系统/数据：`backgroundTaskManager`、`photoAccessHelper`、`relationalStore`、
  `hiAppEvent`、`geoLocationManager`、`file.fs`、`selectionInput`、`print`、`accessibility`。

这些是“能力面”的差距；具体某个 API 的语义/兼容性要以 API 26 SDK 文档为准。
更关键的是：**目前没有开发者手机的 API 26 镜像**，所以这些能力在这块板上用不到；
能在本机跑的是 API 23 社区包，API 26 只能在 DevEco 模拟器/其他设备上体验。

### 6.4 可玩性判断

- **当开发/折腾板：高。** API 23 比 API 11 现代得多，ArkUI/ArkWeb/媒体/分布式都能玩；
  但相机/modem/GPU/指纹是否可用未知，先按“可能残缺”预期。
- **当信息屏/kiosk：中高。** 只要显示、触摸、Wi-Fi 正常，API 23 的 UI/Web 能力足够；
  社区包不稳定/无 OTA 是主要风险。
- **当日常手机：低。** `nosec_userdebug`、无官方安全更新、闭源 blobs 旧、无 OTA，
  不建议放账号/支付/隐私数据。
- **想体验 API 26：** 这块板目前没有公开镜像；用 DevEco 26 模拟器或其他支持 API 26 的设备，
  不要指望 6.1 LTS 包能变成 26。
