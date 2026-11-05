# 奶蛙组件实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 按两张已确认原型升级桌面组件，点击“记一餐”直接进入餐食编辑页。

**Architecture:** 扩展两端共用的只读快照，纯逻辑 Builder 从当天日记生成分餐摘要；WidgetKit 使用原生 SwiftUI 和现有奶蛙资源；App 层用可观测的待处理路由连接深链与 TodayView。

**Tech Stack:** Swift 6、SwiftUI、WidgetKit、Foundation、NutritionCore、现有 App Group。

**Spec:** [规格](../specs/2026-11-05-widget-redesign.md)。

## Global Constraints

- iOS 26+，只构建真机，不使用模拟器；用户负责手机交互测试。
- 当前审核流程由用户处理，不上传、不撤回或修改审核状态。
- 主程序和扩展统一为 1.0.2（38）；不实施个性化和经期等另外排期的功能。
- 现有奶蛙 PNG 与真实控件组成界面，未设置的目标保持未知，跨天不保留昨日摄入。

## Review Focus

1. 小屏、长数字、目标未设和旧快照时，文字不被奶蛙遮挡，未知不能误报为零。
2. 深链冷启动、其他 Tab、已开草稿和重复点击，不丢输入、不重复创建或保存记录。
3. 零点与时区变化后显示今天；时间线与快照均有日期边界。
4. 组件目标与 App 一致，健康训练和手动训练不重复计算。
5. 主程序 / 扩展资源与版本一致，旧 JSON 可读取，变更不影响日记备份与同步 schema。

### Task 1: 快照、分餐和路由逻辑

**Files:** `Shared/DiaryWidgetSnapshot.swift`、新建 `FoodDiary/Services/WidgetSnapshotBuilder.swift`、新建 `FoodDiary/App/WidgetNavigation.swift`、`Tests/AppRegression/WidgetRegression.swift` 与运行脚本。

**Interfaces:** `WidgetSnapshotBuilder.make(document:targetCalories:on:calendar:)` 返回完整当日摘要；`DiaryWidgetRoute` 提供今日页和新记餐 URL；`WidgetNavigation.receive(_:)` 接收有效路由，`takeRoute(canPresent:)` 在允许展示时消费一次。

- [ ] 先写并运行旧 JSON、分餐、未知目标、进度、跨天及路由等待 / 消费用例，确认新接口尚未实现。
- [ ] 实现可兼容解码的餐次字段、当日过滤、纯 Builder 和待处理路由。
- [ ] 回归转绿，记录结果并提交。

### Task 2: 两种尺寸的原生组件

**Files:** `FoodDiaryWidgets/IntakeWidget.swift`、新建 `IntakeWidgetContent.swift` 与扩展自己的 `Assets.xcassets`。

**Interfaces:** 可独立渲染的小号 / 中号内容 View 消费 Task 1 的快照；时间线提供零点清空条目；按钮与背景分别使用新记餐 / 今日 URL。

- [ ] 按原型实现分层、奶蛙、进度、营养条与中号餐次 / 记餐按钮，处理空白、未设目标及旧数据。
- [ ] 时间线在下一零点切换；检查 iOS 编译与扩展资源，按实际尺寸离屏渲染并对照原型。
- [ ] 记录布局结果并提交。

### Task 3: App 直达记餐与数据刷新

**Files:** `FoodDiaryApp.swift`、`TodayView.swift`、`DiaryModel.swift`、`WidgetSnapshotWriter.swift`。

**Interfaces:** Root 持有 WidgetNavigation；TodayView 在可展示且日记正常时消费路由；DiaryModel 在保存和目标 / 健康 / 日期变动后发布同口径快照。

- [ ] 接入新记餐路由，直接打开 ComposerView，不经过 RecordEntrySheet；正常关闭现有表单后再处理待办。
- [ ] 发布分餐快照，接入参考热量、当日训练、健康刷新和跨日更新。
- [ ] 运行 Widget 回归及现有 AI 授权 / 同步回归，构建主程序并提交。

### Task 4: 集成、构建与交付记录

**Files:** 工程版本、README、相关设计 / 待办文档；本机构建记录。

- [ ] 统一 1.0.2（38），运行完整 Swift 测试及本轮 App 回归。
- [ ] 完成全分支独立审查，处理真实缺陷，复核后合入 main；确认改动不包含其他待开发模块。
- [ ] 使用最新源码完成 iPhone Debug、Release 归档与签名核验，核对扩展中的奶蛙资源。
- [ ] 更新文档和本机最新版路径；交给用户真机测试，不上传 TestFlight 或提审。
