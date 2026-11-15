#!/usr/bin/env python3
"""检查 LHT16/laphone 源码树里 BUILD.gn 引用的预编译文件是否齐全。

用法:
    python3 scripts/check-prebuilts.py --root ~/ohos
    python3 scripts/check-prebuilts.py --root ~/ohos --verbose

只做只读检查，不修改源码树。退出码 0 = 全部找到；1 = 有缺失。
"""
import argparse
import re
import sys
from pathlib import Path

SCAN_DIRS = [
    "vendor/hys/laphone",
    "device/board/hys/laphone",
    "device/soc/sprd/uis7885",
]

# 这些是构建生成物，flash.cfg 里引用但它们本来就不在源码树里
GENERATED_IMAGES = {
    "system.img",
    "vendor.img",
    "userdata.img",
    "product.img",
    "sys_prod.img",
    "ramdisk.img",
    "updater.img",
    "cache.img",
    "blackbox.img",
    "prodnv.img",
    "persist.img",
    "dtb.img",
    "dtbo.img",
    "boot.img",
    "boot-updater.img",
    "vendor_boot.img",
    "vendor_boot_updater.img",
}

# 只检查这些类型的文件；源码/脚本由 repo 保证
PREBUILT_SUFFIXES = (
    ".so", ".bin", ".img", ".dat", ".xml", ".ini", ".cfg",
    ".cer", ".json", ".txt", ".pac",
)

SOURCE_RE = re.compile(r'^\s*source\s*=\s*"([^"]+)"\s*$')
FLASH_RE = re.compile(r"=\d+@([^\s\r\n]+)")


def is_prebuilt(name: str) -> bool:
    return name.lower().endswith(PREBUILT_SUFFIXES)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", default=".", help="源码树根目录（含 vendor/、device/）")
    parser.add_argument("--verbose", action="store_true")
    args = parser.parse_args()

    root = Path(args.root).expanduser().resolve()
    if not root.is_dir():
        print(f"root 不存在: {root}", file=sys.stderr)
        return 2

    missing = []
    checked = 0
    checked_files = set()

    for scan in SCAN_DIRS:
        base = root / scan
        if not base.is_dir():
            print(f"[WARN] 目录不存在（可能还没 repo sync）: {base}")
            continue

        for gn in sorted(base.rglob("BUILD.gn")):
            try:
                lines = gn.read_text(encoding="utf-8", errors="replace").splitlines()
            except OSError as exc:
                print(f"[WARN] 读不了 {gn}: {exc}")
                continue

            for lineno, line in enumerate(lines, 1):
                m = SOURCE_RE.match(line)
                if not m:
                    continue
                src = m.group(1).strip()
                if not src or "$" in src or "{" in src or src.startswith("//") or src.startswith("/"):
                    continue
                if not is_prebuilt(src):
                    continue

                candidates = [gn.parent / src, root / src]
                found = None
                for candidate in candidates:
                    try:
                        if candidate.exists():
                            found = candidate
                            break
                    except OSError:
                        pass

                checked += 1
                key = str((gn.parent / src).resolve())
                checked_files.add(key)
                if not found:
                    missing.append((gn.relative_to(root), lineno, src))

    # flash.cfg 引用的预编译文件
    cfg = root / "device/board/hys/laphone/pac/ImageFiles/flash.cfg"
    if cfg.is_file():
        try:
            text = cfg.read_text(encoding="utf-8", errors="replace")
        except OSError as exc:
            print(f"[WARN] 读不了 {cfg}: {exc}")
            text = ""
        image_dir = cfg.parent
        for lineno, line in enumerate(text.splitlines(), 1):
            m = FLASH_RE.search(line)
            if not m:
                continue
            name = m.group(1).strip()
            if not name or name in GENERATED_IMAGES:
                continue
            checked += 1
            if not (image_dir / name).exists():
                missing.append((cfg.relative_to(root), lineno, name))
    else:
        print(f"[WARN] 缺少 {cfg}（PAC 打包配置）")

    # PAC 打包工具/预编译内核
    pac_dir = root / "device/board/hys/laphone/pac"
    for name in ("mkbootimg", "kernel", "dtb", "Script/mkpac.pl", "ImageFiles/flash.cfg"):
        p = pac_dir / name
        checked += 1
        if not p.exists():
            missing.append((pac_dir.relative_to(root), 0, name))

    print(f"root: {root}")
    print(f"检查预编译引用: {checked}")
    if not missing:
        print("全部找到。可以进入编译步骤。")
        return 0

    print(f"缺失 {len(missing)} 项：")
    seen = set()
    for rel, lineno, src in missing:
        key = (str(rel), src)
        if key in seen:
            continue
        seen.add(key)
        loc = str(rel) + (f":{lineno}" if lineno else "")
        print(f"  MISS  {src}    <- {loc}")

    print("")
    print("把原厂闭源文件放到上面列出的路径；路径以 BUILD.gn 的 source 为准。")
    print("清单说明见 docs/VENDOR-BUILD.md 第 3 节。")
    return 1


if __name__ == "__main__":
    sys.exit(main())
