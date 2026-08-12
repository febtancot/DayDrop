import Foundation

/// Applies the PRD's creation-date-first rule for explicitly imported files.
struct ExistingFileDateResolver {
    let calendar: Calendar

    init(calendar: Calendar = DayDropCalendar.local()) {
        self.calendar = calendar
    }

    func archiveDay(creationDate: Date?, modificationDate: Date?) -> ArchiveDay? {
        guard let sourceDate = creationDate ?? modificationDate else {
            return nil
        }
        return ArchiveDay(date: sourceDate, calendar: calendar)
    }
}

