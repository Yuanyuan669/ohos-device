#Requires -Version 5.1
<#
.SYNOPSIS
  只读备份 LHT16 的关键分区（boot 链、NV/校准、system/vendor/product 等）。
.DESCRIPTION
  通过 hdc + dd 读取 /dev/block/by-name/<partition>，先落到设备 /data/local/tmp，
  再拉回 PC，计算 SHA256，生成 manifest。不会写任何分区，不会备份 112 GB 的 userdata。
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File scripts/backup-device.ps1 -OutDir $env:OHOS_BACKUP\LHT16-20261115
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File scripts/backup-device.ps1 -OutDir $env:OHOS_BACKUP\LHT16-20261115 -Profile all -Yes
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$OutDir,

    [string]$Hdc = "",
    [string]$DeviceSerial = "",

    [ValidateSet("critical", "all")]
    [string]$Profile = "critical",

    [string[]]$Only = @(),

    [switch]$Yes,
    [switch]$KeepDeviceCopies,
    [switch]$DryRun
)

if (-not $Hdc) {
    $Hdc = if ($env:OHOS_HDC) { $env:OHOS_HDC }
    elseif ($env:OHOS_TOOLS) { Join-Path $env:OHOS_TOOLS 'sdk\openharmony\toolchains\hdc.exe' }
    else { '' }
}

$ErrorActionPreference = "Stop"

function Fail($msg) {
    Write-Host ("[FAIL] " + $msg) -ForegroundColor Red
    exit 1
}

function Write-Step($msg) { Write-Host ("[..] " + $msg) -ForegroundColor Cyan }
function Write-OK($msg) { Write-Host ("[OK] " + $msg) -ForegroundColor Green }
function Write-Warn($msg) { Write-Host ("[WARN] " + $msg) -ForegroundColor Yellow }

if (-not (Test-Path -LiteralPath $Hdc -PathType Leaf)) {
    Fail ("hdc 不存在: " + $Hdc)
}

if (-not $DeviceSerial) {
    $targets = @(& $Hdc list targets 2>&1 | ForEach-Object { $_.ToString().Trim() } | Where-Object { $_ -and $_ -notmatch "Empty|error|fail" })
    if ($targets.Count -eq 0) { Fail "hdc 未列出设备，请检查 USB/调试授权" }
    $DeviceSerial = $targets[0]
}
Write-OK ("设备: " + $DeviceSerial)

$critical = @(
    "boot_a", "boot_b",
    "vendor_boot_a", "vendor_boot_b",
    "vendor_boot_updater_a", "vendor_boot_updater_b",
    "dtb_a", "dtb_b", "dtbo_a", "dtbo_b",
    "uboot_a", "uboot_b", "sml_a", "sml_b",
    "trustos_a", "trustos_b", "teecfg_a", "teecfg_b",
    "misc", "miscdata", "persist", "prodnv",
    "nr_fixnv1_a", "nr_fixnv1_b", "nr_fixnv2_a", "nr_fixnv2_b",
    "nr_modem_a", "nr_modem_b", "nr_phy_a", "nr_phy_b",
    "nr_deltanv_a", "nr_deltanv_b", "nr_runtimenv1", "nr_runtimenv2",
    "system", "vendor", "product", "sys_prod",
    "updater_a", "updater_b", "odmko_a", "odmko_b",
    "l_agdsp_a", "l_agdsp_b", "pm_sys_a", "pm_sys_b",
    "ch_sys_a", "ch_sys_b", "ise_a", "ise_b", "isedata", "calinv"
)

$extra = @(
    "metadata", "blackbox", "sysdumpdb",
    "logo", "fbootlogo", "uboot_log", "socko_b"
)

$partitions = @($critical)
if ($Profile -eq "all") { $partitions += $extra }
if ($Only.Count -gt 0) { $partitions = @($Only) }
$partitions = $partitions | Select-Object -Unique

# 设备侧空间检查（/data 需要约 8 GB 临时空间）
$df = (& $Hdc -t $DeviceSerial shell "df -k /data/local/tmp" 2>&1 | Out-String)
$availKb = $null
foreach ($line in ($df -split "`r?`n")) {
    if ($line -match "^\S+\s+\d+\s+\d+\s+(\d+)\s+\d+%\s+") {
        $availKb = [int64]$Matches[1]
        break
    }
}
if ($availKb -ne $null) {
    $availGb = [math]::Round($availKb / 1024 / 1024, 1)
    Write-OK ("设备 /data 可用: " + $availGb + " GB")
    if ($availGb -lt 10) { Fail "设备 /data 可用空间 < 10 GB，先清理再备份" }
} else {
    Write-Warn "未能解析设备 /data 空间，请自行确认至少 10 GB 可用"
}

if (-not (Test-Path -LiteralPath $OutDir)) {
    New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
}
$OutDir = (Resolve-Path -LiteralPath $OutDir).Path
$driveName = [System.IO.Path]::GetPathRoot($OutDir).Substring(0, 1)
$pcFree = (Get-PSDrive -Name $driveName -ErrorAction SilentlyContinue)
if ($pcFree) {
    $pcFreeGb = [math]::Round($pcFree.Free / 1GB, 1)
    Write-OK ("PC 输出盘可用: " + $pcFreeGb + " GB")
    if ($pcFreeGb -lt 10) { Fail "PC 输出盘可用空间 < 10 GB" }
}

# 检查分区是否存在
$checkCmd = "for p in " + ($partitions -join " ") + "; do [ -e /dev/block/by-name/$p ] || echo MISSING:$p; done"
$check = (& $Hdc -t $DeviceSerial shell $checkCmd 2>&1 | Out-String)
$missing = @()
foreach ($line in ($check -split "`r?`n")) {
    if ($line -match "MISSING:(\S+)") { $missing += $Matches[1] }
}
if ($missing.Count -gt 0) {
    Write-Warn ("设备上不存在的分区（将跳过）: " + ($missing -join ", "))
    $partitions = @($partitions | Where-Object { $missing -notcontains $_ })
}
if ($partitions.Count -eq 0) { Fail "没有可备份的分区" }

Write-Host ""
Write-Host ("将只读备份 " + $partitions.Count + " 个分区到: " + $OutDir)
Write-Host ("Profile: " + $Profile + "；不包含 userdata（112 GB）")
if (-not $Yes -and -not $DryRun) {
    $answer = Read-Host "输入 YES 继续（只读操作，但请保持供电和连接）"
    if ($answer -ne "YES") { Fail "用户取消" }
}

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$remoteDir = "/data/local/tmp/ohos-backup-" + $stamp

if ($DryRun) {
    Write-Host ""
    Write-Host "[DRY RUN] 不会执行以下命令，只打印计划：" -ForegroundColor Yellow
    Write-Host ("  mkdir -p " + $remoteDir)
    foreach ($p in $partitions) {
        Write-Host ("  dd if=/dev/block/by-name/" + $p + " of=" + $remoteDir + "/" + $p + ".img bs=1M")
        Write-Host ("  hdc file recv " + $remoteDir + "/" + $p + ".img " + (Join-Path $OutDir ($p + ".img")))
    }
    Write-Host ("  rm -rf " + $remoteDir)
    exit 0
}
& $Hdc -t $DeviceSerial shell ("mkdir -p " + $remoteDir) | Out-Null
if ($LASTEXITCODE -ne 0) { Fail "无法在设备上创建临时目录" }

$sumPath = Join-Path $OutDir "SHA256SUMS.txt"
$manifestPath = Join-Path $OutDir "manifest.txt"
"# LHT16 partition backup  " + (Get-Date -Format "s") | Set-Content -LiteralPath $sumPath -Encoding ASCII

# 记录版本/slot/分区表
$manifest = New-Object System.Collections.Generic.List[string]
$manifest.Add("# LHT16 backup manifest")
$manifest.Add("date=" + (Get-Date -Format "s"))
$manifest.Add("device=" + $DeviceSerial)
$manifest.Add("hdc=" + $Hdc)
$manifest.Add("profile=" + $Profile)
$manifest.Add("")
$manifest.Add("## params")
foreach ($key in @(
    "const.ohos.fullname", "const.ohos.apiversion", "const.ohos.releasetype",
    "const.product.model", "const.product.software.version", "const.product.oharm.version",
    "const.ohos.version.security_patch", "const.debuggable", "const.secure"
)) {
    $v = (& $Hdc -t $DeviceSerial shell ("param get " + $key) 2>&1 | Out-String).Trim()
    $manifest.Add($key + "=" + $v)
}
$manifest.Add("")
$manifest.Add("## cmdline")
$manifest.Add((& $Hdc -t $DeviceSerial shell "cat /proc/cmdline" 2>&1 | Out-String).Trim())
$manifest.Add("")
$manifest.Add("## partitions")
foreach ($p in $partitions) {
    $size = (& $Hdc -t $DeviceSerial shell ("blockdev --getsize64 /dev/block/by-name/" + $p) 2>&1 | Out-String).Trim()
    $manifest.Add($p + "=" + $size)
}
$manifest | Set-Content -LiteralPath $manifestPath -Encoding UTF8

$done = 0
$failed = @()
foreach ($p in $partitions) {
    Write-Step ("备份 " + $p + " (" + ($done + 1) + "/" + $partitions.Count + ")")
    $remote = $remoteDir + "/" + $p + ".img"
    $local = Join-Path $OutDir ($p + ".img")

    $expectedRaw = (& $Hdc -t $DeviceSerial shell ("blockdev --getsize64 /dev/block/by-name/" + $p) 2>&1 | Out-String).Trim()
    $expected = $null
    if ($expectedRaw -match "^\d+$") { $expected = [int64]$expectedRaw }

    $dd = (& $Hdc -t $DeviceSerial shell ("dd if=/dev/block/by-name/" + $p + " of=" + $remote + " bs=1M") 2>&1 | Out-String)
    if ($dd -match "No such|Permission denied|cannot open|error") {
        Write-Warn ($p + " 读取失败: " + $dd.Trim())
        $failed += $p
        continue
    }

    if (Test-Path -LiteralPath $local) { Remove-Item -LiteralPath $local -Force }
    & $Hdc -t $DeviceSerial file recv $remote $local | Out-Null
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $local)) {
        Write-Warn ($p + " 拉回失败")
        $failed += $p
        continue
    }

    if ($expected -ne $null) {
        $actual = (Get-Item -LiteralPath $local).Length
        if ($actual -ne $expected) {
            Write-Warn ($p + " 大小不一致: 期望 " + $expected + " 字节，实际 " + $actual + " 字节")
            $failed += $p
            continue
        }
    }

    $hash = (Get-FileHash -LiteralPath $local -Algorithm SHA256).Hash.ToLower()
    $sizeMb = [math]::Round((Get-Item -LiteralPath $local).Length / 1MB, 1)
    ($hash + "  " + $p + ".img") | Add-Content -LiteralPath $sumPath -Encoding ASCII
    Write-OK ($p + ".img  " + $sizeMb + " MB  " + $hash.Substring(0, 16) + "...")
    $done++

    if (-not $KeepDeviceCopies) {
        & $Hdc -t $DeviceSerial shell ("rm -f " + $remote) | Out-Null
    }
}

if (-not $KeepDeviceCopies) {
    & $Hdc -t $DeviceSerial shell ("rmdir " + $remoteDir + " 2>/dev/null") | Out-Null
}

Write-Host ""
Write-OK ("完成: " + $done + "/" + $partitions.Count + " 个分区")
Write-Host ("输出目录: " + $OutDir)
Write-Host ("校验文件: " + $sumPath)
Write-Host ("清单文件: " + $manifestPath)
if ($failed.Count -gt 0) {
    Write-Warn ("失败/跳过: " + ($failed -join ", "))
    exit 2
}
Write-Host ""
Write-Host "下一步：把整个目录复制到另一块物理磁盘/离线存储；未确认备份可读之前不要刷机。" -ForegroundColor Yellow
