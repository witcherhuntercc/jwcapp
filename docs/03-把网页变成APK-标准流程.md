# 把任意网页项目变成 APK（标准流程）

> 目标：**前端零改造**——不改你的业务代码，用容器把它包成可安装的 App。
> 全程约 15 分钟（工具链就绪的前提下）。

---

## 第 0 步：前提检查

```powershell
# 1) JDK 21（必须 21，见 02-坑1）
& 'E:\tools\jdk-21\jdk-21.0.2\bin\javac.exe' -version     # 期望 javac 21.x

# 2) Android SDK 要有 platforms;android-36 与 build-tools;36.0.0
Get-ChildItem 'E:\tools\Android\Sdk\platforms' | Select-Object -ExpandProperty Name
Get-ChildItem 'E:\tools\Android\Sdk\build-tools' | Select-Object -ExpandProperty Name
# 缺则装（dl.google.com 很快）：
#   E:\tools\Android\Sdk\cmdline-tools\latest\bin\sdkmanager.bat "platforms;android-36" "build-tools;36.0.0"

# 3) Node 18+
& 'E:\mywork\jwcenv\nodejs\node.exe' --version
```

---

## 第 1 步：建容器（与你的前端项目分开）

```powershell
mkdir my-app ; cd my-app
npm init -y
npm i @capacitor/core @capacitor/cli @capacitor/android --registry=https://registry.npmmirror.com
npx cap init "应用名称" "com.你的.包名" --web-dir=www
```

---

## 第 2 步：决定"喂什么给容器"

### 模式 A：内置产物（离线可用，更新要发版）

```powershell
# 在你的前端项目里构建
cd <前端项目> ; npm run build
# 把产物拷进容器
robocopy <前端项目>\dist  <容器>\www  /E
```

> 注意：产物里对 API 的引用必须是**同源相对路径**（如 `/api`），否则手机上会指向 localhost。
> 检查方法：`Select-String -Path dist\assets\*.js -Pattern 'baseURL:"[^"]*"'`

### 模式 B：远程 URL（前端改完即刻生效，不用重发 APK）

编辑 `capacitor.config.json`：

```json
{
  "appId": "com.你的.包名",
  "appName": "应用名称",
  "webDir": "www",
  "server": { "url": "https://你的域名", "androidScheme": "https" }
}
```

> `webDir` 里的产物仍会打进 APK 作兜底，但 **`server.url` 存在时以远程为准**。
> Capacitor 官方把 `server.url` 定位为开发/试验用途；正式发布前重新评估（离线、商城合规）。

---

## 第 3 步：生成原生工程

```powershell
npx cap add android
```

**1 秒**完成，并自动把 `www` 拷进 `android/app/src/main/assets/public`。

---

## 第 4 步：改三处配置（否则构建会慢到不可用或直接失败）

1. **Gradle 镜像** —— `android/gradle/wrapper/gradle-wrapper.properties`：
   `distributionUrl` 指向腾讯镜像，官方 URL 注释保留。
2. **Maven 镜像** —— `android/build.gradle` 的两处 `repositories`：
   阿里镜像放前面，`google()` / `mavenCentral()` 保留在后面。
3. **SDK 版本** —— 确认 `android/variables.gradle` 的 `compileSdkVersion` 有对应平台已安装（新模板是 36）。

样板文件在 [../template/](../template/)。

---

## 第 5 步：构建

```powershell
..\jwcapp\scripts\build-apk.ps1 -ProjectDir .
# 或手动：
$env:JAVA_HOME='E:\tools\jdk-21\jdk-21.0.2'
$env:ANDROID_HOME='E:\tools\Android\Sdk'
cd android ; .\gradlew.bat assembleDebug
```

产物：`android\app\build\outputs\apk\debug\app-debug.apk`

---

## 第 6 步：装到真机

```powershell
& 'E:\tools\Android\Sdk\platform-tools\adb.exe' devices          # 确认设备已连接并授权
& 'E:\tools\Android\Sdk\platform-tools\adb.exe' install -r "android\app\build\outputs\apk\debug\app-debug.apk"
# 或者直接把 APK 拷到手机点安装
```

---

## 第 7 步：真机验收清单

- [ ] 能启动，图标与名称正确
- [ ] **登录/注册能成功**（若报 403 → 见 02-坑4：CORS 白名单）
- [ ] 导航跳转正常；**返回键**行为符合预期（默认"有历史就回退、无历史退出"；要自定义需加 `@capacitor/app` 的 `backButton` 监听）
- [ ] 文件上传能调起系统选择器
- [ ] 图片/头像/附件能显示（若裂图 → 见 02-坑5）
- [ ] 手机样式适配无错位
- [ ] 页面显示"安全上下文=是"（HTTPS 下麦克风等能力才可用）
- [ ] 断网/服务停时表现可接受（远程 URL 模式下会显示错误页——这是该模式的固有代价）

---

## 第 8 步：后续

| 想做的事 | 怎么做 |
|---------|--------|
| 加推送 | `@capacitor/push-notifications`（Android 走 FCM，需要 `google-services.json`）；国内先比较厂商通道送达率 |
| 加生物识别 | `@capacitor/biometric-auth` |
| 正式发布 | 生成签名 keystore（`keytool`）→ `assembleRelease`；重新评估"内置产物 vs 远程内容"与商店合规 |
| 前端改了要更新 | 远程 URL 模式：直接改线上即可；内置模式：重新 `cap sync` + 重打包 |
