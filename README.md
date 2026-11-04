# 食记

个人 iPhone 饮食记录应用，当前版本为 0.3.0 个人健康版。中文界面，SwiftUI 与原生 Liquid Glass，最低支持 iOS 26。

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
- 「我的」展示今日概况、身体能力和全部数据。顶部可编辑头像、昵称、身高、当前体重、目标体重，并自动计算 BMI。
- 体重支持带时间的测量历史、趋势图、手动记录编辑和删除。
- 通过通用设置或主页按钮连接 Apple 健康，按所选权限只读步数、活动能量、锻炼时长、步行跑步距离、体重和身高。近 7 天活动趋势保留无数据日期的空缺。
- 可选每日参考热量目标。
- 新建早餐默认 08:45，午餐默认 12:00，晚餐默认 20:00，分别取自个人常用时间范围的中间值。日期沿用所选日期，加餐采用当前时刻。切换餐次会应用该餐次预设，时间也可手动调整。
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

在 App 的「我的 → 右上角通用设置」中填入 API Key，点击「保存 API Key」，再到「饮食」点击「AI 记饮食」，或从对应餐次直接开始。

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

记录文件为 App Documents 目录下的 `FoodDiary/diary.json`，包含 schemaVersion、餐次、日期、食物、原始输入、处理后的照片、修正历史、每日回顾、个人档案及手动体重历史。已有 0.1.0、0.2.x 的记录兼容读取。

可以通过「我的 → 通用设置 → 导出本机记录 JSON」保存备份，也可以在 iPhone「文件」App 中找到食记的目录。API Key 单独保存在 Keychain，不进入记录文件。首版备份提供导出能力。

## 核心测试

```sh
export DEVELOPER_DIR=/Volumes/OS/Applications/Xcode.app/Contents/Developer
swift test
```

测试运行在 Mac，覆盖计算、校验、文件保存回读、更新删除、旧格式兼容、损坏保护、日期、自然份量、修正上下文及 DeepSeek 请求解析。健康相关测试覆盖 BMI、资料校验、旧格式兼容、测量保存回读、来源和日期选择以及缺失数据。界面、相机、键盘、健康授权与实际联网调用使用真实 iPhone 验证。

## 结构

```text
FoodDiary/                  SwiftUI 界面、Keychain、相机和图片处理
FoodDiary.xcodeproj/        iPhone 原生 Xcode 工程
Sources/NutritionCore/      数据模型、本地存储、DeepSeek 客户端
Tests/NutritionCoreTests/   核心自动化测试
docs/superpowers/           本轮范围和开发计划
work/                      本地构建和验证记录，Git 忽略
```

## Apple 健康

首次读取需在手机上选择允许访问的数据类型。授权请求完成后仍可能没有可读取数据，界面显示空缺，读取失败时保留已有快照及错误提示。返回前台或下拉页面时刷新。活动消耗对应活动能量，包含运动与日常活动。

本机资料中的身高优先用于 BMI，未填写时使用 Apple 健康最新身高。体重采用手动记录和可读取的 Apple 健康测量中时间最新的一条，同一时间优先手动记录。只修改昵称或头像不会新增体重测量。Apple 健康的测量需在健康 App 中管理。

Apple 健康的读取结果保存在当前运行会话中，重启后重新读取。个人档案和手动体重历史随本机 JSON 导出，健康来源的数据按需读取。个人资料与健康读取结果仅用于本机展示。训练计划和云同步可在后续迭代接入。
