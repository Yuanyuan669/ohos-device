#!/usr/bin/env bash
# 在 Linux 构建机（香橙派/Ubuntu）上检查 OpenHarmony 4.0 laphone 编译环境。
# 用法: bash scripts/host-check.sh
set -u

echo "== 系统 =="
if command -v lsb_release >/dev/null 2>&1; then
  lsb_release -a 2>/dev/null || true
else
  cat /etc/os-release 2>/dev/null || true
fi
echo "arch: $(uname -m)"
echo "kernel: $(uname -r)"
echo "cpu: $(nproc) threads"
if command -v lscpu >/dev/null 2>&1; then
  lscpu | grep -E 'Model name|CPU\(s\)|Thread|Core|Socket' || true
fi

echo
echo "== 内存/磁盘 =="
free -h
echo
df -h "$HOME" / 2>/dev/null | awk 'NR==1 || !seen[$0]++'

echo
echo "== 关键工具 =="
for cmd in git git-lfs repo python3 python pip3 java javac gcc g++ make cmake ninja ccache ssh sshd docker podman; do
  if command -v "$cmd" >/dev/null 2>&1; then
    printf "OK   %-10s %s\n" "$cmd" "$(command -v "$cmd")"
  else
    printf "MISS %-10s\n" "$cmd"
  fi
done
python3 --version 2>&1 || true
git --version 2>&1 || true
git lfs version 2>&1 || true
repo --version 2>&1 | head -n 2 || true
java -version 2>&1 | head -n 3 || true

echo
echo "== apt 依赖 =="
PKGS="binutils git git-lfs gnupg flex bison gperf build-essential zip curl zlib1g-dev gcc-multilib g++-multilib libc6-dev-i386 lib32ncurses5-dev x11proto-core-dev libx11-dev lib32z1-dev ccache libgl1-mesa-dev libxml2-utils xsltproc unzip m4 bc gnutls-bin python3-pip ruby libtinfo-dev libtinfo5 openjdk-17-jre-headless default-jdk libssl-dev genext2fs u-boot-tools mtd-utils scons gcc-arm-none-eabi gcc-arm-linux-gnueabi"
missing=""
for pkg in $PKGS; do
  if ! dpkg -s "$pkg" >/dev/null 2>&1; then
    missing="$missing $pkg"
  fi
done
if [ -z "$missing" ]; then
  echo "全部依赖已安装"
else
  echo "缺少:$missing"
fi

echo
echo "== SSH =="
if command -v systemctl >/dev/null 2>&1; then
  systemctl is-active ssh 2>/dev/null || systemctl is-active sshd 2>/dev/null || echo "ssh service 未运行"
fi
ip -4 addr show 2>/dev/null | grep -E 'inet ' | grep -v '127.0.0.1' || true

echo
echo "== 结论 =="
RAM_GB=$(free -g | awk '/^Mem:/{print $2}')
if [ "${RAM_GB:-0}" -ge 16 ]; then
  echo "内存: ${RAM_GB} GB（满足厂商最低 16 GB）"
else
  echo "内存: ${RAM_GB} GB（低于 16 GB，建议 32 GB）"
fi
AVAIL_GB=$(df -BG "$HOME" 2>/dev/null | awk 'NR==2{gsub("G","",$4); print $4}')
if [ -n "${AVAIL_GB:-}" ] && [ "$AVAIL_GB" -ge 200 ]; then
  echo "磁盘: ${AVAIL_GB} GB 可用（>= 200 GB）"
else
  echo "磁盘: ${AVAIL_GB:-?} GB 可用（建议 >= 200 GB）"
fi
if [ -z "$missing" ]; then
  echo "依赖: 已齐"
else
  echo "依赖: 还有缺失，跑 scripts/setup-ubuntu.sh"
fi
if command -v repo >/dev/null 2>&1; then
  echo "repo: 已安装"
else
  echo "repo: 未安装"
fi
