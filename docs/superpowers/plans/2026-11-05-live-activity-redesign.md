# 奶蛙实时活动 Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans to implement this plan inline. 本轮用户明确要求只开发代码，不测试、不构建；验证留待后续授权。

**Goal:** 将已选第三套「餐次进度」实现为原生灵动岛和锁屏实时活动。

**Architecture:** 沿用 ActivityKit 和现有 Widget 扩展，将展示、共用组件及数据属性分开。通过现有快照生成器填充营养和分餐，复用已有 URL 路由进入餐食录入。

**Tech Stack:** Swift 6、SwiftUI、WidgetKit、ActivityKit，现有 iOS 26 目标。

**Spec:** [已选原型与交付边界](../../design/live-activity/README.md)。

## Global Constraints

- 保留原始奶蛙素材、黄色品牌及系统相机区域。
- 不编造能量目标、营养或缺失餐次；旧 ContentState 继续解码。
- 按用户本轮指令不测试、不构建、不安装，不操作当前审核。

## Review Focus

旧活动缺字段、无目标 / 超目标、跨日 / 时区、相机与高度限制、息屏 / 减少动态效果、记餐草稿衔接、连续更新顺序均留待后续验证，不能标记通过。

### Task 1: 真实数据

- [x] Shared/IntakeActivityAttributes.swift 扩展可选营养、餐次、时区及快照初始化。
- [x] Shared/DiaryWidgetSnapshot.swift 为餐次增加 Hashable，用于活动状态和更新过渡。
- [x] IntakeActivityManager、DiaryModel、TodayView 统一目标与今日统计；恢复活动引用和零点过期。

### Task 2: 第三套布局与动效

- [x] IntakeLiveActivity.swift 接入四种状态、原生相机避让、深链。
- [x] IntakeLiveActivityContent.swift 实现能量 / 目标 / 进度 / 营养 / 直接记餐。
- [x] IntakeActivityComponents.swift 实现四餐节点、奶蛙短暂过渡与紧凑数据。

### Task 3: 交付

- [x] 保存选定原型，更新 README 与后续清单，注明仅代码状态。
- [ ] 后续授权后运行编译、回归与真机验收；通过前不宣称效果已验证。
