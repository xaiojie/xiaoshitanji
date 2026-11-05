# 全功能回归审计与闭环计划

> 审计日期：2026-11-05 · 版本：1.0.1 (37) · 代码基线：`main`
> 范围：`Sources/NutritionCore`、`FoodDiary/`、`server/`、`Tests/`

## 一、结论概览

| 功能域 | 闭环状态 | 说明 |
|---|---|---|
| 记录闭环（手填 / 常吃 / 搜索 / 复制最近一餐） | ✅ 闭环 | 模型层 23 个用例；AI 路径与离线路径都有 |
| 能量闭环（BMR/TDEE/校准/训练抵扣） | ✅ 闭环 | 校准窗口本轮补测（`CalibrationTests`） |
| AI 分析层（教练、观察、汇总、标签、烟盒） | 🟡 半闭环 | 请求构造与解析全测；5 个异步适配器从未实际执行 |
| 健康数据（睡眠/心率/步数/体重/训练） | ✅ 闭环 | 映射与聚合完整；授权失败只能以空态体现 |
| 运动模块（有氧 + 无氧 + 计划） | ✅ 闭环 | `WorkoutTests` / `WorkoutPlanTests` |
| 戒烟（烟包、记录、文本解析、统计） | ✅ 闭环 | 含本轮之前的 `CigaretteTextParser` |
| 成果感（里程碑、连记、省下的钱） | 🟡 半闭环 | 阈值边界（365 餐、10 次体重）未测 |
| 数据安全（备份、恢复、CSV、照片外置） | 🟡 半闭环 | CSV 公式注入本轮修；`DiaryStore.restore` 无测试 |
| 云端同步（注册/登录/快照/冲突/照片/恢复） | 🟡 半闭环 | 服务端 68 项测试；**客户端照片同步零覆盖** |
| 系统集成（小组件、实时活动、提醒、快捷指令） | 🔴 断链 | 实时活动本轮接线；提醒被拒、快捷指令无测试 |

## 二、本轮回归执行记录

| 命令 | 结果 |
|---|---|
| `DEVELOPER_DIR=… swift test` | **223 tests / 30 suites passed**（本轮 +4） |
| `cd server && api/.venv/bin/python -m pytest -q` | **68 passed**（本轮 +5） |
| `Tests/AppRegression/run-ai-consent.sh` | 6 行 PASS |
| `Tests/AppRegression/run-sync-model.sh` | 4 行 PASS（两轮） |
| `Tests/AppRegression/check-profile-artwork.py` | 3 行 PASS |
| `xcodebuild -configuration Debug -destination 'generic/platform=iOS'` | **BUILD SUCCEEDED** |

## 三、本轮已修复

1. **登录限流可被伪造头绕过**（`server/api/app/security.py:86`）：`client_key` 原来无条件读 `X-Forwarded-For`，直连部署可换 IP 打散分桶。现在只有 `trust_proxy_headers=true`（生产 nginx 场景，`docker-compose.yml:13` 显式设置）才采信。
2. **双设备并发同步返回 500**（`server/api/app/main.py:360-385`）：同 `baseVersion` 并发上传撞 `uq_snapshot_version` 时捕获 `IntegrityError`，回滚后返回 409 让客户端合并。
3. **CSV 公式注入**（`Sources/NutritionCore/DiaryCSV.swift:103`）：`=`、`+`、`-`、`@` 开头的字段加单引号；纯数字保持原样以免破坏数值列。
4. **同一天两份复盘合并后互相覆盖**（`Sources/NutritionCore/CloudSync.swift:468`）：合并时按天去重，保留 `generatedAt` 较新的一条。
5. **实时活动入口不存在**（`FoodDiary/Features/DashboardCards.swift:36`）：`toggleLiveActivity()` 此前无任何调用点，README 说有菜单入口但实际没有。现已接入首页日期菜单（仅今天可用，id `toggleLiveActivity`）。
6. 新增测试：`server/tests/test_hardening.py`（5）、`Tests/NutritionCoreTests/CalibrationTests.swift`（2）、CSV 注入与复盘合并各 1。

## 四、未闭环清单

### P0（本轮已全部处理）

- ✅ 限流零覆盖、并发 500、转发头伪造、`/healthz` 契约无测试。

### P1（已修复，2026-11-05）

| # | 缺口 | 位置 | 现在的回归 |
|---|---|---|---|
| 1 | 客户端照片同步零覆盖 | `Sources/NutritionCore/CloudPhotoSync.swift`；`Tests/AppRegression/SyncModelRegression.swift` | fixture 支持 `/v1/sync/photos/missing`、`PUT/GET /v1/sync/photos/{name}`，断言一张上传、一张下载、名字与引用都还在 |
| 2 | `DiaryStore.restore` 无测试 | `Sources/NutritionCore/DiaryStore.swift:32-45` | 已有 `SyncIntegrityTests.explicitRecoveryPreservesUnreadableOriginalAndItsPhotos` 覆盖（原审计遗漏） |
| 3 | `limit_body` 中间件 413 分支从未触发 | `server/api/app/main.py:153-159` | `test_sync.py::test_body_over_the_hard_limit_is_rejected_before_parsing` |
| 4 | 快照内嵌照片兼容分支未测 | `server/api/app/main.py:74-80` | 内嵌 JPEG 可上传、外部照片必须先传、四种非法照片名一律 422 |
| 5 | AI 上游「200 但结构不对」未测 | `server/api/app/ai.py:148-155` | 五种坏 200 响应与 >256KB 响应都映射为 502 |
| 6 | `restore` / `versions` 跨用户隔离未测 | `server/api/app/main.py:385-413` | B 用户 versions 为空、restore A 的版本 404，且双方状态不变 |
| 7 | AI 拒绝后静默无反馈 | `FoodDiary/Services/AIConsent.swift`、`AIConsentModifier.swift` | 拒绝后浮层提示「本次没有发送任何内容」，下次请求自动清除 |
| 8 | 提醒被拒无引导 | `FoodDiary/Services/ReminderScheduler.swift`、`GeneralSettingsView.swift` | 通知被关闭时提醒区显示说明与「打开系统设置」按钮 |

### P2（2026-11-05 修掉 5 条）

| # | 问题 | 现在的状态 |
|---|---|---|
| 1 | 汇总复盘同周期重复 | 合并时按 `period` 收敛到 `generatedAt` 最新的一条，与本机「每个范围只留一份」一致 |
| 2 | `validate` 不查复盘 id 唯一性 | `reviews` 与 `wellnessReviews` 也查重，重复 id 直接判为不可读 |
| 3 | 413 文案写死「8 MB」 | 跟着 `max_payload_bytes` 走，KB/MB 自适应（测试里 64 KB 会如实提示 64 KB） |
| 4 | `constant_time_equals` 死代码 | 删除，连同不再使用的 `hmac` 导入 |
| 5 | 改密边界没测 | 补三种非法新密码（过短/空/过长）422，以及改密后当前会话仍然可用 |

仍然留着、按需处理：

- `CloudSyncClient` 的 `login / state / logout / deleteAccount` 没有单测，只有 `SyncModel` 回归脚本间接覆盖。
- 里程碑阈值、`HealthMeasurementInput.parse` 非法输入、`PhotoAttachment` 上限、`ReminderPlanner.next` 恰好当前分钟与 DST。
- `TrendsView`、`HealthMetricView` 没有 `accessibilityIdentifier`，脚本巡检不到入口。
- 文件式 CSV / JSON 导入导出已按用户决定移除（2026-11-05），CSV 导入不再需要补。

### 已知设计取舍（不是缺陷，回归时按此预期）

- 云同步是**并集合并 + 本机优先**：一台设备删掉的条目可能被另一台重新带回来。
- 快捷指令、小组件、实时活动都依赖真机验证，命令行只能测模型层。
- HealthKit 读权限被拒时系统不告知 App，UI 只能显示空态。

## 五、手工回归清单（真机，按风险排序）

1. 新装后记一餐点「让 AI 分析」→ 授权弹窗点「暂不使用」→ 停在记餐页，再点仍弹窗。
2. 同意后记第二餐不再弹窗；设置里撤回授权 → 再分析重新弹窗。
3. 备份恢复：设置 → 从 JSON 恢复 → 确认 → 餐数与文件一致，Documents 出现恢复点。
4. 同入口点「继续查看」→ 数据完全不变。
5. 导出 JSON → 改几条 → 恢复该文件 → 回到导出时状态。
6. 两台设备改同一天 → 立即同步 → 出现冲突提示而非丢数据。
7. 版本列表恢复历史版本 → 确认后合并回本机。
8. 断网时删除云端账号 → 报错且登录态保留。
9. 服务器不可达时退出账号 → 本地登录态清空、记录仍在。
10. 相机/相册权限拒绝后再点 → 有提示不白屏。
11. 健康授权全允许 → 今日概况出现步数/消耗/睡眠；系统里关掉读权限后刷新 → 空态不崩溃。
12. 健康 App 写入身高 → 回 App 显示该身高；编辑资料不改身高保存 → 不被本地值覆盖。
13. 烟盒识别：同意授权后拍烟盒 → 品牌/价格/根数填好；拒绝相册权限可回落手输。
14. 烟包校准余量 5 → 记录一根 → 变 4；历史撤销 → 回补一根。
15. 提醒开关打开但通知选「不允许」→ 不响（已知）；系统设置开启后能收到。
16. 快捷指令「用 小食痰记 记一餐」→ App 打开并带入文字。
17. 首页日期菜单 → 「灵动岛显示今日摄入」→ 灵动岛出现当日热量；再点关闭。
18. 记一餐后回桌面 → 小组件今日摄入刷新。
19. 趋势页空态：全新账号只显示空态卡。
20. 体重记录 70 kg → 列表、折线图、我的页头部同步。

## 六、未开发功能计划

### 1.1.0「个人化」（P1 → P4，预计 4 个迭代）

| 阶段 | 内容 | 验收 |
|---|---|---|
| P1 首次引导与个人档案 | 性别/年龄可跳过，目标五选一，出生年可改 | 新装 3 步内开始记第一餐；档案可随时改 |
| P2 模块开关与动态导航 | 吸烟默认开、经期二期；Tab 与首页卡片按开关显隐 | 关掉吸烟后 Tab 消失且数据保留 |
| P3 统一 AI 个性化 | 档案、目标、授权、数据范围进快照；失效与撤权联动 | 换设备后 AI 语气与建议一致；撤权后立即停止发送 |
| P4 健身首页 | 今日训练、记录入口、常用计划、周趋势；训练消耗不与饮食重复计算 | 与现有能量预算数值一致，无双重抵扣 |

### 1.2.0「周期与建议」

- **P5 经期跟踪**：记录与预测分开、经量/疼痛/情绪/精力可选、提醒可关；独立隐私开关（仅本机 / 允许 AI / 参与同步）。
- 动态入口与综合建议：经期、训练、饮食、吸烟四路信号汇总成一条建议。
- 验收：预测偏差可见且可手动纠正；隐私三态在设置中可审计。

### 明确不做

- 社交与排行榜、自维护食物库、睡眠评分与任何医学诊断结论。
- AI 训练计划生成（backlog 3.6）继续后置，等 P4 数据积累后再评估。

## 七、建议执行顺序

1. P1 八项已全部补齐（见上表），下一轮从 1.1.0 的 P1「首次引导与个人档案」开始。
2. 每个阶段一个提交、一次全量回归（`swift test` + `pytest` + 三个 App 回归脚本 + Release 构建）。
3. P2 清单按「改到该文件时顺手补」处理，不单独排期。
