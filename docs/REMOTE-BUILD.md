# 用香橙派 8840U 掌机做 Linux 构建机

结论：**可行，而且比本机 WSL2 更合适。** 8840U（8C/16T）+ 32 GB + 1 TB 正好补上本机
15.1 GB 内存的短板；Windows 继续负责 hdc 和厂商 `UpgradeDownload.exe` 烧录，Linux 只管编译。

## 一、为什么不是 WSL / 双系统

| 方案 | 结论 |
| --- | --- |
| 本机 WSL2 | 能跑，但 15.1 GB 内存对完整 4.0 构建偏紧；VHDX 还要占 D 盘 |
| 本机双系统 | 只多出不到 1 GB 可用内存，仍低于厂商建议的 16 GB；还要缩 D 盘/改 EFI，不值 |
| 8840U 掌机 | 32 GB 内存、1 TB 盘、8C/16T；独立 Ubuntu；最适合持续编译 |
| 远程 Linux/云 | 也可以，但传源码/产物麻烦；本地掌机更可控 |

掌机的唯一代价是要把源码和产物放在另一台机器上，通过 SSH/SCP 来回传；这比内存不足导致
OOM 或重装系统便宜得多。

补充：本机是 9800X3D + 1×16 GB DDR5 单通道。**如果给本机加一条 16 GB 到 32 GB 双通道，
9800X3D 会反超 8840U**，那时优先本机 WSL2（24 GB + swap），掌机作为备用构建机。
在没加内存之前，本机 15.1 GB 单通道更容易 OOM，掌机 32 GB 更适合完整构建。

## 二、先确认掌机状态

把本仓的 `scripts/` 拷到掌机（任选其一）：

```powershell
# Windows -> 掌机
scp -r ohos-device/scripts <user>@<掌机IP>:~/ohos-device-scripts
```

或者等本仓推到 GitHub 后直接 `git clone`。

在掌机上跑：

```bash
bash ~/ohos-device-scripts/host-check.sh
```

重点看：

- `lsb_release -a`：20.04 最好；22.04 也能用，但要装 Python 3.8；24.04 不建议
- `uname -m`：必须是 `x86_64`（8840U 是 x86_64）
- `free -h`：32 GB 应能看到约 30–31 GiB
- `df -h $HOME`：至少留 200 GB（源码 + prebuilts + out）
- `python3 --version`：20.04 自带 3.8；22.04 是 3.10，需要额外装 3.8
- `repo --version`、`git --version`、`git lfs version`
- `sshd` 是否运行（要从 Windows SSH 过去）

## 三、Ubuntu 版本怎么处理

### 3.1 如果是 20.04

最省事，和厂商文档完全一致。直接：

```bash
sudo bash scripts/setup-ubuntu.sh --user ohos --workspace /home/ohos/ohos
```

### 3.2 如果是 22.04

也能用，但要注意 Python 3.8 和旧依赖：

- `setup-ubuntu.sh` 会装 `python3.8`，并给专用用户 `ohos` 建 `~/bin/python3 -> /usr/bin/python3.8`，
  只影响这个构建用户，不改系统全局 python3。
- `libtinfo5`、`lib32ncurses5-dev` 等老包在 22.04 可能缺失；脚本会逐个尝试并打印 WARN。
  缺 `libtinfo5` 时可以从 20.04 的 .deb 补，或者直接用 Docker 20.04。
- 如果 22.04 上仍然遇到 Python/依赖问题，最稳的是 Docker：

```bash
docker run -it --name ohos-build \
  -v /home/ohos/ohos:/home/ohos/ohos \
  -v /home/ohos/.ccache:/home/ohos/.ccache \
  ubuntu:20.04 bash
```

然后在容器里装依赖、`repo sync`、编译；源码和 ccache 都在宿主机目录，容器删了也不丢。

### 3.3 如果是 24.04

不建议直接上；Python/依赖差异更大。用 Docker `ubuntu:20.04` 或装 22.04 双系统/虚拟机。

## 四、推荐拓扑

```text
Windows（本机）                        香橙派 8840U（Ubuntu）
┌──────────────────────┐   SSH/SCP   ┌──────────────────────────┐
│ hdc / 设备            │ <---------> │ repo / 源码 / 编译 / ccache│
│ UpgradeDownload.exe  │             │ out/laphone/.../images    │
│ 备份/烧录             │ <--- PAC --- │ laphone_nosec_userdebug.pac│
└──────────────────────┘             └──────────────────────────┘
```

- 编辑：Windows 上用 VS Code Remote-SSH 连掌机，直接改 Linux 源码树。
- 编译：掌机上跑 `build.sh`；`ccache` 放掌机 SSD。
- 烧录：把 PAC `scp` 回 Windows，用厂商 `UpgradeDownload.exe` 烧。
- 备份：`scripts/backup-device.ps1` 仍在 Windows 跑（设备接 Windows）。

## 五、掌机初始化步骤

1. 装 SSH（如果还没装）：

```bash
sudo apt update
sudo apt install -y openssh-server
sudo systemctl enable --now ssh
ip addr    # 记下局域网 IP
```

2. 在 Windows 上配 SSH key（可选但推荐）：

```powershell
ssh-keygen -t ed25519
type $env:USERPROFILE\.ssh\id_ed25519.pub | ssh <user>@<掌机IP> "mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys"
```

3. 在掌机上创建专用构建用户并装依赖（`ohos` 是锁定密码的，SSH 登录前先设置密码或放 key）：

```bash
sudo bash /path/to/ohos-device/scripts/setup-ubuntu.sh --user ohos --workspace /home/ohos/ohos

# 给 ohos 设置密码，或放 SSH 公钥；否则用主用户 sudo -u ohos 编译
sudo passwd ohos
sudo -u ohos mkdir -p /home/ohos/.ssh
sudo -u ohos bash -c 'cat >> /home/ohos/.ssh/authorized_keys' < ~/.ssh/id_ed25519.pub
sudo chmod 700 /home/ohos/.ssh && sudo chmod 600 /home/ohos/.ssh/authorized_keys
```

4. 同步 4.0 源码（在掌机上，用 `ohos` 用户）：

```bash
sudo -u ohos -H bash -lc '
  cd /home/ohos/ohos &&
  repo init -u https://gitee.com/develop-phone-open-source/manifest -b OpenHarmony-4.0-Release &&
  repo sync -c -j4 &&
  repo forall -c "git lfs pull"
'
```

5. 补闭源文件，跑检查：

```bash
python3 /path/to/ohos-device/scripts/check-prebuilts.py --root /home/ohos/ohos
```

6. 编译：

```bash
sudo -u ohos -H bash -lc '
  cd /home/ohos/ohos &&
  bash build/prebuilts_download.sh --skip-ssl &&
  ./build.sh --product-name laphone --ccache --no-prebuilt-sdk
'
```

7. 把产物传回 Windows：

```powershell
scp <user>@<掌机IP>:/home/ohos/ohos/out/laphone/packages/phone/images/laphone_nosec_userdebug.pac $env:OHOS_BUILD\
scp <user>@<掌机IP>:/home/ohos/ohos/out/laphone/packages/phone/images/laphone_nosec_userdebug.tar.gz $env:OHOS_BUILD\
```

## 六、性能与散热

- 首次全量编译建议 `-j8` 或 `-j12`；32 GB 内存足够，但掌机散热有限，长时间 100% CPU 会降频。
- 用 `ccache`（`--ccache`）；第二次增量编译会快很多。
- 插电、性能模式、垫高/外接散热；`sensors` 或 `btop` 看温度。
- 源码和 `out/` 放 SSD，不要放 SD 卡；`/home` 至少留 200 GB。
- `repo sync -j4` 就够，太大并发容易触发 Gitee 限流。

## 七、Windows 侧还要做什么

- 设备仍接 Windows：`hdc`、`scripts/backup-device.ps1`、厂商 `UpgradeDownload.exe`。
- 需要时用 `scp`/`rsync` 拉 PAC；也可以给掌机开 Samba，但 SSH 更简单。
- 如果掌机和 Windows 不在同一网段，先解决互通（同一路由器/静态 IP/防火墙放行 22）。

## 八、安全

- 掌机不要暴露 SSH 到公网；只开局域网，或用 Tailscale/WireGuard。
- 用 SSH key，禁用密码登录（`/etc/ssh/sshd_config`：`PasswordAuthentication no`）。
- 构建用户 `ohos` 只用于编译，不要给它跑日常桌面/游戏会话。

## 九、下一步

1. 在掌机上跑 `scripts/host-check.sh`，把输出贴回来；先确认 Ubuntu 版本/内存/磁盘/Python。
2. 如果是 20.04：直接 `setup-ubuntu.sh`；如果是 22.04：脚本会处理 Python 3.8，遇到老包缺失再补。
3. 同步 4.0 源码 -> 补闭源文件 -> `check-prebuilts.py` 全绿 -> 编译。
4. 同时继续向厂商要 4.1/5.x/6.x BSP 或 API 26 OTA；公开源码只有 4.0，编译成功也不等于升级到 API 26。
