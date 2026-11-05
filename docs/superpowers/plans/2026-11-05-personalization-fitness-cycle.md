# 个性化、健身与经期跟踪实施待办

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
> 状态：全部待完成；本次只登记方案，不启动开发。建议版本号不代表已经发布。

**Goal:** 在保留现有记录的前提下，按用户主动提供的信息、目标和授权范围组织模块与 AI 建议。

**Architecture:** 复用 NutritionCore、现有训练模型及后端 AI 网关。将档案状态、模块选择、分析范围和快照有效性统一管理；经期作为第二阶段的可选模块接入。

**Tech Stack:** SwiftUI、Swift 6、NutritionCore、HealthKit、UserNotifications、JSON、FastAPI、PostgreSQL。

**Spec:** [设计方案](../specs/2026-11-05-personalization-fitness-cycle.md)。

## Global Constraints

- iPhone、iOS 26+；验证使用真机，不使用模拟器，用户负责最终交互验收。
- 延续黄色奶蛙视觉、自然语言和拍照记餐，不增加食品逐项称重要求。
- 不修改当前 1.0.1（37）审核包；全部任务从后续开发分支开始。
- 性别和年龄可不透露；吸烟与经期独立选择；关闭模块保留历史。
- 事实数值与个人建议分开；所有 AI 入口遵循相同范围、授权与缓存规则。
- 经期的本机记录、AI 分析与云同步分别说明；后端先支持新 schema，再发客户端。

## Review Focus

1. 未填写或不愿透露不能被默认男性、默认出生年份或零值覆盖。
2. 模块关闭后，趋势、缺口提示、追问、汇总、旧缓存和迟到响应不能继续带入其历史数据。
3. 升级、退出引导、同步冲突与恢复旧备份不能删除已有记录或把未确认资料写成已确认。
4. Apple 健康与手动训练并存时，消耗不重复计数；未知数据保留未知。
5. 经期授权撤回、跨日记录、周期不规律与资料不足时，不生成确定预测或泄露敏感内容。

## 建议 1.1.0

### P1 · 个人档案、目标与可跳过引导

**Files:** 扩展 `Sources/NutritionCore/HealthProfile.swift`、`EnergyBudget.swift`、`Models.swift`、`FoodDiary/Features/ProfileEditorView.swift`；新增 `FoodDiary/Features/OnboardingView.swift`。

**Interfaces:** 提供明确区分未填写、不愿透露和已填写的个人上下文，以及已完成/已跳过的引导状态；现有 EnergySettings 只在资料适用时参与计算。

- [ ] 先补充未知资料、主动不透露、合法年龄、清除资料及旧能量设置的回归用例，运行并确认当前实现不能满足新行为。
- [ ] 实现三步引导、稍后设置和资料修改；禁止从默认男性或默认年份自动确认个人信息。
- [ ] 为新字段制定并实现版本迁移；同步服务先扩展 schema 校验，验证旧客户端不会覆写高版本。
- [ ] 验证旧文件、备份、同步历史与引导中断；运行完整 Swift 和后端测试，提交独立变更。

### P2 · 模块选择、导航与分析范围

**Files:** 新增 `Sources/NutritionCore/ModulePreferences.swift`；修改 `FoodDiary/App/FoodDiaryApp.swift`、个人设置、`TrendsView.swift`、`Observation.swift`、`WellnessSummary.swift`。

**Interfaces:** 模块选择由用户明确确认；共享范围对象向导航、趋势与分析提供一致的吸烟/经期启用状态。1.1.0 先落地吸烟开关，经期入口在 P5 完成后开放。

- [ ] 先覆盖男性、女性、不透露与旧用户的选择矩阵，尤其检查“关闭后不发送统计，也不生成缺少吸烟记录的提示”。
- [ ] 实现模块设置与动态导航，健身固定放在趋势后面；当前选中页被关闭时安全切回可用页面。
- [ ] 接入趋势、自动观察、汇总与追问过滤；关闭与删除分开处理，历史可恢复查看。
- [ ] 覆盖请求等待期间关闭模块、重新开启、重启应用和旧数据迁移；测试通过后提交独立变更。

### P3 · 统一 AI 个性化与报告有效性

**Files:** 新增 `Sources/NutritionCore/PersonalizationContext.swift`；修改 `DeepSeekClient.swift`、`Observation.swift`、`ObservationClient.swift`、`WellnessReview.swift` 及各 AI 调用入口。

**Interfaces:** 各入口消费同一份经过筛选的个人上下文；分析快照同时记录数据、资料、目标、模块和授权版本。纯识别仅取得最少必要信息。

- [ ] 先验证同一食品在不同目标下营养事实一致，而建议使用各自已确认的目标；未知年龄或性别不能生成精确代谢目标。
- [ ] 接入记餐建议、每日回顾、汇总、追问及训练建议，保留日期、来源和记录完整程度。
- [ ] 将资料、目标与授权变化纳入缓存有效性；撤权取消请求，迟到响应不按新范围保存；旧报告按原快照标记。
- [ ] 补齐所有入口的模块排除与最少发送用例；运行完整测试后提交独立变更。

### P4 · 健身首页与现有训练能力整合

**Files:** 新增 `FoodDiary/Features/FitnessView.swift`；复用 `WorkoutLogView.swift`、`WorkoutEditorView.swift`、`Sources/NutritionCore/Workouts.swift`、`WorkoutPlans.swift`、`HealthWorkouts.swift`。

**Interfaces:** 消费现有训练记录、计划与健康训练数据，复用当前消耗优先级和 P3 的建议上下文，不创建第二套训练数据源。

- [ ] 先补充无训练、仅手动、仅健康及两者并存的汇总和消耗回归用例。
- [ ] 实现今日训练、开始记录、常用计划、最近训练和周趋势；力量、有氧都可用，经验与偏好可稍后补充。
- [ ] 基于真实训练与恢复资料接入日常建议；自动生成复杂训练计划留在后续扩展。
- [ ] 运行测试并构建最新真机包，交给用户验收导航、键盘、权限和训练记录后提交阶段变更。

## 建议 1.2.0

### P5 · 经期记录、提醒及独立隐私选择

**Files:** 新增 `Sources/NutritionCore/CycleTracking.swift`、`FoodDiary/Features/CycleTrackingView.swift` 及对应测试；扩展日记模型、备份、同步和模块导航。

**Interfaces:** 分开存储实际记录和预计日期；独立控制本机记录、参与 AI 与云同步，复用 P2 的导航和 P3 的分析上下文。

- [ ] 阶段开始时确认预测算法、样本阈值和不确定范围，并先写跨日、异常日期、资料不足与不规律周期用例。
- [ ] 实现开始/结束、日历、历史，可选经量、疼痛、情绪和精力；实际记录不被预测覆盖。
- [ ] 实现用户主动启用的提醒及隐私选择，锁屏提醒默认不显示敏感详情。
- [ ] 为 AI、同步快照、冲突合并、历史恢复、导出和删除分别覆盖敏感字段过滤；撤回后保持相应范围生效。
- [ ] 启用经期或健康习惯入口，接入经确认的跨模块建议，更新隐私说明与发布资料；完整回归、构建与用户真机验收通过后提交阶段变更。

## 发版门槛与跟踪方式

- [ ] 1.1.0：P1–P4 完成；跳过引导可正常记餐，关闭吸烟后所有新分析均不含历史吸烟数据，老用户记录完整。
- [ ] 1.2.0：P5 完成；未启用不采集，拒绝 AI 或同步仍可本机记录，预测与记录区分明确。
- [ ] 每次真机安装、TestFlight 与发布使用当次最新构建，核对主程序和小组件版本；上传与提审按用户后续指令进行。

在 [项目 backlog](../../backlog.md) 登记完成状态，README 只在相应能力实际实现并核验后更新为“已实现”。当前所有复选框保持未完成。
