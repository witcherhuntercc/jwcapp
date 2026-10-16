<#
.SYNOPSIS
    一键构建 Capacitor Android debug APK（通用版，任意 Capacitor 工程可用）。

.DESCRIPTION
    本脚本固化的是"本机实测能跑通的那套组合"，避免重复踩坑：
      - JAVA_HOME 必须 JDK 21（Capacitor 8.5.3 的 android 库 sourceCompatibility=VERSION_21；
        JDK 17 会报 "错误: 无效的源发行版：21"）
      - ANDROID_HOME 指向本机 Android SDK（需含 platforms/build-tools 36）
      - Gradle 发行包走腾讯镜像、Maven 走阿里镜像（这两个配置在 android 工程里，不在本脚本）
    环境变量只作用于当前进程，不写系统、不影响其它项目。

.PARAMETER ProjectDir
    Capacitor 工程根目录（含 package.json 与 android/），默认当前目录

.PARAMETER SkipSync
    跳过 npx cap sync（前端产物没变时可省几秒）

.PARAMETER JavaHome / AndroidSdk / NodeDir
    允许覆盖工具链路径（换机器时用）

.EXAMPLE
    .\build-apk.ps1 -ProjectDir D:\apps\my-app

.EXAMPLE
    .\build-apk.ps1 -ProjectDir . -SkipSync
#>
param(
    [string]$ProjectDir = '.',
    [switch]$SkipSync,
    # 工具链路径：优先参数 / 环境变量，其次自动探测工作区同级的 jwcenv（G17 路径零硬编码）
    [string]$JavaHome   = $env:JWC_JDK21,
    [string]$AndroidSdk = $(if ($env:ANDROID_HOME) { $env:ANDROID_HOME } else { $env:ANDROID_SDK_ROOT }),
    [string]$NodeDir    = $env:JWC_NODE
)

$ErrorActionPreference = 'Stop'

function Fail($msg, $hint) {
    Write-Host "[X] $msg" -ForegroundColor Red
    if ($hint) { Write-Host "    $hint" -ForegroundColor Yellow }
    exit 1
}

# ---- 工具链自动探测：<工作区>\jwcenv\{jdk21,nodejs}；找不到则由下方校验报错并给提示 ----
$jwcenv = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'jwcenv'
if (-not $JavaHome -and (Test-Path (Join-Path $jwcenv 'jdk21')))  { $JavaHome = Join-Path $jwcenv 'jdk21' }
if (-not $NodeDir  -and (Test-Path (Join-Path $jwcenv 'nodejs'))) { $NodeDir  = Join-Path $jwcenv 'nodejs' }

$project = (Resolve-Path -LiteralPath $ProjectDir).Path
$androidDir = Join-Path $project 'android'

if (-not (Test-Path $JavaHome))   { Fail "JDK 21 不存在：$JavaHome" "见 docs/02-环境清单与踩坑.md 第一章；华为云镜像下载 OpenJDK 21" }
if (-not (Test-Path $AndroidSdk)) { Fail "Android SDK 不存在：$AndroidSdk" "见 docs/02 第一章" }
if (-not (Test-Path $androidDir)) { Fail "没找到 Capacitor 原生工程：$androidDir" "先在工程根目录执行 npx cap add android（见 docs/03）" }

$env:JAVA_HOME = $JavaHome
$env:ANDROID_HOME = $AndroidSdk
$env:ANDROID_SDK_ROOT = $AndroidSdk
$env:Path = "$JavaHome\bin;$AndroidSdk\platform-tools;$NodeDir;" + $env:Path

if (Test-Path (Join-Path $JavaHome 'bin\javac.exe')) {
    Write-Host ('JDK : ' + (& (Join-Path $JavaHome 'bin\javac.exe') -version 2>&1)) -ForegroundColor DarkGray
}
Write-Host ('SDK : ' + $AndroidSdk) -ForegroundColor DarkGray
Write-Host ('工程: ' + $project) -ForegroundColor DarkGray

if (-not $SkipSync) {
    $npx = Join-Path $NodeDir 'npx.cmd'
    if (Test-Path $npx) {
        Write-Host '[1/2] npx cap sync android ...' -ForegroundColor Cyan
        Push-Location $project
        & $npx cap sync android | Select-Object -Last 4
        Pop-Location
    } else {
        Write-Host "[!] 跳过 cap sync（找不到 $npx）" -ForegroundColor Yellow
    }
} else {
    Write-Host '[1/2] 已跳过 cap sync（-SkipSync）' -ForegroundColor DarkGray
}

Write-Host '[2/2] gradlew assembleDebug ...' -ForegroundColor Cyan
Push-Location $androidDir
& .\gradlew.bat assembleDebug | Select-Object -Last 6
$exit = $LASTEXITCODE
Pop-Location

$apk = Join-Path $androidDir 'app\build\outputs\apk\debug\app-debug.apk'
if ($exit -ne 0 -or -not (Test-Path $apk)) {
    Fail '构建失败或未产出 APK' '看上面的 Gradle 输出；常见原因见 docs/02-环境清单与踩坑.md'
}

$info = Get-Item $apk
Write-Host ''
Write-Host '[OK] 构建成功' -ForegroundColor Green
Write-Host ('  APK    : ' + $info.FullName)
Write-Host ('  大小   : ' + [math]::Round($info.Length / 1MB, 2) + ' MB')
Write-Host ('  时间   : ' + $info.LastWriteTime)
Write-Host ('  SHA256 : ' + (Get-FileHash $apk -Algorithm SHA256).Hash)
Write-Host ''
Write-Host '装到真机（USB 调试已开、已授权）：' -ForegroundColor DarkGray
Write-Host ('  ' + (Join-Path $AndroidSdk 'platform-tools\adb.exe') + ' install -r "' + $apk + '"') -ForegroundColor DarkGray
