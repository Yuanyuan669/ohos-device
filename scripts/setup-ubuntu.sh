#!/usr/bin/env bash
# 在 WSL/Ubuntu 里安装 OpenHarmony 4.0 (laphone) 构建依赖，创建用户和 workspace。
# 用法（root）:
#   bash /mnt/d/ohos-device/scripts/setup-ubuntu.sh --sync
# 选项:
#   --user NAME        默认 ohos
#   --workspace PATH   默认 /home/<user>/ohos
#   --sync             安装完直接 repo init/sync（很耗时，建议先看提示再跑）
set -euo pipefail

OHOS_USER="ohos"
WORKSPACE=""
DO_SYNC=0
MANIFEST="https://gitee.com/develop-phone-open-source/manifest"
BRANCH="OpenHarmony-4.0-Release"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --user) OHOS_USER="$2"; shift 2 ;;
    --workspace) WORKSPACE="$2"; shift 2 ;;
    --sync) DO_SYNC=1; shift ;;
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
    *) echo "未知参数: $1" >&2; exit 2 ;;
  esac
done

if [[ $EUID -ne 0 ]]; then
  echo "需要 root。用法: sudo bash $0 $*" >&2
  exit 1
fi

if [[ -z "$WORKSPACE" ]]; then
  WORKSPACE="/home/$OHOS_USER/ohos"
fi

export DEBIAN_FRONTEND=noninteractive
export PATH="/usr/local/bin:$PATH"

echo "==> 检测发行版"
. /etc/os-release
echo "    $PRETTY_NAME"
if [[ "${VERSION_ID:-}" != "20.04" ]]; then
  echo "    警告: 厂商文档建议 Ubuntu 20.04，当前是 ${VERSION_ID:-unknown}；脚本会尽量兼容。"
fi

echo "==> apt 基础配置"
dpkg --add-architecture i386 || true
apt-get update
apt-get install -y --no-install-recommends \
  ca-certificates curl wget gnupg lsb-release software-properties-common \
  binutils git git-lfs flex bison gperf build-essential zip unzip \
  zlib1g-dev gcc-multilib g++-multilib libc6-dev-i386 \
  x11proto-core-dev libx11-dev ccache libgl1-mesa-dev \
  libxml2-utils xsltproc m4 bc gnutls-bin python3-pip ruby libtinfo-dev \
  openjdk-17-jre-headless default-jdk libssl-dev genext2fs u-boot-tools \
  mtd-utils scons gcc-arm-none-eabi gcc-arm-linux-gnueabi

echo "==> 可选 32 位/旧版兼容包（失败不阻塞）"
for pkg in lib32ncurses5-dev lib32z1-dev libtinfo5; do
  if apt-get install -y --no-install-recommends "$pkg"; then
    echo "    OK $pkg"
  else
    echo "    WARN $pkg 不可用（${VERSION_ID:-unknown}）"
  fi
done

echo "==> Python 3.8"
PY_VER="$(python3 -c 'import sys; print("%d.%d" % sys.version_info[:2])' 2>/dev/null || echo none)"
if [[ "$PY_VER" == "3.8" ]]; then
  echo "    已是 Python 3.8"
else
  echo "    当前 Python $PY_VER，安装 3.8（deadsnakes）"
  add-apt-repository -y ppa:deadsnakes/ppa
  apt-get update
  apt-get install -y python3.8 python3.8-venv python3.8-dev || {
    echo "    WARN Python 3.8 安装失败；可继续用现有 python3，但 4.0 构建可能不兼容" >&2
  }
  apt-get install -y python3.8-distutils || true
fi

echo "==> 创建用户 $OHOS_USER"
if ! id -u "$OHOS_USER" >/dev/null 2>&1; then
  useradd -m -s /bin/bash "$OHOS_USER"
fi
echo "$OHOS_USER ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/$OHOS_USER"
chmod 440 "/etc/sudoers.d/$OHOS_USER"

# WSL 默认用户
if [[ ! -f /etc/wsl.conf ]] || ! grep -q '^\[user\]' /etc/wsl.conf; then
  cat >> /etc/wsl.conf <<EOF

[user]
default=$OHOS_USER
EOF
else
  sed -i "s/^default=.*/default=$OHOS_USER/" /etc/wsl.conf || true
fi

echo "==> git-lfs / git 配置"
git lfs install --system >/dev/null
sudo -u "$OHOS_USER" -H git config --global user.name "$OHOS_USER"
sudo -u "$OHOS_USER" -H git config --global user.email "$OHOS_USER@localhost"
sudo -u "$OHOS_USER" -H git config --global http.postBuffer 524288000
sudo -u "$OHOS_USER" -H git config --global core.compression 0

# Ubuntu 22.04：只给构建用户一个 python3.8 的 PATH 前置，不改系统全局 python3
if [[ -x /usr/bin/python3.8 ]] && [[ "$(python3 -c 'import sys; print("%d.%d" % sys.version_info[:2])' 2>/dev/null || echo none)" != "3.8" ]]; then
  mkdir -p "/home/$OHOS_USER/bin"
  ln -sf /usr/bin/python3.8 "/home/$OHOS_USER/bin/python3"
  grep -q 'HOME/bin' "/home/$OHOS_USER/.bashrc" 2>/dev/null || echo 'export PATH="$HOME/bin:$PATH"' >> "/home/$OHOS_USER/.bashrc"
  chown -R "$OHOS_USER:$OHOS_USER" "/home/$OHOS_USER/bin" "/home/$OHOS_USER/.bashrc"
  echo "    构建用户 PATH 前置: /home/$OHOS_USER/bin/python3 -> /usr/bin/python3.8"
fi

echo "==> repo"
if ! command -v repo >/dev/null 2>&1; then
  if apt-get install -y repo; then
    echo "    通过 apt 安装 repo"
  else
    echo "    apt 没有 repo，使用 Gitee 镜像安装"
    curl -fsSL https://gitee.com/oschina/repo/raw/master/repo -o /usr/local/bin/repo
    chmod +x /usr/local/bin/repo
  fi
fi
repo --version | head -n 2 || true

echo "==> 创建 workspace: $WORKSPACE"
mkdir -p "$WORKSPACE"
chown -R "$OHOS_USER:$OHOS_USER" "$(dirname "$WORKSPACE")"

if [[ $DO_SYNC -eq 1 ]]; then
  echo "==> repo init/sync（4.0 Release；耗时较长，保持网络）"
  sudo -u "$OHOS_USER" -H bash -lc "cd '$WORKSPACE' && repo init -u '$MANIFEST' -b '$BRANCH' && repo sync -c -j4 && repo forall -c 'git lfs pull'"
  echo "==> 检查闭源预编译文件"
  if [[ -f "$SCRIPT_DIR/check-prebuilts.py" ]]; then
    set +e
    sudo -u "$OHOS_USER" -H python3 "$SCRIPT_DIR/check-prebuilts.py" --root "$WORKSPACE"
    CHECK_RC=$?
    set -e
    echo "    check-prebuilts 退出码: $CHECK_RC（非 0 表示缺闭源文件）"
  fi
else
  echo "==> 未同步源码。下一步："
  echo "    sudo -u $OHOS_USER -H bash -lc \"cd $WORKSPACE && repo init -u $MANIFEST -b $BRANCH && repo sync -c -j4 && repo forall -c 'git lfs pull'\""
fi

cat <<EOF

==> 完成
用户:       $OHOS_USER（WSL 默认用户，重启 WSL 后生效: wsl --shutdown）
workspace:  $WORKSPACE
构建:
  sudo -u $OHOS_USER -H bash -lc "cd $WORKSPACE && bash build/prebuilts_download.sh --skip-ssl && ./build.sh --product-name laphone --ccache --no-prebuilt-sdk"
产物:
  $WORKSPACE/out/laphone/packages/phone/images/laphone_nosec_userdebug.pac

注意：公开 4.0 产物是 API 10，低于设备当前 4.1.7.5/API 11；不要在没有备份/回滚包时直接刷。
EOF
