# jwcapp —— 网页转 App / 移动端打包知识库

把**现有的网页项目**（Vue/React/纯静态 SPA）打包成**可安装的手机 App**，以及围绕这件事的工具链、脚本、踩坑记录。

> **定位**：个人知识与技能库。**不绑定任何具体业务项目**——换项目、换机器，照 `docs/03` 走一遍即可。
> **当前验证过的路线**：Capacitor + Android（本机已完整跑通并装到真机）。

---

## 本库采用的方案（决策记录）

**Capacitor** —— 上游 `ionic-team/capacitor`，实测版本 **8.5.3**。本仓库的脚本、模板、文档全部围绕这一条路线。

| 项 | 值 |
|----|-----|
| 上游仓库 | https://github.com/ionic-team/capacitor |
| 实测版本 | `@capacitor/core` = `@capacitor/cli` = `@capacitor/android` = **8.5.3** |
| 参考源码 | `E:\myprojects\web2app-eval\capacitor`（`--depth 1` 浅克隆，仅作对照） |
| 未被采用的三个 | **Tauri v2**：本机无 Rust/NDK，收益（体积）不匹配诉求；**Bubblewrap（TWA）**：由设备 Chrome 渲染 + 依赖 Google Play，国内机型结构性不适用；**HBuilderX + DCloud**：不是开源项目、封闭生态，但作为"当天出包"的备选保留 |

> 三个未采用的候选源码仍留在 `E:\myprojects\web2app-eval`（浅克隆）供查阅；**本库只维护 Capacitor 路线**，不维护它们的构建配方。

---

## 30 秒结论

| 你的需求 | 用哪个 | 为什么 |
|---------|--------|--------|
| 国内用户、要能装、要能扩原生能力（推送/生物识别） | **Capacitor** | 国际主流、开源、插件生态最全；只差 Android 工具链 |
| 今天就要一个包、不想装任何东西 | **HBuilder X + DCloud 离线 SDK** | 工具链在 `E:\tools` 已就绪（本机验证过） |
| 追求最小体积 | Tauri v2 Mobile | 需 Rust + NDK，本机没有；收益不匹配"省事"诉求 |
| 用户主要在海外 + Google Play 分发 | Bubblewrap（TWA） | 国内机型缺 Chrome/Play，**结构性不适用** |

详细对比与依据见 [docs/01-选型与结论.md](docs/01-选型与结论.md)。

---

## 仓库结构

| 路径 | 内容 |
|------|------|
| `docs/01-选型与结论.md` | 四个候选方案的对比、实测数据、为什么选 Capacitor（含 TWA 排除依据） |
| `docs/02-环境清单与踩坑.md` | 本机工具链的确切路径 + 全部踩过的坑（JDK/Gradle镜像/CORS/MinIO/workbox…） |
| `docs/03-把网页变成APK-标准流程.md` | **新项目接入手册**：从零到真机可装，一条条命令 |
| `docs/04-实测记录.md` | 首次构建与"手机看到真实应用"的完整落地记录（含验证证据） |
| `docs/05-架构原则-本地算力优先.md` | 部署判断原则：本地算力优先 + 云端轻接入；负载均衡/隧道/反向代理的分工；云服务器何时仍值得花钱 |
| `scripts/build-apk.ps1` | 一键构建 debug APK（已固化 JDK21 / Android SDK / 国内镜像） |
| `template/` | 需要手工改的那几个配置文件的样板（Gradle 镜像、SDK 版本等） |

---

## 快速开始（已有项目 → 手机可装）

```powershell
# 0) 前提：JDK 21、Android SDK(platforms/build-tools 36)、Node 18+
#    本机路径见 docs/02；换机器按 docs/02 装一遍

# 1) 建容器（不改你的前端项目）
mkdir my-app ; cd my-app
npm init -y
npm i @capacitor/core @capacitor/cli @capacitor/android --registry=https://registry.npmmirror.com
npx cap init "App 名称" "com.example.app" --web-dir=www

# 2) 把你的前端产物放进来（或在 capacitor.config.json 里指向远程 URL）
#    产物：npm run build  →  dist/    复制成 my-app/www

# 3) 生成原生工程
npx cap add android

# 4) 一键出包
..\jwcapp\scripts\build-apk.ps1 -ProjectDir .
```

产物：`android\app\build\outputs\apk\debug\app-debug.apk`

> **两种打包模式**（先想清楚再动手）：
> - **远程 URL**（`server.url = https://你的域名`）：前端一改即刻生效、不用重发 APK。适合内部试用/快速迭代；Capacitor 官方把它定位为开发用途，正式发布前要重新评估。
> - **内置产物**：把 `dist` 打进 APK，可离线、首屏快；代价是每次前端更新都要重新发版。

---

## 关键约束（从踩坑里提炼的硬规矩）

1. **Java 必须 21**（Capacitor **8.5.3** 的 android 库 `sourceCompatibility VERSION_21`）；AGP 要求的 ≥17 只是底线。
2. **Gradle 走国内镜像**：官方源实测 15 KB/s（131MB 要 2.4 小时），腾讯镜像 1257 KB/s（2 分钟）。
3. **Maven 依赖走国内镜像，但官方仓库保留在镜像之后**做回退，不要整体替换。
4. **公网域名必须进后端 CORS 白名单**，否则带 Origin 的 POST 一律 403（"没有权限访问"最常见的原因）。
5. **资源地址必须是同源相对路径**（如 MinIO 的 `/jwcfast`）；写成 `http://127.0.0.1:9000/...` 会让手机端图片全裂。
6. **前端构建报 `workbox-window` 找不到**：它是 `vite-plugin-pwa` 的隐式依赖，需显式声明。

每条的现象与修法见 [docs/02-环境清单与踩坑.md](docs/02-环境清单与踩坑.md)。
