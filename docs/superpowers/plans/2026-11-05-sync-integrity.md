# 同步完整性修复计划

使用executing-plans逐项实施，结束时一次独立只读审查。
Spec为docs/superpowers/specs/2026-11-05-sync-integrity.md。

- [x] 1. 服务端schema5与用户隔离的照片传输、哈希校验、幂等和快照引用校验，先补失败API测试。
- [x] 2. Core照片边界转换、独立传输、workouts/plans合并，App同步与恢复入口接入，覆盖首次同步/并发重试。
- [x] 3. 自包含备份与导出/恢复，包括烟盒图片、旧文件升级、源图缺失与写入失败保护。
- [x] 4. 整理Debug截图工具，修复编译警告，统一版本/文档；完整测试、签名构建和独立审查。
- [x] 5. 核验线上服务、部署兼容修复，确认TestFlight可见状态，提交完整修复与实际验证记录。

照片失败不得发布不完整快照，下载失败不得覆盖本机文档，历史照片不可被新照片覆盖，备份失败不得丢掉旧文件，所有新接口按当前账号隔离。保留既有存储及数据保护设置。

## 回归与审查记录

- 服务端新增测试先观察到 8 项失败，修复后完整套件 42 项通过。
- Swift 完整套件 206 项，205 项通过，1 项显式演示工具跳过。新增测试覆盖旧日期格式、同日元数据备份补图、恢复点保留与损坏源图拒绝。
- Tests/AppRegression/run-sync-model.sh 运行实际 SyncModel，隔离钥匙串、设备名称与存储边界。恢复完整合并与冲突重试、旧账号无归属基线迁移，两项通过。旧代码对应路径已观察到失败。
- 独立只读审查提出的 5 项 Important 均已修复，最终没有未解决的 Critical 或 Important。额外修复历史版本查询参数被编码进路径的问题。
- 2026-11-05 线上 API 已升级，健康检查返回 schemaVersion 5 和 photoTransferVersion 1。临时账号通过照片往返、账号隔离、两设备令牌并发冲突、去重、历史图片与版本恢复验证。
- 升级前源码、配置与 PostgreSQL 备份保存在服务器 /opt/sub2api-backups/xiaoshitanji-repair-20261105T013451Z。
- App Store Connect 已核验 1.0（29）与 0.16.0（27）处理为 VALID，内部 READY_FOR_BETA_TESTING，外部 READY_FOR_BETA_SUBMISSION。1.0.1（31）本轮尚未上传，测试组分发状态待确认。
- 当前实体 iPhone unavailable，设备安装与相机、键盘、实际多设备交互验收等待连接。
- 最终 Debug / Release 构建通过，日志无编译警告，主程序及内嵌小组件四份签名全部验证，App Group 与主程序 HealthKit 权限有效。临时账号删除后数据库核验用户数与孤立照片数均为 0。
