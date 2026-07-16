import AsyncAlgorithms

extension User {
    nonisolated public var infos: some AsyncSequence<(any UserInfo)?, Never> & Sendable {
        let synchronizer = self.synchronizer
        return AsyncStream { continuation in
            let task = Task { @MainActor in
                for await update in synchronizer.install() {
                    guard !Task.isCancelled else { break }
                    continuation.yield(update)
                }
                continuation.finish()
            }

            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
        .removeDuplicates { lhs, rhs in
            switch (lhs, rhs) {
            case (.none, .none):
                return true
            case (.some(let l), .some(let r)):
                return l.id == r.id
            default:
                return false
            }
        }
    }
}
