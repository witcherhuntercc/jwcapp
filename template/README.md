# template —— 需要手工改的那几个文件（样板）

Capacitor 用 `npx cap add android` 自动生成的工程里，**只有 4 个文件需要按本机情况调整**（都是为了国内网络与 SDK 版本）。
新项目生成 `android/` 之后，把这里的样板对照着改一遍即可。

| 样板文件 | 放到工程的哪里 | 改什么 |
|---------|---------------|--------|
| `capacitor.config.json` | 工程根目录（`cap init` 已生成，按需补 `server` 段） | 两种模式：内置产物 / 远程 URL |
| `android/gradle/wrapper/gradle-wrapper.properties` | 同名路径 | `distributionUrl` 指向腾讯镜像（官方源注释保留） |
| `android/build.gradle` | 同名路径 | 两处 `repositories` 加阿里镜像（官方仓库保留在后） |
| `android/variables.gradle` | 同名路径 | SDK 版本（当前模板：minSdk 24 / compileSdk 36 / targetSdk 36） |

> 详细步骤与原因：见 [../docs/03-把网页变成APK-标准流程.md](../docs/03-把网页变成APK-标准流程.md) 与 [../docs/02-环境清单与踩坑.md](../docs/02-环境清单与踩坑.md)。

**注意**：这些文件里的**绝对路径**（如 SDK 位置）不要写进工程；工具链路径只在构建时通过环境变量传入（`scripts/build-apk.ps1` 已处理）。
