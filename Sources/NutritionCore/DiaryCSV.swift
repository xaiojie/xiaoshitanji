import Foundation

/// 把日记导出成 CSV：给营养师看、自己丢进表格都行。
public enum DiaryCSV {
    public static let mealsHeader = "日期,时间,餐次,食物,克数,热量,蛋白质,碳水,脂肪,来源,备注"
    public static let weightsHeader = "日期,体重(kg),来源"
    public static let smokingHeader = "日期,时间,事件,数量,香烟"

    public static func meals(_ document: DiaryDocument, calendar: Calendar = .current) -> String {
        var rows = [mealsHeader]
        let dayFormatter = DateFormatter()
        dayFormatter.calendar = calendar
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")
        dayFormatter.dateFormat = "yyyy-MM-dd"
        let timeFormatter = DateFormatter()
        timeFormatter.calendar = calendar
        timeFormatter.locale = Locale(identifier: "en_US_POSIX")
        timeFormatter.dateFormat = "HH:mm"

        for record in document.records.sorted(by: { $0.date < $1.date }) {
            for food in record.foods {
                let nutrition = food.nutrition
                let notes = [record.summary, (record.adjustments ?? []).joined(separator: "；")]
                    .filter { !$0.isEmpty }.joined(separator: "；")
                rows.append([
                    dayFormatter.string(from: record.date),
                    timeFormatter.string(from: record.date),
                    record.kind.title,
                    food.name,
                    number(food.grams, digits: 0),
                    number(nutrition.calories, digits: 0),
                    number(nutrition.protein, digits: 1),
                    number(nutrition.carbohydrates, digits: 1),
                    number(nutrition.fat, digits: 1),
                    record.source.title,
                    notes
                ].map(escape).joined(separator: ","))
            }
        }
        return rows.joined(separator: "\r\n") + "\r\n"
    }

    public static func weights(_ document: DiaryDocument, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        var rows = [weightsHeader]
        for weight in document.weights.sorted(by: { $0.date < $1.date }) {
            rows.append([
                formatter.string(from: weight.date),
                number(weight.kilograms, digits: 1),
                weight.source == .manual ? "手动" : "Apple 健康"
            ].map(escape).joined(separator: ","))
        }
        return rows.joined(separator: "\r\n") + "\r\n"
    }

    public static func smoking(_ document: DiaryDocument, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        var rows = [smokingHeader]
        for event in document.smoking.events.sorted(by: { $0.date < $1.date }) {
            let pack = document.smoking.packs.first { $0.id == event.packID }
            rows.append([
                formatter.string(from: event.date),
                event.kind.title,
                "\(event.count)",
                pack?.product.name ?? ""
            ].map(escape).joined(separator: ","))
        }
        return rows.joined(separator: "\r\n") + "\r\n"
    }

    /// 生成三张表拼在一起的单文件，用空行分隔，方便直接导入表格软件。
    public static func document(_ document: DiaryDocument, calendar: Calendar = .current) -> String {
        [meals(document, calendar: calendar),
         "\r\n" + weights(document, calendar: calendar),
         "\r\n" + smoking(document, calendar: calendar)].joined()
    }

    public static func filename(now: Date = .now, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return "小食痰记-记录-\(formatter.string(from: now)).csv"
    }

    /// 写到临时目录，交给系统分享或文件导出。
    public static func write(_ document: DiaryDocument, now: Date = .now, calendar: Calendar = .current) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: filename(now: now, calendar: calendar))
        try self.document(document, calendar: calendar).write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    static func number(_ value: Double, digits: Int) -> String {
        String(format: "%.\(digits)f", value)
    }

    static func escape(_ field: String) -> String {
        let trimmed = field.replacingOccurrences(of: "\r\n", with: "\n")
        guard trimmed.contains(",") || trimmed.contains("\"") || trimmed.contains("\n") else { return trimmed }
        return "\"" + trimmed.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
