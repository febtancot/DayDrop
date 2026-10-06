import Foundation

/// Delayed organization is based on local calendar days, not a 24-hour timeout.
struct AutomaticOrganizationPolicy {
    let delayed: Bool
    var calendar: Calendar = DayDropCalendar.local()

    func sourceDay(
        for snapshot: TopLevelFileSnapshot,
        isBaseline: Bool,
        at now: Date
    ) -> ArchiveDay? {
        guard delayed else {
            return isBaseline ? nil : ArchiveDay(date: now, calendar: calendar)
        }

        // Downloaded files can retain a server's old modification date. Prefer
        // when the file entered Downloads, then the existing metadata fallback.
        guard let downloadDate = snapshot.addedToDirectoryDate
                ?? snapshot.creationDate ?? snapshot.modificationDate,
              downloadDate < calendar.startOfDay(for: now)
        else { return nil }

        return ArchiveDay(date: downloadDate, calendar: calendar)
    }
}
