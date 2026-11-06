# 健身首页原型

绘制日期：2026-11-05。2026-11-06 已按用户选择的第三套开发跑步界面，构建版本为 1.1.0（41），等待真机交互与户外验证。

| 展示顺序 | 方向 | 原型图 | 奶蛙动作 |
| --- | --- | --- | --- |
| 1 | 今日动一动 | [查看原图](fitness-home-01-today.png) | 坐在训练凳上举哑铃 |
| 2 | 训练搭子 | [查看原图](fitness-home-02-plans.png) | 坐姿拉伸 |
| 3 | 运动手账 | [查看原图](fitness-home-03-journal.png) | 躺在垫子上休息 |

三套均延续现有 App 的奶油底色、黄色主题、棕色文字、拟物器材和玻璃质感底部导航。人物以原始奶蛙全身与脸部图片为参考，变换动作而保留人物特征。

健身入口位于趋势之后。界面围绕现有训练记录、常用计划、Apple 健康与建议组织，首版能力范围参见 [个性化与健身规划](../../superpowers/specs/2026-11-05-personalization-fitness-cycle.md)。复杂自动计划、动作识别及经期模块不在本次原型中。

原型以 390 × 844 逻辑视口构思，交付 PNG 为图像工具生成的 852 × 1846 像素。数据均为示例，明确区分手动记录和 Apple 健康来源；日期以 2026 年 11 月 5 日星期四为准。正式实现时采用原生文字、图标和布局，不能将整张效果图当作可交互页面。

使用内置 image_gen 绘制，完整提示词与输入参考记录在 [generation-prompts.json](generation-prompts.json)。第三套已进入本轮跑步实现，详见下方实施状态。

## 已接入的独立人物素材

四张素材使用内置 image_gen 绘制，均为 1536 × 1024 的 RGBA 透明 PNG，并直接加入主程序资源。

| 用途 | 素材 |
| --- | --- |
| 运动手账首页休息 | [FitnessFrogRest](../../../FoodDiary/Assets.xcassets/FitnessFrogRest.imageset/FitnessFrogRest.png) |
| 跑前拉伸 | [FitnessFrogStretch](../../../FoodDiary/Assets.xcassets/FitnessFrogStretch.imageset/FitnessFrogStretch.png) |
| 跑步中 | [FitnessFrogRun](../../../FoodDiary/Assets.xcassets/FitnessFrogRun.imageset/FitnessFrogRun.png) |
| 跑后喝水 | [FitnessFrogFinish](../../../FoodDiary/Assets.xcassets/FitnessFrogFinish.imageset/FitnessFrogFinish.png) |

素材完整提示词与原始角色参考见 [running-asset-prompts.json](running-asset-prompts.json)。

## 实施状态

支持 GPS 自由跑、公里目标跑、地图分段轨迹、暂停继续、结束保存、公里分段、心率读取刷新与曲线，以及按选择范围的跑后 AI 建议。健身入口位于趋势之后，本机跑步摘要进入趋势与整体分析。

精确轨迹、心率样本、目标及恢复草稿存放本机 RunArchive。WorkoutRecord 的可选 runMetrics 保存精确数值摘要，兼容字段继续满足旧客户端约束。旧客户端显示兼容摘要，新客户端使用精确指标。地图服务使用 Apple MapKit。

检查结果为 248 项 Swift 测试通过，三组应用回归共 20 项通过，通用 iPhone 开发签名构建及签名校验通过。独立代码审查指出的四类保存与恢复问题已通过新增回归覆盖并修复。真机待验证项目包括锁屏与后台持续定位、实际 GPS 误差、设备心率同步时效、耗电、小屏与动态字体。

详细需求和实施步骤见 [跑步方案](../../superpowers/specs/2026-11-05-gps-running.md) 与 [实施计划](../../superpowers/plans/2026-11-05-gps-running.md)。
