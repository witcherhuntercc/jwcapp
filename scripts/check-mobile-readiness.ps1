<#
.SYNOPSIS
    出包前自检：把"Web 套壳后在手机上会出问题"的点全部列出来（容器侧 + 前端侧）。

.DESCRIPTION
    踩过的坑：WebView 容器只负责"显示网页"，不会自动处理状态栏/返回键/安全区。
    uni-app 这类 runtime 是内置这些能力的，Capacitor 是"最小内核 + 按需插件"，
    所以每次接新项目都要确认这几项，否则会出现"内容顶到状态栏""右滑直接退出"这类现象。

.PARAMETER ProjectDir
    Capacitor 工程根目录（含 package.json 与 android/）

.PARAMETER WebSource
    可选：前端源码目录（用于检查 viewport / safe-area / 100vh 等前端侧适配）

.EXAMPLE
    .\check-mobile-readiness.ps1 -ProjectDir D:\apps\my-app -WebSource D:\apps\my-app\web-src
#>
param(
    [Parameter(Mandatory = $true)][string]$ProjectDir,
    [string]$WebSource
)

$ErrorActionPreference = 'Stop'
$results = New-Object System.Collections.ArrayList
function Note($level, $item, $detail) {
    [void]$results.Add([pscustomobject]@{ 级别 = $level; 检查项 = $item; 说明 = $detail })
}

$project = (Resolve-Path -LiteralPath $ProjectDir).Path

# ---------------- 容器侧 ----------------
$pkgPath = Join-Path $project 'package.json'
if (-not (Test-Path $pkgPath)) { Write-Host "[X] 找不到 $pkgPath" -ForegroundColor Red; exit 1 }
$pkg = Get-Content $pkgPath -Raw -Encoding UTF8 | ConvertFrom-Json
$deps = @()
if ($pkg.dependencies) { $deps += $pkg.dependencies.PSObject.Properties.Name }
if ($pkg.devDependencies) { $deps += $pkg.devDependencies.PSObject.Properties.Name }

if ($deps -contains '@capacitor/app') {
    Note 'OK' '返回手势/退出确认' '已装 @capacitor/app'
} else {
    Note 'FAIL' '返回手势/退出确认' '未装 @capacitor/app → 右滑/返回键会直接退出应用，且无"再按一次退出"提示'
}

if ($deps -contains '@capacitor/status-bar') {
    Note 'OK' '状态栏策略' '已装 @capacitor/status-bar'
} else {
    Note 'WARN' '状态栏策略' '未装 @capacitor/status-bar → 内容可能绘制到状态栏下方（Android 15+ 强制 edge-to-edge 时尤其明显）'
}

foreach ($opt in 'keyboard','splash-screen','haptics') {
    if ($deps -contains "@capacitor/$opt") { Note 'OK' "可选插件 @capacitor/$opt" '已装' }
    else { Note 'INFO' "可选插件 @capacitor/$opt" '未装（键盘遮挡/白屏/震动手感相关，按需）' }
}

# 加载模式
$cfgPath = Join-Path $project 'capacitor.config.json'
$remoteUrl = $null
if (Test-Path $cfgPath) {
    try { $cfg = Get-Content $cfgPath -Raw -Encoding UTF8 | ConvertFrom-Json } catch { $cfg = $null }
    if ($cfg -and $cfg.server -and $cfg.server.url) { $remoteUrl = $cfg.server.url }
}
if ($remoteUrl) {
    Note 'INFO' '打包模式' "远程 URL：$remoteUrl （前端改完即刻生效，但必须联网且服务在线；官方定位为开发/试验用途）"
} else {
    Note 'INFO' '打包模式' '内置产物（离线可用；每次前端更新需重新发版）'
}

# targetSdk → 是否会被强制 edge-to-edge
$varsPath = Join-Path $project 'android\variables.gradle'
if (Test-Path $varsPath) {
    $m = Select-String -Path $varsPath -Pattern 'targetSdkVersion\s*=\s*(\d+)' | Select-Object -First 1
    if ($m) {
        $sdk = [int]$m.Matches[0].Groups[1].Value
        if ($sdk -ge 35) { Note 'WARN' "targetSdk=$sdk" 'Android 15+ 会强制 edge-to-edge（系统行为，原生 App 同样如此）→ 必须自己处理 insets：容器侧 StatusBar 或前端 safe-area' }
        else { Note 'OK' "targetSdk=$sdk" '未触发强制 edge-to-edge' }
    }
} else {
    Note 'FAIL' 'Android 工程' "未找到 $varsPath（是否还没执行 npx cap add android？）"
}

# ---------------- 前端侧 ----------------
if ($WebSource) {
    $web = (Resolve-Path -LiteralPath $WebSource).Path
    $indexHtml = Join-Path $web 'index.html'
    if (Test-Path $indexHtml) {
        $html = Get-Content $indexHtml -Raw -Encoding UTF8
        if ($html -match 'viewport-fit=cover') { Note 'OK' 'viewport 元信息' '已含 viewport-fit=cover' }
        else { Note 'FAIL' 'viewport 元信息' '缺少 viewport-fit=cover → env(safe-area-inset-*) 不会生效' }
    } else {
        Note 'WARN' 'viewport 元信息' "未找到 $indexHtml（若前端项目在别处，把 -WebSource 指到它的根目录）"
    }

    $srcDir = if (Test-Path (Join-Path $web 'src')) { Join-Path $web 'src' } else { $web }
    $safe = (rg -o --no-heading 'safe-area-inset' $srcDir 2>$null | Measure-Object).Count
    $vh   = (rg -o --no-heading '100vh'        $srcDir 2>$null | Measure-Object).Count
    $dvh  = (rg -o --no-heading '100dvh'       $srcDir 2>$null | Measure-Object).Count
    $tap  = (rg -o --no-heading 'tap-highlight-color' $srcDir 2>$null | Measure-Object).Count

    if ($safe -gt 0) { Note 'OK'   '安全区变量'   "env(safe-area-inset-*) 使用 $safe 处" }
    else             { Note 'WARN' '安全区变量'   '全项目未使用 env(safe-area-inset-*) → 刘海/状态栏/手势条可能遮挡内容' }

    if ($vh -gt 0) { Note 'WARN' '整屏高度用法' "100vh 出现 $vh 处（WebView 里 100vh 含状态栏高度，易顶出可视区）→ 建议改 100dvh" }
    else           { Note 'OK'   '整屏高度用法' '未使用 100vh' }
    if ($dvh -gt 0) { Note 'OK' 'dvh 用法' "100dvh 使用 $dvh 处" }

    if ($tap -gt 0) { Note 'OK'   '点击高亮' '已处理 -webkit-tap-highlight-color' }
    else            { Note 'INFO' '点击高亮' '未处理（Android 上点击会有灰块，可选）' }
}

# ---------------- 输出 ----------------
Write-Host ''
Write-Host ('=== 移动端就绪度自检：' + $project + ' ===') -ForegroundColor Cyan
$results | Format-Table -AutoSize

$fail = @($results | Where-Object { $_.级别 -eq 'FAIL' }).Count
$warn = @($results | Where-Object { $_.级别 -eq 'WARN' }).Count
Write-Host ('结论：FAIL ' + $fail + ' 项，WARN ' + $warn + ' 项') -ForegroundColor $(if ($fail -gt 0) { 'Red' } elseif ($warn -gt 0) { 'Yellow' } else { 'Green' })
if ($fail -gt 0) { Write-Host '建议：先补齐 FAIL 项再出包 —— 详见 docs/06-移动端适配与容器能力.md' -ForegroundColor Yellow }
elseif ($warn -gt 0) { Write-Host '可以出包；WARN 项建议尽快补（现象是"内容顶到状态栏/高度异常"）' -ForegroundColor Yellow }
else { Write-Host '可以出包：容器侧与前端侧的关键项都已就绪' -ForegroundColor Green }
