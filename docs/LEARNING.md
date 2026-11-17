# Laval 社区课程筛选：应用开发向

先回答“是不是都在你知识库里”：**不是。**
我掌握的是通用 OpenHarmony/ArkTS/ArkUI 知识；Laval 的具体课程、PPT、录播、2025–2026 新接口和厂商实践，不保证在训练数据里。你给链接/附件，我可以读、总结、提取代码、对照当前 SDK 做迁移。

## 一、最值得先看的：鸿蒙原生应用公开课（2023）

汇总页：<https://laval.csdn.net/654c962934bf9e25c799ce2f.html>

特点：体系完整、偏基础、有 PPT/录播/代码，适合打底。课程偏 API 9–12，但概念和 ArkUI/ArkTS 基础对 API 11/23/26 仍然适用。

| 课程 | 用途 | 录播 |
| --- | --- | --- |
| 北向应用入门 | 工程结构、Ability、页面、生命周期 | [链接](https://laval.csdn.net/edu/ed7836c7272563d7b48dcfb9d42a3f45) |
| 应用模型 | Stage 模型、UIAbility、Context | [链接](https://laval.csdn.net/edu/faf11bd5a01d29bc60e07fca1206da19) |
| UI 开发 | ArkUI 声明式 UI、布局、组件 | [链接](https://laval.csdn.net/edu/002bf62d3c5042676e94d5860e6636de) |
| ArkTS 语言基础类库 | 集合、字符串、JSON、并发基础 | [链接](https://laval.csdn.net/edu/279097baf441edeee82c6c6fbc3f276d) |
| Web 组件 | WebView、JS Bridge、混合应用 | [链接](https://laval.csdn.net/edu/0c73639998d824663fdc8f80f3356696) |
| 通知 | 本地/系统通知、通知渠道 | [链接](https://laval.csdn.net/edu/2653af3e19f8749a3a80027954a210e8) |
| 窗口管理 | 全屏、横屏、系统栏、常亮（kiosk 必看） | [链接](https://laval.csdn.net/edu/3d3e82bfd631da9ffedde78b3bf96ef6) |
| 媒体 | AVPlayer、音频、图片 | [链接](https://laval.csdn.net/edu/818041566b075694c0665629b83d87db) |
| 网络与连接 | HTTP、Socket、网络状态 | [链接](https://laval.csdn.net/edu/e88ddb9efa2393a488251e41e5d25e6a) |
| 数据管理 | Preferences、关系型数据库、分布式数据 | [链接](https://laval.csdn.net/edu/6184641235cf181cdca775a5dba2cdb9) |
| 文件管理 | 沙箱、文件 API、用户文件 | [链接](https://laval.csdn.net/edu/37798269d9448f41c63819c33807a359) |
| 后台任务管理 | 长时任务、延迟任务、后台限制 | [链接](https://laval.csdn.net/edu/cd2e661934f89519a98459bb1ed875e5) |

代码：<https://laval.csdn.net/656ece079820e81a16d95bfd.html>

## 二、进阶：2025 应用开发系列

汇总页：<https://laval.csdn.net/68775c7aa6db534ba2b96333.html>

| 课程 | 用途 |
| --- | --- |
| 应用架构设计 | 分层、模块化、状态/数据流、工程组织 |
| React Native 入门 | 跨端方案；不是 ArkTS 主线，按需看 |
| 状态管理 V1 | 旧写法，维护老代码用 |
| 状态管理 V2 | **重点**：`@ComponentV2`、`@Local/@Param`、V2 状态模型，API 12+，对 API 23/26 更相关 |

V2 录播：<https://laval.csdn.net/edu/0262b55d1a4ee74d76902371fd70a553>

## 三、部署/测试/系统能力

汇总页：<https://laval.csdn.net/687762aba6db534ba2b964c7.html>

- 《OpenHarmony XTS 测试流程分享》：应用/系统兼容性测试
- 《OpenHarmony 启动恢复子系统介绍》：理解刷机/恢复/启动失败
- 《OpenHarmony Web 应用开发（以小瓦 AI 为例）》：Web 技术栈做应用
- 《OpenHarmony 应用安装介绍》：HAP 安装、签名、调试安装

其中“应用安装”和“XTS”对后面打包/上板最直接。

## 四、按需看：媒体、通信、统一互联

- 媒体框架系列：<https://laval.csdn.net/6877614aa6db534ba2b9647b.html>
  - 图形框架、渲染后端、图形 HDI、Histreamer、蓝牙通话
  - 做播放器、相机、复杂 UI/动画时有用
- 通信技术系列：<https://laval.csdn.net/68776462080e555a88cfe1ec.html>
  - 分布式设备发现/认证、蜂窝上网流程
- 统一互联专栏：<https://laval.csdn.net/column/6686687f4396326ba84168fe>
  - 设备联动、富对富文件互传、IoT Connect、BLE 配网
  - 做多设备/跨端应用时看；单机 kiosk 可以先跳过
- 案例专栏：<https://laval.csdn.net/column/6481c43823bba5458d8ee09b>
  - 1234 篇，偏系统/驱动/实战；按关键词（ArkUI、Camera、USB、分布式、性能）筛，不要通读

## 五、南向/系统向（不是应用主线）

- 开发者手机南向适配公开课：<https://laval.csdn.net/65ae05f86901917cd68b559a.html>
- 芯片适配系列：<https://laval.csdn.net/68a417b2a6db534ba2c43479.html>
- 系统能力/启动恢复/XTS：见上

这些对你刷机、BSP、驱动有用；做应用可以先不看。

## 六、推荐学习顺序（针对这台 LHT16 + kiosk）

1. 北向应用入门 → 应用模型 → UI 开发
2. ArkTS 基础类库 → 状态管理 V1/V2
3. 窗口管理 + 通知 + 后台任务（kiosk 常亮/横屏/保活）
4. 网络与连接 + 数据管理 + 文件管理（天气/照片/配置）
5. Web 组件 / Web 应用（如果要做混合页面）
6. 应用安装 + XTS（打包、签名、上板、测试）
7. 需要多设备时再看统一互联/通信系列

## 七、和 API 26 的关系

- 这些课大多录制于 2023–2025，覆盖 API 9–12 居多；V2 状态管理是 API 12+。
- API 26 的新接口（新 ArkUI/窗口/媒体/安全/NearLink 等）不在这些老课里，需要：
  - OpenHarmony 6.1/7.0 release notes
  - DevEco 26 的 API 26 SDK/d.ts
  - API 26 模拟器实测
- 课程的价值是**打基础和工程习惯**，不是 API 26 的完整清单。

## 八、怎么用我

你可以直接丢给我：

- 课程链接 / PPT / 录播字幕
- 课程里的示例代码
- 你写的 kiosk 代码 + 目标 API

我可以做：总结、对照 API 版本、改写成当前工程、补类型/错误处理、生成最小示例、做迁移 checklist。
