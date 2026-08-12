import Foundation

enum DownloadCandidateRejection: Equatable, Sendable {
    case hidden
    case directory
    case temporarySuffix(String)
}

enum DownloadCandidateEligibility: Equatable, Sendable {
    case eligible
    case rejected(DownloadCandidateRejection)
}

/// Applies the metadata-only checks that must pass before size stability is sampled.
struct DownloadCandidatePolicy {
    static let browserTemporarySuffixes = [
        ".crdownload",
        ".download",
        ".part",
        ".tmp"
    ]

    private let temporarySuffixes: [String]

    init(temporarySuffixes: [String] = DownloadCandidatePolicy.browserTemporarySuffixes) {
        self.temporarySuffixes = temporarySuffixes
            .map { $0.lowercased() }
            .sorted { lhs, rhs in
                if lhs.count == rhs.count {
                    return lhs < rhs
                }
                return lhs.count > rhs.count
            }
    }

    func evaluate(
        fileName: String,
        isHidden: Bool,
        isDirectory: Bool
    ) -> DownloadCandidateEligibility {
        if isHidden || fileName.hasPrefix(".") {
            return .rejected(.hidden)
        }

        if isDirectory {
            return .rejected(.directory)
        }

        let normalizedName = fileName.lowercased()
        if let suffix = temporarySuffixes.first(where: normalizedName.hasSuffix) {
            return .rejected(.temporarySuffix(suffix))
        }

        return .eligible
    }

    func isEligible(
        fileName: String,
        isHidden: Bool,
        isDirectory: Bool
    ) -> Bool {
        evaluate(
            fileName: fileName,
            isHidden: isHidden,
            isDirectory: isDirectory
        ) == .eligible
    }
}
