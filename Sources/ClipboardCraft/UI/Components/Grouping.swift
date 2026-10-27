import Foundation

enum DateBucket: Hashable {
    case pinned, today, yesterday, week, month, older(year: Int, month: Int)

    var title: String {
        switch self {
        case .pinned: "Pinned"
        case .today: "Today"
        case .yesterday: "Yesterday"
        case .week: "Previous 7 Days"
        case .month: "Previous 30 Days"
        case .older(let y, let m):
            DateComponents(calendar: .current, year: y, month: m).date?.formatted(.dateTime.month(.wide).year()) ?? "Earlier"
        }
    }

    static func of(_ date: Date, now: Date) -> DateBucket {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return .today }
        if cal.isDateInYesterday(date) { return .yesterday }
        let days = now.timeIntervalSince(date) / 86_400
        if days < 7 { return .week }
        if days < 30 { return .month }
        let c = cal.dateComponents([.year, .month], from: date)
        return .older(year: c.year ?? 0, month: c.month ?? 0)
    }
}

struct ClipSection: Identifiable {
    var id: DateBucket { bucket }
    let bucket: DateBucket
    var items: [ClipItem]
}

enum Grouping {
    /// Groups clips by recency. Input order is preserved inside each section.
    static func byDate(_ items: [ClipItem], pinnedSeparately: Bool, now: Date = .now) -> [ClipSection] {
        var sections: [ClipSection] = []
        var index: [DateBucket: Int] = [:]
        for item in items {
            let bucket: DateBucket = (pinnedSeparately && item.isPinned) ? .pinned : .of(item.updatedAt, now: now)
            if let i = index[bucket] {
                sections[i].items.append(item)
            } else {
                index[bucket] = sections.count
                sections.append(ClipSection(bucket: bucket, items: [item]))
            }
        }
        return sections
    }
}
