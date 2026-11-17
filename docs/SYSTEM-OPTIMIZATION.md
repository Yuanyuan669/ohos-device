# 系统级体验优化调研（LHT16 / OpenHarmony 4.1 / API 11）

结论先说：**没有找到可直接刷的、完整的 LHT16 4.1/API11 “优化版”镜像。**
官方 613 仍是唯一完整稳定的系统；社区里最接近的是基于 4.0 的衍生仓库，不是 4.1，也不能直接替换。
所以“整套优化”只有两条路：**在 613 上做深度减负/定制**，或**自己维护一套系统镜像**。

## 一、搜过哪里

- Laval 社区搜索：`性能优化`、`流畅`、`系统应用`、`开发者手机 优化`
  - 结果绝大多数是 **应用层**：ArkUI 布局、Flutter、LazyForEach、图片降采样、启动/内存优化
  - 没有 LHT16 的系统级优化 ROM 或完整配置
- Gitee：`openharmony_phone`（开发者手机衍生版）
  - 基于 **OpenHarmony-4.0-Release**，不是 4.1
  - fork 了 `applications_launcher`、`applications_systemui`、`graphic_graphic_2d`、
    `arkui_ace_engine`、`resourceschedule_memmgr`、`window_window_manager`、`startup_appspawn` 等
  - 提交里有 SystemUI/Launcher/图形/内存的修复和优化，但没有 4.1 分支，也没有可用的新固件包
  - 页面底部“固件下载”链接已失效
- GitHub：`laphone`、`uis7885`、`GeekyHarmony`、`OpenHarmony performance` 没有相关完整项目
- 通用 OpenHarmony 性能资料：AOT/PGO、LazyForEach、布局扁平化、bytrace + SmartPerf、
  memmgr/调度、GPU/Composer 调优等，可作为方法，但不是现成 ROM

## 二、现成的“完整方案”为什么没有

1. LHT16 的 4.1 vendor/内核/闭源 blobs 没有公开完整 BSP；
2. 公开源码只到 4.0，编 4.0 等于降级；
3. 6.x 的 GeekyHarmony 是坏移植，相机/输入法/方向都缺；
4. 系统 UI/Launcher/SystemUI 是系统签名应用，普通 HAP 替换不了；
5. 完整优化需要重做 system/product/vendor 和签名/OTA，不是改几个参数。

## 三、可选路线

### A. 613 深度减负 + 参数调优（最实际）

不重刷、风险低，能拿到大部分“感知提升”：

- 卸载/停用不用的第三方和示例应用
- 系统设置里停用不必要的预装应用
- 动画倍率 1.5 → 0.5/1.0
- 关闭不必要的后台服务/自启
- 换轻量 Launcher（如果找到 API11 可用、能设默认的）
- 用 `top`/`SmartPerf` 找常驻 CPU/内存大户
- kiosk 应用侧做 LazyForEach、缓存、减少重绘

预期：桌面滑动、应用启动、设置页会明显轻快；系统底层不会变。

### B. 613 定制系统镜像（半套“完整方案”）

从 613 PAC 里拆 `system`/`product`/`vendor`，删除重应用、改 init/param、精简开机服务、
替换 Launcher/SystemUI（如果能拿到系统签名），再重打 PAC。

- 优点：可以做成真正的“精简 kiosk 系统”
- 缺点：没有源码，只能二进制层改；容易破坏签名/启动；每次官方更新都要重做
- 适合：只做固定 kiosk，不追求通用手机体验

### C. OpenHarmony 4.0 衍生版 + 闭源 blobs（不推荐）

`openharmony_phone` 的思路就是这套：4.0 + 厂商闭源文件 + 定制系统应用。
但它是 4.0/API10，比 613 的 4.1/API11 旧；除非你只想要一个可定制的 kiosk 基线，
否则不值得为了“优化”降级。

### D. 换板 / 上 API26

如果目标是现代系统体验，LHT16 的闭源 vendor 是天花板。RK3568/RK3588 这类开放板
有更新的 OpenHarmony 支持和可定制空间，才是“整套优化”的正路。

## 四、建议顺序

1. 先做基线：冷/热启动、桌面滑动、设置页、kiosk 首屏、内存/CPU 占用
2. 613 减负 + 动画调优 + kiosk UI 更新，测一次
3. 如果还不够，再评估是否值得做定制 system 镜像
4. 不要再用 GeekyHarmony 6.1 这种半成品

## 五、kiosk UI 现状

`D:\ohos-kiosk` 已做第一版 UI 重构：

- 更大的时钟/日期层级
- 天气卡：温度/天气/风况重新排版
- 信息卡：标题 + 圆点列表，滚动区域更干净
- 照片卡：Cover 填充 + 底部照片计数/指示点
- 备忘卡：点按进设置
- 深色卡片、统一圆角/边框/间距
- 已构建、已签名：`build-artifacts/entry-signed.hap`

设备当前不在线，尚未安装验证；连上后跑 `bash scripts/deploy.sh` 即可截图看效果。
