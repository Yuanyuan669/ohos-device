#Requires -Version 5.1
<#
.SYNOPSIS
  安装 WSL2 + Ubuntu 20.04，并把发行版放到 D 盘。
.DESCRIPTION
  需要管理员权限。会启用 WSL/虚拟机平台，安装 Canonical.Ubuntu.2004，
  把发行版移动到 D:\wsl\Ubuntu-20.04，并写 .wslconfig（12 GB 内存 / 16 GB swap）。
  不会自动重启；如果 DISM 返回 3010，请重启后重新运行本脚本。
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File scripts/setup-wsl.ps1
#>
[CmdletBinding()]
param(
    [string]$Distro = "Ubuntu-20.04",
    [string]$InstallRoot = "D:\wsl\Ubuntu-20.04",
    [int]$MemoryGB = 12,
    [int]$SwapGB = 16,
    [int]$Processors = 12,
    [switch]$SkipInstall
)

$ErrorActionPreference = "Stop"

function Fail($msg) { Write-Host ("[FAIL] " + $msg) -ForegroundColor Red; exit 1 }
function Write-Step($msg) { Write-Host ("[..] " + $msg) -ForegroundColor Cyan }
function Write-OK($msg) { Write-Host ("[OK] " + $msg) -ForegroundColor Green }
function Write-Warn($msg) { Write-Host ("[WARN] " + $msg) -ForegroundColor Yellow }

try {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    $OutputEncoding = [System.Text.Encoding]::UTF8
} catch { }

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Fail "需要管理员权限。请以管理员身份打开 PowerShell，再运行本脚本。"
}

Write-Step "启用 WSL / 虚拟机平台（已启用则跳过）"
$reboot = $false
foreach ($feature in @("Microsoft-Windows-Subsystem-Linux", "VirtualMachinePlatform")) {
    $out = & dism.exe /online /enable-feature /featurename:$feature /all /norestart 2>&1 | Out-String
    if ($LASTEXITCODE -eq 3010) { $reboot = $true }
    elseif ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne 0x800f0906) {
        Write-Warn ("DISM " + $feature + " 返回 " + $LASTEXITCODE)
        Write-Warn $out.Trim()
    } else {
        Write-OK ($feature + " 已启用")
    }
}

Write-Step "更新 WSL"
& wsl.exe --update 2>&1 | Out-String | Write-Host
if ($LASTEXITCODE -ne 0) { Write-Warn "wsl --update 失败；稍后可从 Microsoft Store 更新 WSL" }

& wsl.exe --set-default-version 2 2>&1 | Out-String | Write-Host
if ($LASTEXITCODE -ne 0) { Write-Warn "设置默认 WSL2 失败；重启后重试" }

if ($reboot) {
    Write-Warn "WSL/虚拟机平台刚刚启用，需要重启 Windows 才能继续。"
    Write-Host ""
    Write-Host "重启后重新运行：" -ForegroundColor Yellow
    Write-Host ("  powershell -ExecutionPolicy Bypass -File " + $PSCommandPath)
    exit 0
}

if (-not $SkipInstall) {
    Write-Step "安装 Ubuntu 20.04（winget）"
    $winget = Get-Command winget.exe -ErrorAction SilentlyContinue
    if (-not $winget) { Fail "未找到 winget；请从 Microsoft Store 安装 Ubuntu 20.04 LTS 后重跑 -SkipInstall" }

    & winget.exe install --id Canonical.Ubuntu.2004 --exact --accept-source-agreements --accept-package-agreements 2>&1 | Out-String | Write-Host
    if ($LASTEXITCODE -ne 0) {
        Write-Warn "winget 安装返回 $LASTEXITCODE；如果商店已安装可继续"
    }

    Write-Step "初始化 Ubuntu-20.04（root，无需交互）"
    $launcher = Get-Command ubuntu2004.exe -ErrorAction SilentlyContinue
    if ($launcher) {
        & $launcher.Source install --root 2>&1 | Out-String | Write-Host
    } else {
        Write-Warn "未找到 ubuntu2004.exe；请从开始菜单启动一次 Ubuntu 20.04 完成初始化"
    }
}

$distros = (& wsl.exe -l -q 2>&1 | Out-String)
if ($distros -notmatch [regex]::Escape($Distro)) {
    Write-Warn ("WSL 中没有找到发行版 " + $Distro + "。请手动启动一次 Ubuntu 20.04，然后重跑：")
    Write-Host ("  powershell -ExecutionPolicy Bypass -File " + $PSCommandPath + " -SkipInstall")
    exit 1
}
Write-OK ("发行版已注册: " + $Distro)

Write-Step "把发行版移动到 D 盘: $InstallRoot"
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $InstallRoot) | Out-Null
$moved = $false
& wsl.exe --manage $Distro --move $InstallRoot 2>&1 | Out-String | Write-Host
if ($LASTEXITCODE -eq 0) {
    Write-OK "wsl --manage --move 成功"
    $moved = $true
} else {
    Write-Warn "wsl --manage --move 不可用，改用 export/import（耗时较长，请勿中断）"
    $tar = Join-Path (Split-Path -Parent $InstallRoot) ($Distro + ".tar")
    & wsl.exe --export $Distro $tar 2>&1 | Out-String | Write-Host
    if ($LASTEXITCODE -ne 0) { Fail "wsl --export 失败" }
    & wsl.exe --unregister $Distro 2>&1 | Out-String | Write-Host
    if ($LASTEXITCODE -ne 0) { Fail "wsl --unregister 失败" }
    & wsl.exe --import $Distro $InstallRoot $tar --version 2 2>&1 | Out-String | Write-Host
    if ($LASTEXITCODE -ne 0) { Fail "wsl --import 失败" }
    Remove-Item -LiteralPath $tar -Force -ErrorAction SilentlyContinue
    Write-OK "export/import 完成（默认用户会由 setup-ubuntu.sh 创建）"
    $moved = $true
}

Write-Step "写 .wslconfig"
$wslDir = Split-Path -Parent $InstallRoot
New-Item -ItemType Directory -Force -Path $wslDir | Out-Null
$configPath = Join-Path $env:USERPROFILE ".wslconfig"
if (Test-Path -LiteralPath $configPath) {
    $bak = $configPath + ".bak." + (Get-Date -Format "yyyyMMdd-HHmmss")
    Copy-Item -LiteralPath $configPath -Destination $bak
    Write-Warn ("已备份原 .wslconfig 到 " + $bak)
}
$swapPath = (Join-Path $wslDir "swap.vhdx") -replace "\\", "\\"
$config = @"
[wsl2]
memory=${MemoryGB}GB
processors=$Processors
swap=${SwapGB}GB
swapFile=$swapPath
localhostForwarding=true
"@
Set-Content -LiteralPath $configPath -Value $config -Encoding ASCII
Write-OK ("写入 " + $configPath + "（memory=" + $MemoryGB + "GB, swap=" + $SwapGB + "GB, processors=" + $Processors + "）")

Write-Host ""
Write-OK "WSL2 基础环境就绪"
Write-Host "下一步（在普通 PowerShell 里）：" -ForegroundColor Yellow
Write-Host ("  wsl -d " + $Distro + " -u root bash /mnt/d/ohos-device/scripts/setup-ubuntu.sh --sync")
Write-Host "如果 WSL 提示需要重启，先重启 Windows，再重跑本脚本或直接执行上面的命令。"
