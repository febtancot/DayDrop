import Foundation

/// A calendar day stored without a time or time zone.
///
/// DayDrop persists this value as `YYYY-MM-DD` independently of the visible
/// `Day`, `Month`, and `Year` folder hierarchy.
struct ArchiveDay: Hashable, Codable, Sendable {
    let year: Int
    let month: Int
    let day: Int

    init?(year: Int, month: Int, day: Int) {
        guard ArchiveDay.isValid(year: year, month: month, day: day) else {
            return nil
        }

        self.year = year
        self.month = month
        self.day = day
    }

    init(date: Date, calendar: Calendar = DayDropCalendar.local()) {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        precondition(
            components.year != nil && components.month != nil && components.day != nil,
            "The supplied calendar must produce year, month, and day components."
        )

        self.year = components.year!
        self.month = components.month!
        self.day = components.day!
    }

    init?(encoded: String) {
        let bytes = Array(encoded.utf8)
        guard
            bytes.count == 10,
            bytes[4] == Character("-").asciiValue,
            bytes[7] == Character("-").asciiValue,
            bytes.enumerated().allSatisfy({ index, byte in
                index == 4 || index == 7 || (Character("0").asciiValue!...Character("9").asciiValue!).contains(byte)
            }),
            let year = Int(String(encoded.prefix(4))),
            let month = Int(String(encoded.dropFirst(5).prefix(2))),
            let day = Int(String(encoded.suffix(2))),
            ArchiveDay.isValid(year: year, month: month, day: day)
        else {
            return nil
        }

        self.year = year
        self.month = month
        self.day = day
    }

    var encoded: String {
        "\(fourDigits(year))-\(twoDigits(month))-\(twoDigits(day))"
    }

    var yearComponent: String {
        fourDigits(year)
    }

    var monthComponent: String {
        twoDigits(month)
    }

    var monthDayComponent: String {
        "\(twoDigits(month))\(twoDigits(day))"
    }

    func date(in calendar: Calendar) -> Date? {
        calendar.date(from: DateComponents(year: year, month: month, day: day))
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let encoded = try container.decode(String.self)

        guard let value = ArchiveDay(encoded: encoded) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected a valid calendar date encoded as YYYY-MM-DD."
            )
        }

        self = value
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(encoded)
    }

    private static func isValid(year: Int, month: Int, day: Int) -> Bool {
        guard (1...9999).contains(year), (1...12).contains(month), (1...31).contains(day) else {
            return false
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.locale = Locale(identifier: "en_US_POSIX")

        let components = DateComponents(year: year, month: month, day: day)
        guard let date = calendar.date(from: components) else {
            return false
        }

        let roundTrip = calendar.dateComponents([.year, .month, .day], from: date)
        return roundTrip.year == year && roundTrip.month == month && roundTrip.day == day
    }

    private func twoDigits(_ value: Int) -> String {
        value < 10 ? "0\(value)" : String(value)
    }

    private func fourDigits(_ value: Int) -> String {
        switch value {
        case ..<10:
            return "000\(value)"
        case ..<100:
            return "00\(value)"
        case ..<1_000:
            return "0\(value)"
        default:
            return String(value)
        }
    }
}

enum DayDropCalendar {
    /// Gregorian calendar using the Mac's current time zone by default.
    static func local(timeZone: TimeZone = .current) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }
}
