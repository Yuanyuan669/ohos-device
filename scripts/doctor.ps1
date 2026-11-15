#Requires -Version 5.1
<#
.SYNOPSIS
  检查 LHT16 系统构建/升级链路还缺什么。
.DESCRIPTION
  只读检查：主机工具、SDK、WSL、设备属性、磁盘/内存、厂商 BSP/OTA/备份是否存在。
  不写设备分区，不安装任何东西。
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File scripts/doctor.ps1
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File scripts/doctor.ps1 -Hdc "D:\ohos-tools\sdk\openharmony\toolchains\hdc.exe"
#>
[CmdletBinding()]
param(
    [string]$Hdc = "D:\ohos-tools\sdk\openharmony\toolchains\hdc.exe",
    [string]$NewHdc = "D:\DevEcoStudio\sdk\default\openharmony\toolchains\hdc.exe",
    [string]$DeviceSerial = "",
    [string]$RepoRoot = "D:\ohos-device",
    [string]$BackupRoot = "D:\ohos-backup"
)

$ErrorActionPreference = "Continue"
try {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    $OutputEncoding = [System.Text.Encoding]::UTF8
} catch { }

function Write-Section($title) {
    Write-Host ""
    Write-Host ("== " + $title + " ==") -ForegroundColor Cyan
}

function Write-OK($msg) { Write-Host ("[OK]   " + $msg) -ForegroundColor Green }
function Write-Warn($msg) { Write-Host ("[WARN] " + $msg) -ForegroundColor Yellow }
function Write-Miss($msg) { Write-Host ("[MISS] " + $msg) -ForegroundColor Red }
function Write-Info($msg) { Write-Host ("       " + $msg) }

function Get-CommandPath($name) {
    $c = Get-Command $name -ErrorAction SilentlyContinue
    if ($c) { return $c.Source }
    return $null
}

function Test-Exe($path) {
    return (Test-Path -LiteralPath $path -PathType Leaf)
}

Write-Host "ohos-device doctor / 2026-11-15"
Write-Host ("Repo: " + $RepoRoot)

Write-Section "主机"
$os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
if ($os) { Write-Info ($os.Caption + "  " + $os.Version + "  " + $os.OSArchitecture) }
$cs = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue
if ($cs) {
    $ram = [math]::Round($cs.TotalPhysicalMemory / 1GB, 1)
    Write-Info ("CPU 逻辑核: " + $cs.NumberOfLogicalProcessors + " / 内存: " + $ram + " GB")
    if ($ram -lt 16) { Write-Warn "内存低于 16 GB，完整 OpenHarmony 构建可能偏紧（建议 32 GB 或远程构建）" }
    else { Write-OK "内存 >= 16 GB" }
}
$d = Get-PSDrive D -ErrorAction SilentlyContinue
if ($d) {
    $free = [math]::Round($d.Free / 1GB, 1)
    Write-Info ("D 盘可用: " + $free + " GB")
    if ($free -lt 200) { Write-Warn "D 盘可用 < 200 GB，源码 + 产物可能不够" }
    else { Write-OK "D 盘空间足够（预留 200 GB+）" }
}

Write-Section "构建环境"
$wsl = Get-CommandPath "wsl.exe"
$lxss = Get-ChildItem "HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss" -ErrorAction SilentlyContinue
if ($wsl -and $lxss) {
    $distroNames = @($lxss | ForEach-Object { (Get-ItemProperty -LiteralPath $_.PSPath -ErrorAction SilentlyContinue).DistributionName } | Where-Object { $_ })
    if ($distroNames -contains "Ubuntu-20.04" -or $distroNames -contains "Ubuntu") {
        Write-OK ("WSL 发行版: " + ($distroNames -join ", "))
    } elseif ($distroNames.Count -gt 0) {
        Write-Warn ("WSL 已安装，但未发现 Ubuntu-20.04；现有: " + ($distroNames -join ", "))
    } else {
        Write-Miss "WSL 已启用但没有发行版（需要 Ubuntu-20.04）"
    }

    $wslconfig = Join-Path $env:USERPROFILE ".wslconfig"
    if (Test-Path -LiteralPath $wslconfig) {
        $cfg = Get-Content -LiteralPath $wslconfig -Raw
        if ($cfg -match "memory\s*=" -and $cfg -match "swap\s*=") { Write-OK ".wslconfig 已配置 memory/swap" }
        else { Write-Warn ".wslconfig 存在但未配置 memory/swap；跑 scripts/setup-wsl.ps1" }
    } else {
        Write-Warn ".wslconfig 不存在；跑 scripts/setup-wsl.ps1 生成"
    }

    if ($distroNames -contains "Ubuntu-20.04") {
        $srcCheck = (& wsl.exe -d Ubuntu-20.04 -u root bash -lc "test -d /home/ohos/ohos/vendor/hys/laphone && echo YES || echo NO" 2>&1 | Out-String)
        if ($srcCheck -match "YES") { Write-OK "WSL 源码树: /home/ohos/ohos（vendor/hys/laphone 存在）" }
        else { Write-Warn "WSL 里还没有源码树 /home/ohos/ohos；先跑 scripts/setup-ubuntu.sh --sync" }
        $repoCheck = (& wsl.exe -d Ubuntu-20.04 -u root bash -lc "command -v repo >/dev/null && echo YES || echo NO" 2>&1 | Out-String)
        if ($repoCheck -match "YES") { Write-OK "WSL 里 repo 已安装" } else { Write-Miss "WSL 里 repo 未安装" }
    }
} elseif ($wsl) {
    Write-Miss "WSL 未安装/未初始化（wsl.exe 存在但注册表无发行版；跑 scripts/setup-wsl.ps1，需管理员+重启）"
} else {
    Write-Miss "WSL 未安装（系统构建需要 Linux；跑 scripts/setup-wsl.ps1）"
}

$docker = Get-CommandPath "docker"
if ($docker) { Write-OK ("docker: " + $docker) } else { Write-Warn "Docker 未安装（不是必须，WSL2 也可以）" }

$repo = Get-CommandPath "repo"
if ($repo) { Write-OK ("repo: " + $repo) } else { Write-Miss "repo 未安装（OpenHarmony 源码同步需要）" }

foreach ($tool in @("git", "python", "node", "cmake", "ninja", "7z")) {
    $p = Get-CommandPath $tool
    if ($p) { Write-OK ($tool + ": " + $p) } else { Write-Warn ($tool + " 未找到（按需安装）") }
}

$java = Get-CommandPath "java"
if ($java) { Write-OK ("java(PATH): " + $java) }
elseif (Test-Exe "D:\ohos-tools\java\jdk-17\bin\java.exe") { Write-Info "java 不在 PATH，但 D:\ohos-tools\java\jdk-17 存在（kiosk env.sh 会补）" }
else { Write-Warn "未找到 java" }

Write-Section "SDK / IDE"
$sdk40 = "D:\ohos-tools\sdk\openharmony\ets\oh-uni-package.json"
$sdk26 = "D:\DevEcoStudio\sdk\default\openharmony\ets\oh-uni-package.json"
if (Test-Path -LiteralPath $sdk40) {
    $j = Get-Content -LiteralPath $sdk40 -Raw | ConvertFrom-Json
    Write-OK ("OpenHarmony 4.0 SDK: apiVersion=" + $j.apiVersion + " version=" + $j.version)
} else { Write-Miss "OpenHarmony 4.0 SDK 未找到（kiosk 应用构建需要）" }

if (Test-Path -LiteralPath $sdk26) {
    $j = Get-Content -LiteralPath $sdk26 -Raw | ConvertFrom-Json
    Write-OK ("DevEco OpenHarmony SDK: apiVersion=" + $j.apiVersion + " version=" + $j.version + " (" + $j.releaseType + ")")
} else { Write-Warn "DevEco 自带 OpenHarmony SDK 未找到" }

if (Test-Path -LiteralPath "D:\DevEcoStudio\product-info.json") {
    $p = Get-Content -LiteralPath "D:\DevEcoStudio\product-info.json" -Raw | ConvertFrom-Json
    Write-Info ("DevEco Studio: " + $p.version)
}

Write-Section "hdc / 设备"
$hdcUsable = $null
foreach ($candidate in @($Hdc, $NewHdc)) {
    if (Test-Exe $candidate) {
        $ver = (& $candidate -v 2>&1 | Out-String).Trim()
        Write-OK ($candidate + "  " + $ver)
        if (-not $hdcUsable) { $hdcUsable = $candidate }
    } else {
        Write-Warn ("hdc 不存在: " + $candidate)
    }
}

$serial = $DeviceSerial
if ($hdcUsable) {
    $targets = @(& $hdcUsable list targets 2>&1 | ForEach-Object { $_.ToString().Trim() } | Where-Object { $_ -and $_ -notmatch "Empty|error|fail" })
    if ($targets.Count -gt 0) {
        Write-OK ("设备: " + ($targets -join ", "))
        if (-not $serial) { $serial = $targets[0] }
    } else {
        Write-Miss "hdc 未列出设备（检查 USB / 调试授权 / 线）"
    }
}

if ($hdcUsable -and $serial) {
    $props = @(
        "const.ohos.fullname",
        "const.ohos.apiversion",
        "const.ohos.releasetype",
        "const.product.model",
        "const.product.software.version",
        "const.product.oharm.version",
        "const.ohos.version.security_patch",
        "const.debuggable",
        "const.secure"
    )
    foreach ($key in $props) {
        $v = (& $hdcUsable -t $serial shell ("param get " + $key) 2>&1 | Out-String).Trim()
        Write-Info ($key + " = " + $v)
    }
    $slot = (& $hdcUsable -t $serial shell "cat /proc/cmdline" 2>&1 | Out-String)
    if ($slot -match "slot_suffix=(\S+)") { Write-Info ("current slot: " + $Matches[1]) }
    $df = (& $hdcUsable -t $serial shell "df -h /data/local/tmp" 2>&1 | Out-String)
    $dfLine = ($df -split "`r?`n" | Where-Object { $_ -match "\S" } | Select-Object -Last 1)
    if ($dfLine) { Write-Info ("/data/local/tmp: " + $dfLine.Trim()) }
}

Write-Section "厂商 BSP / 源码树 / OTA / 备份"
$hasUbuntu = $false
if ($distroNames -contains "Ubuntu-20.04") { $hasUbuntu = $true }
if ($hasUbuntu) {
    $treeCheck = (& wsl.exe -d Ubuntu-20.04 -u root bash -lc "for d in vendor/hys/laphone device/board/hys/laphone device/soc/sprd/uis7885; do test -d /home/ohos/ohos/$d || echo MISS:$d; done" 2>&1 | Out-String)
    if ($treeCheck -match "MISS:") {
        Write-Warn "WSL 源码树不完整，缺少："
        ($treeCheck -split "`r?`n" | Where-Object { $_ -match "MISS:" }) | ForEach-Object { Write-Info $_.Trim() }
    } else {
        Write-OK "WSL 源码树包含 vendor/hys/laphone、device/board/hys/laphone、device/soc/sprd/uis7885"
        $pre = (& wsl.exe -d Ubuntu-20.04 -u root python3 /mnt/d/ohos-device/scripts/check-prebuilts.py --root /home/ohos/ohos 2>&1 | Out-String)
        $preLines = @($pre -split "`r?`n" | Where-Object { $_ -match "缺失|全部找到|检查预编译" })
        $preLines | ForEach-Object { Write-Info $_.Trim() }
        if ($pre -notmatch "全部找到") { Write-Warn "闭源预编译文件未齐；跑 check-prebuilts.py 看清单" }
    }
} else {
    Write-Warn "源码树在 WSL（/home/ohos/ohos），本仓不放源码；BSP 公开在 Gitee，先装 WSL 并 sync"
}

$otaHits = @()
if (Test-Path -LiteralPath $BackupRoot) {
    $otaHits = @(Get-ChildItem -LiteralPath $BackupRoot -Recurse -File -Include *.zip,*.bin,*.img -ErrorAction SilentlyContinue | Select-Object -First 20)
}
if ($otaHits.Count -gt 0) {
    Write-OK ("备份/OTA 目录发现 " + $otaHits.Count + " 个候选文件:")
    $otaHits | ForEach-Object { Write-Info $_.FullName }
} else {
    Write-Miss ("未在 " + $BackupRoot + " 发现 OTA/镜像/备份文件")
}

$backupManifest = @()
if (Test-Path -LiteralPath $BackupRoot) {
    $backupManifest = @(Get-ChildItem -LiteralPath $BackupRoot -Recurse -File -Include SHA256SUMS.txt,manifest.txt -ErrorAction SilentlyContinue)
}
if ($backupManifest.Count -gt 0) { Write-OK "发现分区备份清单:"; $backupManifest | ForEach-Object { Write-Info $_.FullName } }
else { Write-Miss "未发现分区备份清单（刷机前必须先跑 scripts/backup-device.ps1）" }

Write-Section "结论"
Write-Info "应用链路：已具备（DevEco + API 10 SDK + hdc + 设备）"
Write-Info "系统构建：公开 BSP 是 4.0/API 10；可编译，但不是 API 26 升级"
Write-Info "API 26：仍需厂商 4.1/5.x/6.x BSP 或已签名 OTA"
Write-Info "下一步：1) 备份分区  2) 装 WSL2  3) sync 4.0 源码  4) 补闭源文件/编译  5) 问厂商新版本"
