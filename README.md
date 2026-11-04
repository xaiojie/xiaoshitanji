# 食记

个人 iPhone 饮食记录应用，当前版本为 0.2.0 AI 记餐版。中文界面，SwiftUI 与原生 Liquid Glass，最低支持 iOS 26。

## 首版功能

- 文字、相册照片或拍照输入，支持文字补充图片。
- 用一碗、一个、一杯、半份等日常说法描述，AI 自动估算食物、份量、热量和营养。
- 识别结果显示自然份量。可选择吃了一半、少一点或多一点，自动重算千卡、蛋白质、碳水和脂肪。
- 补充「米饭只吃了一半」「还有一碗汤」等描述，AI 在当前餐食基础上继续修正。
- 日常流程使用自然语言及图片输入，分析需要先配置 DeepSeek API Key。
- 确认保存、补记、编辑、删除，以及按本地日期汇总。
- 饮食首页包括摄入环、营养供能分布及早、午、晚、加餐四个分区。
- AI 每日回顾提供总结、亮点和下一餐建议，信息足够时给出参考评分。
- 最近 7 天和 30 天趋势，包含摄入、实际生成的 AI 评分和记录日平均营养。
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

在 App 的「我的」中填入 API Key，点击「保存 API Key」，再到「饮食」点击「AI 记饮食」，或从对应餐次直接开始。

使用官方地址 `https://api.deepseek.com/chat/completions`，模型为 `deepseek-flash`，采用 JSON Output、非流式及关闭思考模式的请求。2026 年 11 月 4 日核对的官方文档确认该模型支持图片输入。

- [DeepSeek 初次调用文档](https://api-docs.deepseek.com/)
- [DeepSeek 图片输入文档](https://api-docs.deepseek.com/guides/vision)
- [DeepSeek JSON Output 文档](https://api-docs.deepseek.com/guides/json_mode)

照片在手机上缩小到最长边 1280 像素并重新编码为 JPEG，去掉原图的位置和相机元数据。只有点击 AI 分析后，饮食文字及处理后的照片才会发送给 DeepSeek，调用费用记入用户自己的 API 账户。

营养密度及内部食用重量来自 AI 估算。结果页显示自然份量，估算依据可展开查看。修正流程接受日常描述和份量选项。后续可接入独立营养数据库。

## 每日 AI 回顾

在首页的「AI 饮食教练」中点击分析。回顾只覆盖已保存的餐食，只有一餐或信息不足时评分保留空值。修改、补记或删除当天餐食后，旧回顾会失效。

回顾记录会保存生成时使用的热量参考目标。调整目标后，首页等待基于当前目标的新回顾，历史趋势中的评分仍对应当时的目标。

## 数据

记录文件为 App Documents 目录下的 `FoodDiary/diary.json`，包含 schemaVersion、餐次、日期、食物、原始输入、处理后的照片、修正历史及每日回顾。已有 0.1.0 的记录兼容读取。

可以通过「我的 → 导出饮食记录 JSON」保存备份，也可以在 iPhone「文件」App 中找到食记的目录。API Key 单独保存在 Keychain，不进入记录文件。首版备份提供导出能力。

## 核心测试

```sh
export DEVELOPER_DIR=/Volumes/OS/Applications/Xcode.app/Contents/Developer
swift test
```

测试运行在 Mac，覆盖计算、校验、文件保存回读、更新删除、旧格式兼容、损坏保护、日期、自然份量、修正上下文及 DeepSeek 请求解析。界面、相机、键盘与实际联网调用通过真实 iPhone 验证。0.2.0 改版的真机安装及联调等待手机重新连接。

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
