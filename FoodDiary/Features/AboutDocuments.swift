import Foundation

enum AppInformation {
    static let author = "爬爬 · Jay He"
    static let contactEmail = "2296900700@qq.com"
    static let updatedDate = "2026 年 11 月 5 日"
    static let privacyURL = URL(string: "https://xiaoshitanji.papaclaoud.top/privacy")!
    static let supportURL = URL(string: "https://xiaoshitanji.papaclaoud.top/support")!
    static let emailURL = URL(string: "mailto:2296900700@qq.com")!
    static let deepSeekPrivacyURL = URL(string: "https://cdn.deepseek.com/policies/zh-CN/deepseek-privacy-policy.html")!
    static let applePrivacyURL = URL(string: "https://www.apple.com/legal/privacy/")!

    static var versionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String
        return build.map { "版本 \(version)（\($0)）" } ?? "版本 \(version)"
    }
}

struct AboutSection: Identifiable {
    let title: String
    let content: String
    var id: String { title }
}

enum AboutDocument: String, CaseIterable, Identifiable {
    case terms, privacy, permissions, personalInformation, thirdParties
    var id: Self { self }

    var title: String {
        switch self {
        case .terms: "用户协议"
        case .privacy: "隐私说明"
        case .permissions: "应用权限说明"
        case .personalInformation: "个人信息清单"
        case .thirdParties: "第三方 SDK 与服务"
        }
    }

    var subtitle: String {
        switch self {
        case .terms: "服务内容、使用规则与数据管理"
        case .privacy: "了解数据如何保存、发送和删除"
        case .permissions: "每项能力的用途与管理方式"
        case .personalInformation: "数据类型、处理场景与控制入口"
        case .thirdParties: "实际使用的系统能力和外部服务"
        }
    }

    var artwork: String {
        switch self {
        case .terms: "ProfileObservation"
        case .privacy: "MilkFrogPeek"
        case .permissions: "ProfileSettings"
        case .personalInformation: "HealthScale"
        case .thirdParties: "ProfileCloud"
        }
    }

    var sections: [AboutSection] {
        switch self {
        case .terms:
            [
                AboutSection(title: "服务与开发者", content: "小食痰记由\(AppInformation.author)开发和维护，用于个人饮食、身体测量、运动及吸烟习惯记录。联系邮箱为 \(AppInformation.contactEmail)。本协议说明本应用的使用规则，数据处理详情见隐私说明。"),
                AboutSection(title: "使用范围", content: "本应用面向成年人。你可以使用本机记录、营养估算、趋势和生活习惯分析等功能，按需要选择 Apple 健康、AI 分析及云端同步。吸烟模块用于了解和改善自己的吸烟习惯，请如实区分自己抽的数量与分给别人的数量。"),
                AboutSection(title: "AI 结果与健康信息", content: "AI 识别可能误读照片、标签或份量，请检查并确认后保存。餐食热量、营养与 BMI 等供日常记录参考。身体不适或需要诊疗时，请向专业医疗人员咨询。烟盒尼古丁标注累计是记录值，不能代表人体实际吸收量。"),
                AboutSection(title: "AI 服务的使用", content: "当前 AI 功能免费提供并设有公平使用额度。授权后，分析所需文字、所选照片或经确认的健康汇总会经小食痰记服务器转交 DeepSeek。你可以在通用设置撤回 AI 数据授权。请仅提交你有权处理的内容，并合理使用服务。"),
                AboutSection(title: "可选同步账号", content: "云端同步需要单独创建或登录账号。请妥善保管账号和密码。你可以在“我的 → 云端同步”登录后同步记录，或通过“删除云端账号”移除账号及其云端日记、照片和版本历史。本机记录由你在设备上管理。"),
                AboutSection(title: "记录、备份与权利", content: "请定期通过通用设置导出需要保留的数据。你录入的记录与照片由你管理，软件和相关素材按适用法律及授权范围使用。网络或识别暂时不可用时，可保留输入稍后重试，或使用手动记录。"),
                AboutSection(title: "变更与联系", content: "服务或条款更新会随应用版本及相关页面公布。关于功能、隐私、数据处理或使用规则的问题，请联系 \(AppInformation.contactEmail)。")
            ]
        case .privacy:
            [
                AboutSection(title: "本机保存", content: "饮食、营养数值、照片、个人资料、体重、训练、烟包和吸烟记录，以及你保存的分析结果，默认由应用保存在设备上。本机自动备份和你导出的文件需一并妥善保管。云端同步由你主动使用。"),
                AboutSection(title: "AI 分析的授权与发送", content: "首次使用 AI 时会说明接收方、内容和用途，并等待你明确同意。根据所用功能，本次所需的食物描述、问题、所选餐食／营养表／烟盒照片、营养数据或经确认的健康聚合数值，会通过 HTTPS 发送至 xiaoshitanji.papaclaoud.top，再转交 DeepSeek API 处理。可在“通用设置 → AI 与隐私”撤回授权。"),
                AboutSection(title: "健康数据", content: "连接 Apple 健康后，只读访问你允许的步数、活动、训练、身体测量、睡眠、心率等项目，用于本机展示和聚合。汇总分析发送前仍会逐次确认数据范围。AI 请求使用所选汇总数值，原始健康样本保留在设备。保存的报告和汇总快照可随主动云同步上传。"),
                AboutSection(title: "照片与语音", content: "相机由扫描操作触发，相册通过系统选择器取得你选中的图片。用于记录的照片会被处理为压缩图片并去除原始位置等元数据。语音用于转为文字，设备支持时在本机识别，其他情况下由 Apple 语音识别服务处理。你可以在系统中管理相关权限。"),
                AboutSection(title: "可选云端同步", content: "同步服务器保存用户名、密码校验哈希、会话令牌哈希、设备显示名称、日记快照、照片及版本历史。快照可包含个人资料、饮食、体重、运动、吸烟记录和已保存的健康汇总与报告。登录令牌保存在本机钥匙串，传输使用 HTTPS。"),
                AboutSection(title: "服务日志与保存期限", content: "AI 网关为本次请求转发内容，应用数据库保存每日调用计数和每日变化的网络散列，用于限流与公平使用。较早计数会在后续请求时清理。常规访问日志可包含 IP、时间、路径、状态码等，用于安全维护与排障，并随服务器日志轮转清理。DeepSeek 对请求内容的处理和保留适用其隐私政策。你主动保存的 AI 结果作为日记内容管理。"),
                AboutSection(title: "数据控制与删除", content: "可在各条记录详情中修改或删除本机内容，在通用设置导出完整备份或 CSV。云端账号删除入口位于“我的 → 云端同步”，会删除生产服务中的账号、令牌、日记、照片和版本历史。故障恢复备份可能保留此前数据，相关删除请求可通过邮箱提出。导出文件、其他设备及系统备份由你分别管理。"),
                AboutSection(title: "隐私选择与联系", content: "本版本使用本项目模块与 Apple 系统框架，未嵌入广告或跨应用追踪 SDK。健康数据用于你选择的记录和分析功能。你可撤回 AI 授权、管理系统权限、停止同步或删除账号。隐私与数据处理问题请联系 \(AppInformation.contactEmail)，线上完整政策可通过下方入口查看。")
            ]
        case .permissions:
            [
                AboutSection(title: "相机", content: "用途为拍摄餐食、营养成分表和烟盒。扫描时由系统请求相机权限。可在 iOS 设置中管理；也可使用系统照片选择器导入图片。"),
                AboutSection(title: "照片选择", content: "使用 iOS 系统照片选择器读取你选中的图片，用于记录、识别或设置头像。所选图片的后续使用取决于相应功能和 AI、同步授权。"),
                AboutSection(title: "麦克风与语音识别", content: "用于把你说的一餐转成可编辑文字，首次使用语音输入时由系统请求麦克风和语音识别权限。支持设备端识别时优先本机处理，其他情况下使用 Apple 语音识别服务。可在 iOS 设置中管理，文字输入也可直接使用。"),
                AboutSection(title: "Apple 健康", content: "只读访问你允许的步数、活动能量、锻炼时间、距离、身高、体重、睡眠、心率、静息心率、心率变异性、有氧适能、耳机音量和体能训练。各项可在健康 App 的个人资料 → App → 小食痰记中管理。应用仅能读取系统允许返回的数据。"),
                AboutSection(title: "通知", content: "用于本地饮食和称重提醒，安排提醒时由系统请求权限。提醒内容和时间可在通用设置调整，通知权限可在 iOS 设置中管理。"),
                AboutSection(title: "实时活动与小组件", content: "按你的操作在锁定屏幕、灵动岛或桌面展示记录概况。小组件与主程序通过同一设备的 App Group 文件共享摘要。实时活动可在应用对应的系统设置中管理，小组件可在系统桌面编辑。"),
                AboutSection(title: "网络与 AI 数据授权", content: "AI 请求、主动云同步及打开在线支持页需要网络。AI 数据授权可在通用设置撤回，云同步通过同步账号单独管理。联网权限如由系统提供开关，可在应用的 iOS 设置中调整。")
            ]
        case .personalInformation:
            [
                AboutSection(title: "个人资料与身体测量", content: "内容为昵称、头像、身高、体重、目标体重及相关测量日期，用于个人展示、BMI 和体重趋势。本机保存，主动云同步时可一并上传。可在“我的”编辑资料和管理体重记录。"),
                AboutSection(title: "饮食与照片", content: "内容为餐次、时间、食物描述、份量、营养标签、估算数值、修正和所选照片，用于记餐及趋势。本机保存，AI 所需部分经授权发送给后端和 DeepSeek；主动云同步可包含完整记录和照片。可在餐食详情编辑、删除或导出。"),
                AboutSection(title: "吸烟与烟包", content: "内容为香烟名称、包装标注、价格、烟包余量、照片、抽烟与分烟数量及日期，用于个人习惯和费用统计。本机保存，识别所需内容经授权用于 AI，主动云同步可包含这些记录。可在戒烟模块管理烟包与历史。"),
                AboutSection(title: "运动及 Apple 健康", content: "内容为手动训练记录，以及你允许读取的活动、身体、睡眠、心率等健康数据。系统原始样本在本机读取，所选聚合数值经确认可用于 AI；保存的报告及汇总快照可进入主动云同步。可在训练详情、健康 App 和分析范围选择中管理。"),
                AboutSection(title: "问题与分析报告", content: "内容为你提出的问题、分析范围、聚合上下文、回答和报告，用于解读已有记录。发起 AI 时经授权处理，保存后作为本机日记内容，并可导出或同步。可在相应分析页面管理历史回答。"),
                AboutSection(title: "语音输入", content: "内容为语音识别过程中的声音和转写文字。声音用于 Apple 语音识别，文字可由你编辑并用于记餐和 AI。应用的日记保存转写后的内容，设备支持时声音在本机识别，其他情况下由 Apple 服务处理。"),
                AboutSection(title: "同步账号与会话", content: "内容为用户名、密码验证信息、会话令牌、设备显示名称和版本记录，用于认证与同步。服务器保存密码和令牌的哈希，设备钥匙串保存登录会话。可退出同步账号，或登录后删除云端账号。"),
                AboutSection(title: "设置、调用计数与日志", content: "本机保存目标、提醒和授权状态，用于执行你的设置。后端使用调用计数、每日网络散列及常规访问日志进行公平使用限制、安全维护和排障。计数、日志和故障恢复备份按各自清理流程管理，处理详情见隐私说明。")
            ]
        case .thirdParties:
            [
                AboutSection(title: "本机依赖概况", content: "当前安装包使用本项目 NutritionCore 模块及 Apple 系统框架，未嵌入第三方广告、统计、社交登录或 DeepSeek 客户端 SDK。下面列出实际参与相关功能的外部服务和系统能力。"),
                AboutSection(title: "DeepSeek AI 服务", content: "接收方为 DeepSeek（深度求索），通过小食痰记后端调用其 API。用于餐食与营养表识别、烟盒识别、自然语言修正、回顾、追问和汇总建议。按所选功能处理必要文字、压缩图片、营养数据或经确认的健康聚合数值。发起条件为你主动使用 AI 并明确授权，处理规则见下方 DeepSeek 隐私政策。"),
                AboutSection(title: "Apple 系统服务", content: "HealthKit 用于只读健康数据，PhotosUI 和相机用于你选择或拍摄的图片，Speech 与 AVFoundation 用于语音输入，UserNotifications 用于本地提醒，WidgetKit、ActivityKit 与 App Intents 用于系统小组件、实时活动和快捷操作，Security 用于钥匙串会话保存。语音在设备支持时本机识别，其他情况下可由 Apple 服务处理。系统数据处理规则见 Apple 隐私政策。"),
                AboutSection(title: "小食痰记后端", content: "由开发者维护，地址为 xiaoshitanji.papaclaoud.top，提供 AI 转发、用量限制及可选的账号与日记同步。AI 转发内容和同步保存内容按各自功能处理。此服务与本应用的隐私说明及联系入口一致。")
            ]
        }
    }
}
