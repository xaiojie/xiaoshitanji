import SwiftUI
import NutritionCore

struct KeepGoingView: View {
    @Environment(DiaryModel.self) private var diary
    @Environment(\.dismiss) private var dismiss

    private var stats: DiaryStats { Milestones.stats(for: diary.document) }
    private var achievements: [Achievement] { Milestones.achievements(for: diary.document) }

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    FrogCallout(text: "青蛙的坚持", detail: "记录攒下来的东西，都在这儿。")
                    streakCard
                    summaryRow
                    smokingCard
                    Text("里程碑").font(.headline).padding(.top, 4)
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(achievements) { achievement in
                            badge(achievement)
                        }
                    }
                }
                .padding(20)
            }
            .background(Theme.background)
            .navigationTitle("成果").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } }
            }
        }
    }

    private var streakCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(stats.currentStreak)").font(.system(size: 64, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.ink)
                Text("天").font(.title3).foregroundStyle(Theme.mutedInk)
                Spacer()
                Image("MilkFrogPeek").resizable().scaledToFit().frame(width: 58, height: 66)
                    .accessibilityHidden(true)
            }
            Text(stats.currentStreak > 0 ? "今天已经记过，保持住。" : "今天记一餐，就能重新连起来。")
                .font(.subheadline).foregroundStyle(Theme.mutedInk)
            if stats.longestStreak > stats.currentStreak {
                Text("最长连记 \(stats.longestStreak) 天").font(.caption).foregroundStyle(Theme.mutedInk)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentCard()
        .accessibilityIdentifier("streakCard")
    }

    private var summaryRow: some View {
        HStack(spacing: 12) {
            statTile(value: "\(stats.totalMeals)", label: "累计餐数", symbol: "fork.knife")
            statTile(value: "\(stats.recordedDays)", label: "记录天数", symbol: "calendar")
            if let free = stats.smokeFreeDays {
                statTile(value: "\(free)", label: "戒烟天数", symbol: "lungs")
            } else {
                statTile(value: "—", label: "戒烟天数", symbol: "lungs")
            }
        }
    }

    @ViewBuilder
    private var smokingCard: some View {
        let totals = SmokingStats.totals(for: diary.document)
        if totals.hasData {
            VStack(alignment: .leading, spacing: 10) {
                Label("抽烟累计", systemImage: "lungs").font(.headline)
                HStack(spacing: 12) {
                    statTile(value: "\(totals.smoked)", label: "自己抽的", symbol: "flame")
                    statTile(value: "\(totals.shared)", label: "分出去的", symbol: "person.2")
                    statTile(value: totals.costText(), label: "花费", symbol: "banknote")
                }
                if let first = totals.firstEventDate {
                    Text("从 \(first.formatted(date: .abbreviated, time: .omitted)) 开始记录。")
                        .font(.caption2).foregroundStyle(Theme.mutedInk)
                }
            }
            .contentCard()
            .accessibilityIdentifier("smokingTotals")
        }
    }

    private func statTile(value: String, label: String, symbol: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: symbol).font(.subheadline).foregroundStyle(Theme.olive)
            Text(value).font(.title3.bold())
            Text(label).font(.caption2).foregroundStyle(Theme.mutedInk)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .contentCard()
    }

    private func badge(_ achievement: Achievement) -> some View {
        HStack(spacing: 10) {
            Image(systemName: achievement.symbol)
                .font(.title3)
                .foregroundStyle(achievement.isAchieved ? Theme.ink : Theme.mutedInk.opacity(0.5))
                .frame(width: 34)
            VStack(alignment: .leading, spacing: 3) {
                Text(achievement.title).font(.subheadline.weight(.semibold))
                Text(achievement.isAchieved
                     ? (achievement.achievedAt?.formatted(date: .abbreviated, time: .omitted) ?? "已达成")
                     : "还没解锁")
                    .font(.caption2).foregroundStyle(Theme.mutedInk)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(achievement.isAchieved ? Theme.softYellow : Theme.surface,
                    in: .rect(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(achievement.isAchieved ? Theme.gold : Theme.mutedInk.opacity(0.15), lineWidth: 1)
        }
        .opacity(achievement.isAchieved ? 1 : 0.7)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("achievement-\(achievement.id)")
    }
}
