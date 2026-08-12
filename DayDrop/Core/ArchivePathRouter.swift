import Foundation

enum ArchiveHierarchy: Equatable, Sendable {
    case recentDay
    case monthAndDay
    case yearMonthAndDay
}

struct ArchiveRoute: Equatable, Sendable {
    let sourceDay: ArchiveDay
    let hierarchy: ArchiveHierarchy
    let pathComponents: [String]

    var relativePath: String {
        pathComponents.joined(separator: "/")
    }
}

/// Maps a full local calendar day to DayDrop's visible archive hierarchy.
struct ArchivePathRouter {
    let calendar: Calendar

    init(calendar: Calendar = DayDropCalendar.local()) {
        self.calendar = calendar
    }

    func route(for sourceDate: Date, relativeTo today: Date = Date()) -> ArchiveRoute {
        route(
            for: ArchiveDay(date: sourceDate, calendar: calendar),
            relativeTo: ArchiveDay(date: today, calendar: calendar)
        )
    }

    func route(for sourceDay: ArchiveDay, relativeTo today: Date = Date()) -> ArchiveRoute {
        route(for: sourceDay, relativeTo: ArchiveDay(date: today, calendar: calendar))
    }

    func route(for sourceDay: ArchiveDay, relativeTo today: ArchiveDay) -> ArchiveRoute {
        let dayFolder = "Day \(sourceDay.encoded)"
        let monthFolder = "Month \(sourceDay.yearComponent)-\(sourceDay.monthComponent)"

        if sourceDay.year != today.year {
            return ArchiveRoute(
                sourceDay: sourceDay,
                hierarchy: .yearMonthAndDay,
                pathComponents: [
                    "Year \(sourceDay.yearComponent)",
                    monthFolder,
                    dayFolder
                ]
            )
        }

        if naturalDayDistance(from: sourceDay, to: today) <= 14 {
            return ArchiveRoute(
                sourceDay: sourceDay,
                hierarchy: .recentDay,
                pathComponents: [dayFolder]
            )
        }

        return ArchiveRoute(
            sourceDay: sourceDay,
            hierarchy: .monthAndDay,
            pathComponents: [monthFolder, dayFolder]
        )
    }

    private func naturalDayDistance(from sourceDay: ArchiveDay, to today: ArchiveDay) -> Int {
        guard
            let sourceDate = sourceDay.date(in: calendar),
            let todayDate = today.date(in: calendar),
            let difference = calendar.dateComponents(
                [.day],
                from: calendar.startOfDay(for: sourceDate),
                to: calendar.startOfDay(for: todayDate)
            ).day
        else {
            assertionFailure("Valid archive days must be representable in the routing calendar.")
            return .max
        }

        return abs(difference)
    }
}
