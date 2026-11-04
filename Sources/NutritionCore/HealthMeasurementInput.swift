import Foundation

public enum HealthMeasurementInput {
    public static func format(_ value: Double?) -> String {
        value.map {
            $0.formatted(.number.locale(Locale(identifier: "en_US_POSIX"))
                .grouping(.never).precision(.fractionLength(0...3)))
        } ?? ""
    }

    public static func parse(_ text: String) throws -> Double? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        guard let value = Double(text.replacingOccurrences(of: ",", with: ".")), value.isFinite else {
            throw DiaryError.invalidInput("请填写有效数字，可使用小数点或小数逗号。")
        }
        return value
    }
}
