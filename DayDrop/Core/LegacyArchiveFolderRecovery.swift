import Foundation

struct LegacyManagedFolderCandidate: Equatable, Sendable {
    let dateIdentifier: String
    let relativePath: String
    let directoryIdentity: String
}

/// Recovers ownership only when persisted operation evidence ties a legacy
/// numeric archive path to one unambiguous full date. A numeric folder name by
/// itself is never sufficient evidence.
struct LegacyArchiveFolderRecovery {
    private let calendar: Calendar
    private let fileManager: FileManager

    init(
        calendar: Calendar = DayDropCalendar.local(),
        fileManager: FileManager = .default
    ) {
        self.calendar = calendar
        self.fileManager = fileManager
    }

    func candidates(
        in rootURL: URL,
        operationRecords: [OperationRecord],
        existingFolders: [ManagedDayFolder]
    ) -> [LegacyManagedFolderCandidate] {
        let root = rootURL.standardizedFileURL
        let existingDates = Set(existingFolders.map(\.dateIdentifier))
        let existingPaths = Set(existingFolders.map(\.relativePath))
        var datesByRelativePath: [String: Set<ArchiveDay>] = [:]

        for record in operationRecords where record.succeeded {
            let destination = URL(fileURLWithPath: record.destinationPath)
                .standardizedFileURL
            guard fileManager.fileExists(atPath: destination.path) else {
                continue
            }

            let folderURL = destination.deletingLastPathComponent()
            guard let relativePath = relativePath(of: folderURL, under: root),
                  let sourceDay = legacySourceDay(
                      for: relativePath,
                      performedAt: record.performedAt
                  )
            else {
                continue
            }

            datesByRelativePath[relativePath, default: []].insert(sourceDay)
        }

        return datesByRelativePath.compactMap { relativePath, dates in
            guard dates.count == 1,
                  let sourceDay = dates.first,
                  !existingDates.contains(sourceDay.encoded),
                  !existingPaths.contains(relativePath),
                  let folderURL = safeLegacyFolder(
                      in: root,
                      relativePath: relativePath
                  ),
                  let identity = FileSystemIdentity.directoryIdentifier(at: folderURL)
            else {
                return nil
            }

            let ownershipDate = DayDropDirectoryOwnershipMarker
                .managedDateIdentifier(at: folderURL)
            guard ownershipDate == nil || ownershipDate == sourceDay.encoded else {
                return nil
            }

            return LegacyManagedFolderCandidate(
                dateIdentifier: sourceDay.encoded,
                relativePath: relativePath,
                directoryIdentity: identity
            )
        }.sorted { lhs, rhs in
            lhs.dateIdentifier < rhs.dateIdentifier
        }
    }

    private func relativePath(of folderURL: URL, under rootURL: URL) -> String? {
        let rootPath = rootURL.path
        let folderPath = folderURL.path
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        guard folderPath.hasPrefix(prefix) else { return nil }

        let relativePath = String(folderPath.dropFirst(prefix.count))
        guard ManagedDayFolder.isValidRelativePath(relativePath) else { return nil }
        return relativePath
    }

    private func legacySourceDay(
        for relativePath: String,
        performedAt: Date
    ) -> ArchiveDay? {
        let components = relativePath.split(separator: "/").map(String.init)
        let performedDay = ArchiveDay(date: performedAt, calendar: calendar)
        let sourceDay: ArchiveDay?

        switch components.count {
        case 1:
            sourceDay = monthDay(
                components[0],
                year: performedDay.year
            )
        case 2:
            guard components[0].count == 2,
                  components[0].allSatisfy(\.isNumber),
                  components[1].hasPrefix(components[0])
            else { return nil }
            sourceDay = monthDay(
                components[1],
                year: performedDay.year
            )
        case 3:
            guard components[0].count == 4,
                  components[0].allSatisfy(\.isNumber),
                  components[1].count == 2,
                  components[1].allSatisfy(\.isNumber),
                  components[2].hasPrefix(components[1]),
                  let year = Int(components[0])
            else { return nil }
            sourceDay = monthDay(components[2], year: year)
        default:
            return nil
        }

        guard let sourceDay,
              legacyRelativePath(for: sourceDay, relativeTo: performedDay) == relativePath
        else {
            return nil
        }
        return sourceDay
    }

    private func monthDay(_ value: String, year: Int) -> ArchiveDay? {
        guard value.count == 4,
              value.allSatisfy(\.isNumber),
              let month = Int(value.prefix(2)),
              let day = Int(value.suffix(2))
        else {
            return nil
        }
        return ArchiveDay(year: year, month: month, day: day)
    }

    private func legacyRelativePath(
        for sourceDay: ArchiveDay,
        relativeTo today: ArchiveDay
    ) -> String {
        if sourceDay.year != today.year {
            return [
                sourceDay.yearComponent,
                sourceDay.monthComponent,
                sourceDay.monthDayComponent
            ].joined(separator: "/")
        }

        if naturalDayDistance(from: sourceDay, to: today) <= 14 {
            return sourceDay.monthDayComponent
        }

        return [sourceDay.monthComponent, sourceDay.monthDayComponent]
            .joined(separator: "/")
    }

    private func naturalDayDistance(from sourceDay: ArchiveDay, to today: ArchiveDay) -> Int {
        guard let sourceDate = sourceDay.date(in: calendar),
              let todayDate = today.date(in: calendar),
              let difference = calendar.dateComponents(
                  [.day],
                  from: calendar.startOfDay(for: sourceDate),
                  to: calendar.startOfDay(for: todayDate)
              ).day
        else {
            return .max
        }
        return abs(difference)
    }

    private func safeLegacyFolder(
        in rootURL: URL,
        relativePath: String
    ) -> URL? {
        let components = relativePath.split(separator: "/").map(String.init)
        guard !components.isEmpty else { return nil }

        var candidate = rootURL
        for component in components {
            candidate.appendPathComponent(component, isDirectory: true)
            guard let values = try? candidate.resourceValues(
                forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
            ),
                  values.isDirectory == true,
                  values.isSymbolicLink != true
            else {
                return nil
            }
        }

        let resolvedRoot = rootURL.resolvingSymlinksInPath().standardizedFileURL
        let resolvedCandidate = candidate.resolvingSymlinksInPath().standardizedFileURL
        let rootPrefix = resolvedRoot.path.hasSuffix("/")
            ? resolvedRoot.path
            : resolvedRoot.path + "/"
        guard resolvedCandidate.path.hasPrefix(rootPrefix) else { return nil }
        return candidate.standardizedFileURL
    }
}
