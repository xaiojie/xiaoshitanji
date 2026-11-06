import Foundation
import NutritionCore
import SwiftUI

enum RunFormat {
    static func distance(_ meters: Double) -> String { String(format: "%.2f", meters / 1000) }

    static func duration(_ seconds: Double) -> String {
        let value = max(0, Int(seconds))
        if value >= 3600 { return String(format: "%d:%02d:%02d", value / 3600, value / 60 % 60, value % 60) }
        return String(format: "%02d:%02d", value / 60, value % 60)
    }

    static func pace(_ seconds: Double?) -> String {
        guard let seconds, seconds.isFinite, seconds > 0 else { return "—" }
        let value = Int(seconds.rounded())
        return String(format: "%d′%02d″", value / 60, value % 60)
    }
}

struct RunMetric: View {
    let title: String
    let value: String
    var unit = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(Theme.mutedInk)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value).font(.system(.title2, design: .rounded, weight: .heavy)).monospacedDigit()
                    .minimumScaleFactor(0.7).lineLimit(1)
                if !unit.isEmpty { Text(unit).font(.caption).foregroundStyle(Theme.mutedInk) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

struct RunFrogHeader: View {
    let title: String
    let detail: String
    let artwork: String

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Text(title).font(.system(.title2, design: .rounded, weight: .heavy))
                Text(detail).font(.subheadline).foregroundStyle(Theme.mutedInk).fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Image(artwork).resizable().scaledToFit().frame(width: 138, height: 126).accessibilityHidden(true)
        }
        .padding(20)
        .background(Theme.yellowGradient, in: .rect(cornerRadius: 30))
    }
}
