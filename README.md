# 食记

个人 iPhone 饮食记录 MVP，中文界面，SwiftUI 与原生 Liquid Glass，最低支持 iOS 26。

## 首版功能

- 文字、相册照片或拍照输入，支持文字补充图片。
- DeepSeek 生成待确认的食物、实际食用克数和每 100 克营养数值。
- 调整份量后自动重算千卡、蛋白质、碳水和脂肪。
- 无 API Key 时可手动添加食物。
- 确认保存、补记、编辑、删除，以及按本地日期汇总。
- 最近七天趋势，均值仅统计有记录的日期。
- 可选每日参考热量目标。
- 原子写入本地 JSON，损坏文件和更新版本数据受到覆盖保护。
- API Key 保存于本机 Keychain，支持导出不含 Key 的完整记录 JSON。

## 用 Xcode 运行

1. 打开 `FoodDiary.xcodeproj`。
2. 选择 `FoodDiary` scheme。
3. 用数据线连接并解锁 iPhone，设备需运行 iOS 26 或更新版本。
4. 在 iPhone 中启用开发者模式，并信任此 Mac。
5. 在 Signing & Capabilities 选择自己的 Apple 开发团队。本机已配置检测到的 Jay He 团队。
6. 选择连接的 iPhone，点击 Run。

本机 Xcode 位于 `/Volumes/OS/Applications/Xcode.app`。命令行构建可使用以下方式。

```sh
export DEVELOPER_DIR=/Volumes/OS/Applications/Xcode.app/Contents/Developer
xcodebuild -project FoodDiary.xcodeproj -scheme FoodDiary \
  -configuration Debug -destination 'generic/platform=iOS' \
  -derivedDataPath work/DerivedData build
```

## 配置 DeepSeek

在 App 的「我的」中填入 API Key，点击「保存 API Key」，再到「今天」点击「记录饮食」。

使用官方地址 `https://api.deepseek.com/chat/completions`，模型为 `deepseek-flash`，采用 JSON Output、非流式及关闭思考模式的请求。2026 年 11 月 4 日核对的官方文档确认该模型支持图片输入。

- [DeepSeek 初次调用文档](https://api-docs.deepseek.com/)
- [DeepSeek 图片输入文档](https://api-docs.deepseek.com/guides/vision)
- [DeepSeek JSON Output 文档](https://api-docs.deepseek.com/guides/json_mode)

照片在手机上缩小到最长边 1280 像素并重新编码为 JPEG，去掉原图的位置和相机元数据。只有点击 AI 分析后，饮食文字及处理后的照片才会发送给 DeepSeek，调用费用记入用户自己的 API 账户。

首版营养密度来自 AI 估算。确认页会显示估算假设，允许按实际份量或包装标签修改。后续可接入独立营养数据库。

## 数据

记录文件为 App Documents 目录下的 `FoodDiary/diary.json`，包含 schemaVersion、餐次、日期、食物、原始输入、处理后的照片及估算说明。

可以通过「我的 → 导出饮食记录 JSON」保存备份，也可以在 iPhone「文件」App 中找到食记的目录。API Key 单独保存在 Keychain，不进入记录文件。首版备份提供导出能力。

## 核心测试

```sh
export DEVELOPER_DIR=/Volumes/OS/Applications/Xcode.app/Contents/Developer
swift test
```

测试运行在 Mac，覆盖计算、校验、文件保存回读、更新删除、损坏保护、日期和 DeepSeek 请求解析。应用界面、相机和实际联网调用通过真实 iPhone 验证。

## 结构

```text
FoodDiary/                  SwiftUI 界面、Keychain、相机和图片处理
FoodDiary.xcodeproj/        iPhone 原生 Xcode 工程
Sources/NutritionCore/      数据模型、本地存储、DeepSeek 客户端
Tests/NutritionCoreTests/   核心自动化测试
docs/superpowers/           本轮范围和开发计划
work/                      本地构建和验证记录，Git 忽略
```

健身数据、HealthKit 和云同步可在后续迭代接入独立模块。
