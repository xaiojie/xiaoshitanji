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
  提交 `cf385ea`。
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
  提交 `413d30c`。
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
  detent 由 `[.medium, .large]` 改为 `[.height(300), .large]`。提交 `1a0023c`。
- **验证**：真机弹窗高度贴合内容，四个餐次与 AI 入口无需滚动。

### 9. 「拍下碗里的这一餐」卡片点不动

- **症状**：记餐页的大拍照卡只是静态卡片，必须点旁边小按钮才能开相机，与文案「拍下」不符。
- **修复**：`FoodDiary/Features/MealInputView.swift` 整块卡片改为 `Button(action: onCamera)`；
  烟包编辑页的「拍好，AI 自动识别」卡片同样处理
  （`MealInputView.swift` / `SmokingPackEditorView.swift`，id `takePhotoCard` / `scanPackCard`）。
  提交 `bdd951f`。
- **验证**：真机点击卡片直接进相机；重构后仍能走相册与手输兜底。

## 更早版本（据提交记录整理，供追溯）

这些修复发生在本轮之前，细节未逐条复述，回归时按标题排查：

| 提交 | 修复内容 |
|---|---|
| `5ef2536` | `commit(_:)` 保存复盘时递归调用自己导致栈溢出 |
| `6c13d6e` | 小组件快照写到了 App Group 根目录之外，桌面读不到 |
| `771d934` | 旧版健康报告解码失败会连带整个日记打不开 |
| `e0a1af7` | 同步与备份流程会丢照片和记录 |
| `e260c8f` | 设置页显示硬编码版本号，升级后对不上 |
| `f902c08` | 晚餐用了和午餐一样的图标 |
| `18c0018` | 烟盒扫描重复创建烟包、状态串位 |
| `095702a` | App 图标裁切发虚（改用原始抠图） |

## 工具链坑（不是 App 缺陷，但会误判成 bug）

| 现象 | 原因 | 处理 |
|---|---|---|
| `swift test` 报 `external macro implementation type 'TestingMacros.ExpectMacro' could not be found` | 默认 `xcode-select` 指向 CommandLineTools，其 Swift 6.4 不带 Testing 宏 | 一律 `DEVELOPER_DIR=/Volumes/OS/Applications/Xcode.app/Contents/Developer swift test` |
| `xcodebuild` 报 `Unable to resolve module dependency: 'NutritionCore'` | DerivedData 陈旧 | `rm -rf ~/Library/Developer/Xcode/DerivedData/FoodDiary-*` 后重建 |
| 所有接口 422 `{"loc":["query","request"]}` | `get_session(request)` 少了 `Request` 注解，FastAPI 当成必填查询参数 | 补注解 |
| App Store Connect API 401 `NOT_AUTHORIZED` | `altool --generate-jwt` 把 JWT 打到 stderr，直接赋值拿到空串 | `2>&1 \| grep "^eyJ"` 取 token |
| 上传后 `/v1/builds` 立即查询返回 `[]` | 构建仍在处理（10–30 分钟） | 等待后重查 |
| `git push` 报 SSL timeout / HTTP2 framing | 本地网络到 GitHub 不稳 | 重试，或走系统代理 `http://127.0.0.1:7897` |
