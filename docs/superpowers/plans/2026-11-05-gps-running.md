# 户外跑步实施计划

> 执行方式采用 superpowers:executing-plans。用户已授权按三个阶段连续开发。

**Goal** 完成第三套健身运动手账、GPS 自由跑、公里目标跑和有来源的心率分析。

**Architecture** NutritionCore 保存纯逻辑会话与本机轨迹归档，主程序提供 CoreLocation、HealthKit、SwiftUI 和 MapKit。WorkoutRecord 继续承担可同步摘要。

**Tech Stack** Swift 6、SwiftUI、CoreLocation、MapKit、HealthKit、Charts。

**Spec** ../specs/2026-11-05-gps-running.md

## Global Constraints

- 第三套原型为视觉依据，人物外观固定，使用独立透明 PNG。
- 健身放在趋势之后，自由跑与 0.1–200 公里目标跑均可用。
- 心率显示来源与时效，本次范围由有效跑步区间限定。
- 原始坐标与心率样本保留本机，AI 使用明确授权的统计。
- 保持 schema 5 及现有记录兼容。
- 使用真实 iPhone 的后续验证，当前运行纯逻辑测试和通用 iOS 构建。

## Review Focus

- 暂停、进程恢复和定位间断的距离与时长。
- 重试、文件损坏及保存失败时草稿保留。
- 心率样本跨时间、多来源、延迟同步与权限撤回。
- 本机与健康重复运动、云端摘要和能量统计一致性。
- 小屏、动态字体、运行中离开页面和操作权限被拒绝。

### Task 1 跑步核心与归档

**Files** Sources/NutritionCore/Running.swift、RunArchive.swift、Tests/NutritionCoreTests/RunningTests.swift。

**Interfaces** RunSession 提供 ingest、pause、resume、finish、checkpoint、recover；RunRecord 关联 WorkoutRecord；RunArchive 原子保存草稿和按 UUID 保存记录。

- [x] 编写暂停计时、GPS 跳点/间断、目标、公里分段、心率过滤与归档重试测试。
- [x] 用 Xcode 工具链运行，确认新增类型缺失使测试失败。
- [x] 实现对应逻辑并运行完整 swift test，通过后记录结果。

### Task 2 原生跑步界面与系统服务

**Files** FoodDiary/Services/RunTrackingModel.swift、RunHealthReader.swift、Features/Fitness/、App/FoodDiaryApp.swift、Info.plist。

**Interfaces** 根节点持有 RunTrackingModel，页面通过 environment 共享；服务把原始定位转为 RunLocation，界面只消费有效轨迹与指标。

- [x] 完成并接入四张奶蛙素材。
- [x] 实现准备、自由/目标选择、权限、后台定位、运行状态与草稿恢复。
- [x] 实现 MapKit 分段路线、心率读取、运动手账、记录与详情。
- [x] 运行通用 iPhone 编译，读取错误并修复。

### Task 3 分析、兼容与构建

**Files** Sources/NutritionCore/RunAnalysis.swift、WorkoutTimeline.swift、FoodDiary/Features/AboutDocuments.swift、相关训练汇总入口及回归测试。

**Interfaces** AI 请求使用 RunAnalysisContext 与当前 AIConsent；WorkoutTimeline 对应唯一来源记录并提供统一列表。

- [x] 为请求不含坐标/原始心率、缺失体重与唯一同场运动去重建立回归用例。
- [x] 接入跑后建议、训练摘要、心率刷新、定位/数据/MapKit 说明。
- [x] 完整逻辑测试与通用 iPhone 构建，核对新版主程序与扩展版本。
- [x] 完成整分支独立审查并修复重要问题，记录真机待验证内容。


## 2026-11-06 验证记录

248 项 Swift 逻辑测试通过，Widget 9 项、AI 授权 5 项、同步模型 6 项回归通过。通用 iPhone Debug 开发签名构建通过，主程序和扩展均为 1.1.0（41），深度签名校验通过。独立审查四项 P2 已修复，覆盖损坏历史与草稿隔离、扩展指标与旧摘要兼容、可恢复删除、重试保留心率。真机交互和户外验证等待设备连接。
