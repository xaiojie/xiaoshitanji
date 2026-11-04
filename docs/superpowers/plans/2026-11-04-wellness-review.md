# 汇总分析与子页面实施计划

使用 superpowers:executing-plans，根 agent 顺序实施。结束时进行一次只读独立审查。

## 约束

原生 iOS26 SwiftUI，实体 iPhone。继承黄色奶蛙主题与既有数据/AI流程，旧格式兼容，敏感健康汇总在应用内确认后发送。

Spec 为 docs/superpowers/specs/2026-11-04-wellness-review-design.md。

## 任务

- [x] 1. 修复子页布局，替换旧 Form 外观、顶部退出气泡和照片覆盖装饰。责任文件为 BrandComponents、GeneralSettings、Composer、ProfileEditor、WeightHistory、SmokingHistory。
- [x] 2. 测试先行实现 WellnessSummary 与 WellnessReview，包括本地聚合、缺失覆盖、时间范围、持久化兼容、DeepSeek 构造和解析。责任文件为 Sources/NutritionCore 和新的 WellnessTests。
- [x] 3. 接入按范围读取健康数据和「我的」汇总分析页，含发送确认、取消、错误、历史报告和只用本机数据。责任文件为 HealthDataModel、DiaryModel、WellnessReviewView、ProfileView。
- [x] 4. 完整回归、一次独立审查、真机构建与安装，更新版本与说明。
- [ ] 5. 用户在真机检查子页面、相机、键盘和实际 AI 分析效果。

## 最终结果

用户明确选择「先安装，我自己测试」，因此第5项交由用户自测。本轮未操作手机界面或发送实际健康数据至API。

75项核心测试通过，Debug和Release构建及严格签名校验通过。已安装0.6.0（10）。独立审查的身高截止时间问题已通过查询谓词修正，请求中无用途的测量UUID已剔除并增加RED→GREEN断言。其余未处理的Critical/Important为0。

## 审查重点

所有数据日期范围一致。未知数据保留缺失。分烟与校准不计个人摄入。长期历史汇总保持请求大小可控。最新测量与体重变化使用正确日期及来源。HTTP/解析/保存失败和取消不会丢失旧报告或覆盖其他记录。所有新的发送都由明确用户动作触发。
