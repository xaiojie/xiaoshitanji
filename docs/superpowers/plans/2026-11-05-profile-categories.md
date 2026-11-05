# 个人主页分类与拟物图标实施计划

使用 executing-plans 逐项实施。用户已明确要求直接开发并离线构建。

**Goal** 将个人主页收敛为概况和分类入口，补齐晚餐与拟物图标。
**Architecture** 复用现有 SwiftUI 环境模型、HealthMetricDetailView、ActivityChartCard、WeightHistoryView 及全部工具页。
**Tech Stack** SwiftUI、原生 Liquid Glass、图片资源目录、Swift Testing。
**Spec** docs/superpowers/specs/2026-11-05-profile-categories.md。

## 约束与检查重点

用户已断开手机，仅构建实体 iPhone 目标。保持已保存记录的读取兼容。未知健康数值保留未知。大字体下允许卡片扩展。全部现有功能入口都应可达。

- [x] 1. 使用 imagegen 逐个生成透明拟物素材，缩图后落入 Assets.xcassets。早餐、午餐、加餐保留现有素材，晚餐补齐。
- [x] 2. 新建共享图片图标组件和健康分类页，重排 ProfileView。分类覆盖全部 ActivityMetric，身体和饮食入口保持可达。
- [x] 3. 对分类覆盖及资源、入口作回归核验，检查现有真实数据副本可读。签名构建 Debug 与 Release 归档，独立只读审查，记录实测范围。

## 验证记录

- 十二张透明 PNG 已生成并导入，统一为 256×256，总计约 547 KiB。提示词保存在 docs/design/profile-artwork-prompts.json。
- Tests/AppRegression/check-profile-artwork.py 核验十一项健康指标各归属一次、十五项图片引用有效且带透明通道、既有功能入口标识保留。
- 完整 Swift 套件 209 项，208 通过、1 项显式开发工具跳过。旧日记及两份真实备份副本仍可读取并校验通过。
- 真实共享 SwiftUI 卡片经 macOS 静态渲染检查标准网格与单列布局，产物 work/profile-preview/components.png。此项验证为组件布局检查。
- 独立只读审查没有发现需要修复的 Critical、Important 或 Minor。
- 实体 iPhone 目标 Debug 构建和 Release 归档通过，日志无警告，主程序和小组件均为 1.0.1（33），签名及 App Group / HealthKit 配置验证有效。
- 用户已断开手机，本轮完成离线构建，设备安装及实际界面交互等待连接。
