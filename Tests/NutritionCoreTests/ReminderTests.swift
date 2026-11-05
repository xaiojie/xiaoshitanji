import Foundation
import Testing
@testable import NutritionCore

@Suite("提醒")
struct ReminderTests {
    private let calendar = Calendar(identifier: .gregorian)

    @Test("默认三餐开启、称重关闭")
    func defaults() {
        let reminders = ReminderPlanner.defaults()
        #expect(reminders.count == 4)
        #expect(reminders.first { $0.kind == .lunch }?.hour == 12)
        #expect(reminders.first { $0.kind == .lunch }?.minute == 30)
        #expect(reminders.first { $0.kind == .weight }?.isEnabled == false)
        #expect(ReminderPlanner.scheduled(reminders).count == 3)
    }

    @Test("非法时间不排期")
    func rejectsInvalidTime() {
        let bad = Reminder(kind: .breakfast, hour: 24, minute: 0, isEnabled: true)
        #expect(throws: (any Error).self) { try bad.validate() }
        #expect(ReminderPlanner.scheduled([bad]).isEmpty)
    }

    @Test("下一次提醒跨天与当天")
    func nextReminder() {
        let now = calendar.date(from: DateComponents(year: 2023, month: 11, day: 4, hour: 13, minute: 0))!
        let reminders = ReminderPlanner.defaults()
        let next = ReminderPlanner.next(from: reminders, now: now, calendar: calendar)
        #expect(next?.0.kind == .dinner)
        #expect(calendar.component(.hour, from: next!.1) == 18)

        let late = calendar.date(from: DateComponents(year: 2023, month: 11, day: 4, hour: 23, minute: 0))!
        let tomorrow = ReminderPlanner.next(from: reminders, now: late, calendar: calendar)
        #expect(tomorrow?.0.kind == .breakfast)
        #expect(calendar.component(.day, from: tomorrow!.1) == 5)
    }

    @Test("关闭的提醒不参与下次计算")
    func disabledExcluded() {
        var reminders = ReminderPlanner.defaults()
        reminders[0].isEnabled = false
        reminders[1].isEnabled = false
        reminders[2].isEnabled = false
        #expect(ReminderPlanner.next(from: reminders) == nil)
    }

    @Test("时间格式化与回填")
    func timeFormatting() {
        var reminder = Reminder(kind: .dinner)
        #expect(reminder.timeText == "18:00")
        let date = calendar.date(from: DateComponents(year: 2023, month: 11, day: 4, hour: 19, minute: 45))!
        reminder.setTime(from: date, calendar: calendar)
        #expect(reminder.timeText == "19:45")
    }
}
