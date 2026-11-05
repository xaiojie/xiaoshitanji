# Bug 修复记录

记录每个已修 bug 的**症状、根因、修复、验证**，便于以后回归时判断「这个现象是不是修过」。
工具链问题（不是 App bug）单独放在最后。

## 2026-11-05 · 崩溃

### 1. 点麦克风语音输入，App 直接闪退（第一次）

- **症状**：首次点击记餐页麦克风，App 被系统杀掉。崩溃日志（`--domain-type systemCrashLogs` 抓取）显示
  `EXC_BREAKPOINT` / `dispatch_assert_queue_fail` / `_swift_task_checkIsolatedSwift`，
  栈顶为 `closure #1 in closure #1 in static SpeechTranscriber.requestPermission()`。
- **根因**：`SFSpeechRecognizer.requestAuthorization` 的完成回调跑在 TCC 的后台队列上，
  但闭包继承了 `@MainActor` 类的执行器隔离，Swift 6 在运行时做了隔离检查并触发 SIGTRAP。
- **修复**：`FoodDiary/Services/SpeechTranscriber.swift` 中把 `requestPermission()` 改为
  `private nonisolated static func … async -> Bool`，不再继承主 actor 隔离。
  提交 `07c0a82`。
- **验证**：真机反复授权/拒绝各 3 次，不再崩溃；`swift test` 全绿。

### 2. 语音授权通过后开始录音又闪退（第二次）

- **症状**：修好授权崩溃后，开始录音 1～2 秒内再次崩溃，
  线程为 `RealtimeMessenger.mServiceQueue`，栈为
  `closure #1 in SpeechTranscriber.start()` → `AVAudioNodeTap::TapMessage::RealtimeMessenger_Perform()`。
- **根因**：`installTap(onBus:)` 的音频回调在实时音频线程执行，闭包同样继承了 `@MainActor` 隔离；
  修复前一次崩溃只处理了 TCC 回调，没有处理音频回调。
- **修复**：`installTap` 与 `recognitionTask` 的闭包统一标 `@Sendable`，
  共享变量改为 `nonisolated(unsafe) let audioRequest`；
  同时在 `installTap` 前加 `guard format.sampleRate > 0, format.channelCount > 0`
  （0 采样率会让 AVFoundation 抛 ObjC 异常），失败时提示「麦克风暂时不可用，先手动输入吧。」并清理会话。
  提交 `54f2626`。
- **验证**：真机连续录音 10 次无崩溃；拒绝麦克风权限后走 fallback 不崩溃。

## 2026-11-05 · 数据与服务端

### 3. 登录限流可被 `X-Forwarded-For` 绕过

- **症状**：安全审计发现限流分桶键无条件读取 `X-Forwarded-For`，
  直连部署时客户端换一个假 IP 就能无限次尝试密码，撞库防护形同虚设。
  `Settings.trust_proxy_headers` 存在但从未被引用（死配置）。
- **修复**：`server/api/app/security.py` 的 `client_key(request, username, *, trust_forwarded=False)`；
  只有反向代理部署（`TRUST_PROXY_HEADERS=1`，`docker-compose.yml:13` 已设置）才采信转发头，
  否则用 `request.client.host`。`register` / `login` 两处调用点传入开关。
- **验证**：新增 `server/tests/test_hardening.py::test_limiter_ignores_spoofed_forwarded_header`
  与 `::test_limiter_uses_forwarded_header_behind_proxy`，两种部署形态行为都被锁定。

### 4. 两台设备同时同步，输的一方拿到 500

- **症状**：双设备用同一 `baseVersion` 上传时，后写入的一方偶发 500，
  客户端只会对 409 做合并重试，于是直接报错、不同步。
- **根因**：`put_snapshot` 只靠 `with_for_update()` 串行化，SQLite 下该语句无效；
  真正撞到唯一约束 `uq_snapshot_version` 时 `IntegrityError` 未被捕获。
- **修复**：`server/api/app/main.py` 的 `put_snapshot` 捕获 `IntegrityError` → `rollback` →
  重新读取最新状态 → 返回 409（含 `version` / `updatedAt`）。
- **验证**：`test_hardening.py::test_concurrent_upload_same_base_version_is_a_conflict`
  用 `asyncio.gather` 并发两个 `baseVersion=0` 上传，断言状态码恰为 `[201, 409]` 且版本只涨 1。

### 5. 导出 CSV 会被表格软件当公式执行

- **症状**：食物名或备注以 `=`、`+`、`-`、`@` 开头时，导出的 CSV 用 Excel / Numbers 打开会执行公式
  （CSV injection），可被用来外链窃取数据。
- **修复**：`Sources/NutritionCore/DiaryCSV.swift` 的 `escape` 对上述开头的字段加单引号前缀；
  纯数字（如 `-3.5`）仍原样输出，避免破坏数值列。
- **验证**：`Tests/NutritionCoreTests/DiaryCSVTests.swift::escapesFormulaInjection`。

### 6. 换设备后看到过期的饮食复盘

- **症状**：两台设备各给同一天生成过复盘，同步合并后同一天存在两条 review，
  页面 `review(on:)` 取首条，可能显示较旧的那份。
- **修复**：`Sources/NutritionCore/CloudSync.swift` 合并时新增 `oneReviewPerDay`，
  按天去重并保留 `generatedAt` 较新的一条。
- **验证**：`Tests/NutritionCoreTests/CloudSyncTests.swift::mergesReviewsByDay`。

## 2026-11-05 · 交互

### 7. 「灵动岛显示今日摄入」没有入口

- **症状**：`TodayView.toggleLiveActivity()` 与相关状态、错误提示都实现了，
  但全仓库没有任何调用点；README 却写着「首页菜单里手动打开」，用户实际点不到。
- **修复**：`FoodDiary/Features/DashboardCards.swift` 的日期菜单新增
  「灵动岛显示今日摄入 / 关闭灵动岛」（仅选中今天时出现，id `toggleLiveActivity`），
  由 `TodayView` 传入 `liveActivity.isRunning` 与动作闭包。
- **验证**：真机点开后灵动岛出现当日热量，再点关闭；`xcodebuild` BUILD SUCCEEDED。

### 8. 「记饮食」弹窗过高

- **症状**：首页点「记一餐」弹出的面板占了半个屏幕，上方大片空白。
- **修复**：`FoodDiary/Features/MealSectionCard.swift` 的 `RecordEntrySheet`
  收紧内边距（24 → 22 / 12 / 22）、行距 24 → 18、图标 48 → 44，
  detent 由 `[.medium, .large]` 改为 `[.height(300), .large]`。提交 `651bf5f`。
- **验证**：真机弹窗高度贴合内容，四个餐次与 AI 入口无需滚动。

### 9. 「拍下碗里的这一餐」卡片点不动

- **症状**：记餐页的大拍照卡只是静态卡片，必须点旁边小按钮才能开相机，与文案「拍下」不符。
- **修复**：`FoodDiary/Features/MealInputView.swift` 整块卡片改为 `Button(action: onCamera)`；
  烟包编辑页的「拍好，AI 自动识别」卡片同样处理
  （`MealInputView.swift` / `SmokingPackEditorView.swift`，id `takePhotoCard` / `scanPackCard`）。
  提交 `b63e555`。
- **验证**：真机点击卡片直接进相机；重构后仍能走相册与手输兜底。

## 2026-11-05 · 回归缺口补齐

### 10. 客户端照片同步从来没有真正跑过

- **症状**：同步回归脚本对 `/v1/sync/photos/*` 一律抛 `URLError(.unsupportedURL)`，
  照片实际上传（`Sources/NutritionCore/CloudPhotoSync.swift:11`）与下载（`:39`）从未被执行。
  服务端「先传照片再发快照、缺照片 422」的约束在客户端是纸面约定。
- **修复**：`Tests/AppRegression/SyncModelRegression.swift` 的 fixture 现在实现
  `/v1/sync/photos/missing`、`PUT/GET /v1/sync/photos/{name}`（校验 Bearer、`image/jpeg`、
  文件名与内容哈希一致），`DiaryModel` fixture 改用真实临时 `Photos/` 目录；
  主流程断言本机照片上传且服务端只收一次、云端照片落到本机 `Photos/`、合并后两条引用都还在。
- **验证**：`bash Tests/AppRegression/run-sync-model.sh` 两种模式均输出
  `PASS — photos travelled both ways (1 uploaded, 1 downloaded) and stayed referenced`。

### 11. AI 拒绝授权后像「点了没反应」

- **症状**：点「暂不使用 AI」后弹窗消失，调用方 `catch is CancellationError {}` 静默吞掉，
  页面无任何反馈，用户会以为按钮坏了或分析正在后台悄悄进行。
- **修复**：`FoodDiary/Services/AIConsent.swift` 新增 `declinedNotice`（拒绝时写入、再次请求时清空）；
  `FoodDiary/Features/AIConsentModifier.swift` 在顶部浮层显示「已取消，本次没有发送任何内容」，
  4 秒后自动消失。视图消失（`cancelPending`）不算拒绝，保持安静。
- **验证**：`Tests/AppRegression/run-ai-consent.sh` 新增两条断言（拒绝有提示、取消不提示）。

### 12. 通知权限被关闭时提醒开关「看似开着，永远不响」

- **症状**：`ReminderScheduler.reschedule` 在权限被拒时 `return` 得无声无息，
  设置页开关仍是打开状态，用户不知道要去系统里允许通知。
- **修复**：新增 `ReminderScheduling`（`.scheduled` / `.notificationsDenied`），
  `reschedule` 返回结果；`FoodDiary/Features/GeneralSettingsView.swift` 在有提醒开启且返回
  `.notificationsDenied` 时，于提醒区显示说明与「打开系统设置」按钮
  （id `notificationDeniedNotice` / `openNotificationSettings`）。
- **验证**：`xcodebuild` DEBUG 构建通过；真机在系统通知关闭状态下进入设置页可见提示。

### 13. 服务端四条边界没有测试（413 / 内嵌照片 / 坏 200 / 越权恢复）

- **修复**：`server/tests/test_sync.py` 新增 body 超限 413、内嵌 JPEG 快照可通过、
  外部照片必须先上传、四种非法照片名 422、B 用户 versions 为空且 restore 404；
  `server/tests/test_ai.py` 新增五种「200 但结构不对」响应与 >256KB 响应映射 502。
- **验证**：`server/api/.venv/bin/python -m pytest -q` → **82 passed**（原 68）。

## 2026-11-05 · P2 清理

### 14. 两台设备各自生成的「近7天」汇总会同时留下

- **症状**：本机保存汇总时按周期覆盖（每个范围只留一份），云同步合并却按 id 取并集。
  两台设备各自生成一份同周期报告，合并后同屏出现两份结论；下次在本机再存又变回一份。
- **修复**：`Sources/NutritionCore/CloudSync.swift` 新增 `oneReviewPerPeriod`，
  合并时按 `snapshot.period` 收敛到 `generatedAt` 最新的一条。
- **验证**：`CloudSyncTests::mergesWellnessReviewsByPeriod`（两份同周期合并后只剩新的）。

### 15. 重复 id 的复盘能通过校验

- **修复**：`Sources/NutritionCore/Models.swift` 的 `validate()` 补上
  `reviews` 与 `wellnessReviews` 的 id 唯一性检查，重复即 `unreadableDiary`。
- **验证**：`CloudSyncTests::duplicateReviewIdentifiersAreRejected`。

### 16. 服务端 413 提示写死「8 MB」，改配置后会说谎

- **修复**：`server/api/app/main.py` 新增 `human_bytes(limit)`，提示文案跟随 `max_payload_bytes`；
  顺手删掉 `server/api/app/security.py` 里零调用的 `constant_time_equals` 与 `hmac` 导入；
  `test_auth.py` 补三种非法新密码 422 与「改密后当前会话仍可用」。
- **验证**：`pytest` **85 passed**（82 → 85）。

### 17. 下线文件式 CSV / JSON 导入导出

- **决定**：用户拍板（m03002）「已经做了云端就没必要用文件传输」。
- **改动**：删除 `Sources/NutritionCore/DiaryCSV.swift`、`FoodDiary/Features/CSVFileDocument.swift`、
  `FoodDiary/Features/JSONBackupDocument.swift`、`Tests/NutritionCoreTests/DiaryCSVTests.swift`；
  `GeneralSettingsView` 的「本机数据」只保留餐数、照片目录、每天自动备份与最近备份时间；
  `DiaryModel.restoreBackup` 一并删除（唯一调用方是已移除的导入向导）。
  **保留** 每天自动备份与恢复点（`DiaryBackup` + `BackupService`），那是本机防损坏的兜底，不属于文件传输。

## 2026-11-05 · 抽烟费用

### 18. 说「我抽了两根」只减了库存，这两根的花费一直没算

- **症状**：在识别烟盒的输入框里写「这包烟二十，我抽了两根」，包建好了、余量显示 18，
  但今日「自己抽的折算费用」是「—」，历史里也找不到这两根。用户反馈「这包烟是自己买的，花的是自己的钱」。
- **根因**：`CigaretteTextHints.openingCount()` 把「抽了两根」换算成开包余量 18，
  `SmokingPackEditorView.save()` 只写 `openingCount`，从不生成 `SmokingEvent`。
  日汇总与累计都按事件流算，没有事件自然没有根数、尼古丁和花费。
- **修复**：
  - 新增 `CigaretteOpeningPlan.make(from:)`：说余量按余量开包；说抽了几根则按满包开，
    并把这几根作为待补记事件返回；
  - `SmokingPackEditorView` 保存时把待补记根数写成一条 `smoked` 事件，编辑旧包时补记到该包；
  - `SmokingDiary.record(_:count:packID:date:)` 让补记落到指定烟包（当前烟包可能已经换了），
    `DiaryModel.recordSmoking(_:count:packID:)` 与之对接；
  - 花费口径统一为「每包价 ÷ 20 × 根数」：`SmokingStats.totals` 原先按 `openingCount` 折算，
    半包开包时会多算，现在与日汇总、README 一致，也去掉了 `openingCount > 0` 的静默跳过。
- **验证**：`swift test` **222 项**。新增 `CigaretteTextParserTests::openingPlanRecordsSmokedInsteadOfShrinkingThePack`、
  `SmokingStatsTests::priceCountsPerWholePack`（开包余 5 根仍按 20 支折算）、
  `SmokingStatsTests::recordsIntoTheNamedPack`（补记落到旧包、余量各自扣、未知烟包报错）。

## 2026-11-05 · 追问质量

### 19. 不管问什么，蛙都劝「先连续记录 7 天」

- **症状**：用户问「我要减肥，该吃多少卡路里」「跑完步晚饭吃什么」，回答都是
  「这段记录还看不出……建议先连续记录 7 天」。用户原话：「不能给出明确的建议或者意见，这样用户会很烦」。
- **根因**：`ObservationClient.askPrompt` 有两处反向指令——第 2 条要求「数据不足时直接说『这段记录还看不出』」
  第 3 条要求「没有目标时不要编造目标」，模型于是把「拒绝回答」当成结论；
  `WellnessReview.swift` 的示例 action 又直接写成「连续记录一周」，进一步强化了这个套路。
- **修复**：
  - `askPrompt` 重写为 8 条硬规则：第一句必须直接给结论；结论必须落到千卡/克数/份量/分钟；
    缺数据时先给今天能做的方案、再说明假设，「多记几天会更准」最多结尾一句；
    没有 target 时按 `averageCalories`、体重给出参考区间（减脂 1.2–1.6 克/公斤蛋白、不低于 1200 千卡）并标「估算」；
    食物与运动给常见量（香蕉 90–105 千卡、76 公斤跑 30 分钟约 300 千卡）；末尾最多 3 条「·」建议；
  - `wellnessPrompt` 增加「行动必须今天就能执行，不能把再记录几天当唯一行动」，示例 action 换成「晚餐加一份蛋白」；
  - 界面提示改为「回答会给出具体数字和今天能做的做法；推算会标成估算」，旧答案标签由「基于旧数据」改为「按当时的记录」。
- **验证**：`swift test` **224 项**。新增 `ObservationTests::askPromptDemandsConcreteAdviceInsteadOfPunting`、
  `WellnessTests::wellnessPromptAsksForConcreteActions`；Debug 构建装到真机（1.0.2 / 38）。

### 20. 汇总分析把「11月4日 7支」写成「11月3日 7支」，而且每段都在说「难以判断」

- **症状**：近 30 天的汇总分析写「11月3日自抽 7 支、11月4日 9 支、分给别人 2 支」，
  实际记录是「11月4日 7 支、11月5日 9 支、分给别人 1 支」。同一天的近 7 天报告却是对的。
  另外摘要以「难以判断整体饮食质量」收尾，四类观察每段都重复「记录少、无法判断」，
  五条 limitations 说的是同一个缺口，分段控件一滚就看不见。
- **根因**：`makeWellnessRequest` 用 `.iso8601` 编码，本地零点被写成 UTC——
  本地 11-04 00:00 变成 `2026-11-03T16:00:00Z`，模型按 UTC 读就报成 11 月 3 日；
  timeline 里只有饮食/吸烟/活动的分项，没有逐日体重；快照里没有覆盖度这类数字，
  模型只能用「记录不足」来兜底；提示词又要求「每类缺少数据时明确说明」，于是每段都免责。
  连「全部记录」也常看起来和近 7 天一样，因为实际数据只跨了几天。
- **修复**（`fd63c8e`）：
  - 请求里的日期全部换成快照本地字符串：`startDate`/`endDate`/`timeline[].date` 为 `yyyy-MM-dd`，
    体重日期为 `yyyy-MM-dd HH:mm`，提示词明确「直接按字面引用，不要换算时区、不要加减天数」；
    并规定「分日数字只能来自 timeline，不得挪到另一天，不得编造没出现过的日期」。
  - `WellnessTrend` 增加 `weightKG`（旧报告缺该键解码为 nil），只有体重的日子也进时间线。
  - 新增 `WellnessCoverage`（窗口天数与饮食/吸烟/体重/活动各有几天），随请求作为 `coverage` 下发；
    没设参考目标时用 `EnergyCalculator` 在本地算一个 `suggestedTarget` 并标明是估算。
  - `wellnessPrompt` 改为结论先行：summary 第一句必须是带数字的结论；覆盖度只出现一次；
    每类观察不再重复免责；`limitations` 最多 2 条并合并同类缺口；解析时也截到 2 条
    （`validate()` 仍允许 8 条，旧报告不会因此读不出来）。
  - UI：7/30/全部 与「覆盖 N/M 天」吸顶；结论卡加数字 chip（日均千卡、自抽支数、日均步数）；
    四类观察默认收起；两个重复的折叠区合并成「数据范围与缺口」，缺口只留底部一行。
- **验证**：按用户要求先提交、暂未跑 `swift test` / `xcodebuild`（只做了 `swiftc -parse` 语法检查），
  与另一批灵动岛改动一起进入 `fd63c8e`；构建与全量回归待统一执行。

### 21. 一桶 140 克的方便面只算出 467 千卡，而且看不到「份量是估的」

- **症状**：拍营养成分表记一桶香辣牛肉面，App 给 467 千卡（= 1955 kJ ÷ 4.184 的每 100 克值），实际整桶 140 克是 654 千卡，少算 187；界面也没提示份量是推算的。
- **根因**：标签只标每 100 克，照片里没有净含量时，模型静默按「整包 = 100 克」算；`portionIsEstimated` 只当成一行小字，没有可操作的修正入口；一餐只能带一张照片，营养表和包装正面没法一起拍。
- **修复**：
  - `DeepSeekClient.makeRequest(text:images:mode:)` 支持最多 `maxPhotos = 3` 张照片，单图重载保留；服务端 `validated_body` 从「最多 2 段、1 张图」放宽到「最多 4 段、3 张图」。
  - `MealDraft.photos` 成为照片真源（首张仍写进 `record.photoJPEG`），`MealInputView` 改成横向缩略图 + 每张可移除，加删照片会 `MealRecord.clearEstimate()` 让旧结果作废。
  - 提示词新增四条硬规则：默认按整份（没吃剩就整碗/整包）、汤类按 90%、无净含量时按品类常见包装量估算、多张照片合并读取；`FoodAnalysisMode.label` 的说明同步要求找净含量。
  - 新增 `Sources/NutritionCore/PackagedSizes.swift`：按食物名给「整桶 120/140 克」「整袋 105 克」等候选、识别汤汤水水；`FoodPortionView` 加「按整包记更准」卡片（整包 chip + 「汤没喝，按 90% 算」），`NutritionLabel.withConsumedAmount(_:)` 选完整包后把 `portionIsEstimated` 置为 false。
  - 结果页把「营养标签 · 份量估算」改成「份量是估的，可改成整包」。
- **验证**：`swift test` **229 tests / 30 suites passed**（新增多图上限、提示词规则、`PackagedSizes`、整包换算 4 组）；`server/api/.venv/bin/python -m pytest ../tests -q` 从 `server/api` 目录运行 **89 passed**（新增 1/2/3 张图放行、4 张图 422）；Debug `xcodebuild` BUILD SUCCEEDED。真实端点复测（单图 + 「整桶都吃了，汤没喝完」）：模型给出 99 克（按常见 110 克 × 0.9）、假设写「汤没喝完，按整桶约90%计」「图片未显示净含量，按常见桶装方便面约110克估算」，整桶 140 克的修正在 UI 里一键可选。
- **部署**：服务端在 `sub2api-US`（154.201.78.199，`/opt/xiaoshitanji-sync`，无 git，靠传文件 + `docker compose up -d --build api`）。已把 `api/app/{ai,main,security}.py` 传上去重建，`/healthz` 返回 `{"status":"ok","schemaVersion":5,"photoTransferVersion":1}`。
- **线上复测**（两张图：营养表 + 包装正面，文字「一桶香辣牛肉面，整桶都吃了，汤没喝完」）：返回 126 克（140 × 0.9）、能量约 589 千卡，假设写「汤没喝完，按整桶约90%计」「净含量按包装标注的面饼+配料140克估算」——与手工核算的 654 千卡整桶、不喝汤约 590 千卡一致。

### 22. 不管几点记录，时间都写成晚上 8 点

- **症状**：点「晚餐」或从首页记一餐，录入页的时间默认是 20:00；18:20 记的晚餐也被写成 20:00，超过当下的时间只能被 DatePicker 的上限拦住。
- **根因**：`Sources/NutritionCore/Models.swift` 的 `MealRecord.usePresetTime(for:)` 按餐次查表：早餐 08:45、午餐 12:00、**晚餐 20:00**（只有加餐取当前时刻）。首页点行、扫描记一餐（按时间猜成晚餐）、以及在录入页把餐次拨成晚餐，三条路径都会落到 20:00。
- **修复**：
  - `MealRecord.draft(on:kind:now:calendar:)` 改成统一调用新的 `useClockTime(_:calendar:)`：取「现在」的时分秒放到所选日期上，餐次只决定归类；
  - 删除 `usePresetTime(for:)`，拆成 `useClockTime(_:calendar:)`（只改时间）与 `applyKind(_:)`（只改餐次），`ComposerView` 拨餐次时不再改时间；
  - `MealInputView` 说明文案改为「默认记成现在的时间，可点开改成实际用餐时间。」；
  - 设置里的提醒时间（8:00 / 12:10 / 18:00）保持不变，只发通知，不再影响记录时间。
- **验证**：`swift test` **231 tests / 30 suites passed**（改写 3 条 + 新增「18:20 记晚餐仍是 18:20」「切餐次不改时间」「五个餐次窗口边界」共 6 条）；`Tests/AppRegression/run-widget.sh` 9 条 PASS（同步修正了深链草稿的期望时间）；Debug 与 Release 的 `xcodebuild -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO` 均 BUILD SUCCEEDED。真机安装需设备重新连接后验证。

## 更早版本（据提交记录整理，供追溯）

这些修复发生在本轮之前，细节未逐条复述，回归时按标题排查：

| 提交 | 修复内容 |
|---|---|
| `b0fb34d` | `commit(_:)` 保存复盘时递归调用自己导致栈溢出 |
| `a0f736a` | 小组件快照写到了 App Group 根目录之外，桌面读不到 |
| `d778122` | 旧版健康报告解码失败会连带整个日记打不开 |
| `a6bbd2a` | 同步与备份流程会丢照片和记录 |
| `29d4d09` | 设置页显示硬编码版本号，升级后对不上 |
| `0a4e34e` | 晚餐用了和午餐一样的图标 |
| `e9bce0e` | 烟盒扫描重复创建烟包、状态串位 |
| `82e2e86` | App 图标裁切发虚（改用原始抠图） |

## 工具链坑（不是 App 缺陷，但会误判成 bug）

| 现象 | 原因 | 处理 |
|---|---|---|
| `swift test` 报 `external macro implementation type 'TestingMacros.ExpectMacro' could not be found` | 默认 `xcode-select` 指向 CommandLineTools，其 Swift 6.4 不带 Testing 宏 | 一律 `DEVELOPER_DIR=/Volumes/OS/Applications/Xcode.app/Contents/Developer swift test` |
| `xcodebuild` 报 `Unable to resolve module dependency: 'NutritionCore'` | DerivedData 陈旧 | `rm -rf ~/Library/Developer/Xcode/DerivedData/FoodDiary-*` 后重建 |
| 所有接口 422 `{"loc":["query","request"]}` | `get_session(request)` 少了 `Request` 注解，FastAPI 当成必填查询参数 | 补注解 |
| App Store Connect API 401 `NOT_AUTHORIZED` | `altool --generate-jwt` 把 JWT 打到 stderr，直接赋值拿到空串 | `2>&1 \| grep "^eyJ"` 取 token |
| 上传后 `/v1/builds` 立即查询返回 `[]` | 构建仍在处理（10–30 分钟） | 等待后重查 |
| `git push` 报 SSL timeout / HTTP2 framing | 本地网络到 GitHub 不稳 | 重试，或走系统代理 `http://127.0.0.1:7897` |
