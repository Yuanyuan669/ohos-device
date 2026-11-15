# 本地不入库文件

这些目录已经写进 `.gitignore`，放进去的东西不会被 `git add`：

```text
firmware/        laphone_nosec_userdebug.pac、原厂完整包、其他镜像
ota/             vendor OTA zip（如 updater_*.zip）
tools/           UpgradeDownload.exe、DriverSetup.exe、fastboot/SPD 等工具
closed-source/   原厂 license 的 .so/.bin 文件包（相机/GPU/GNSS/RIL/modem 等）
backups/         LHT16 分区备份、manifest、SHA256SUMS
local/           自己的笔记、日志、临时文件
```

使用建议：

- 固件/OTA/工具按原厂目录结构保留，别改厂商文件名；
- 闭源文件按 `docs/VENDOR-BUILD.md` 的路径放到源码树里，不要放在本仓；
- 不要 `git add -f` 这些目录，除非明确确认可以公开且没有版权/隐私问题；
- 备份目录至少复制一份到另一块物理磁盘或离线存储。

这台机器上目前没有搜到厂商固件/烧录工具/闭源文件；目录已建好，拿到文件后直接放进去即可。
