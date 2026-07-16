import Foundation

nonisolated public struct UserId: LosslessStringConvertible, Sendable, Codable, Equatable, Hashable {
    public let description: String

    public init(_ description: String) {
        self.description = description
    }
}

@MainActor
@Observable
public final class User {

    @ObservationIgnored
    public let service: any UserService

    @ObservationIgnored
    let storage: any UserStorage

    @ObservationIgnored
    let synchronizer: any UserSynchronizer

    @ObservationIgnored
    private var _sync: Task<Void, Never>?

    public private(set) var info: (any UserInfo)?

    public init(
        service: any UserService,
        storage: any UserStorage,
        synchronizer: any UserSynchronizer
    ) {
        self.service = service
        self.storage = storage
        self.synchronizer = synchronizer

        _sync = Task { @MainActor [weak self, storage, synchronizer] in
            let info = await storage.fetch()
            guard !Task.isCancelled else {
                return
            }

            self?.info = info

            for await info in synchronizer.install() {
                guard !Task.isCancelled else {
                    break
                }
                self?.info = info
            }
        }
    }

    deinit {
        _sync?.cancel()
        synchronizer.dispose()
    }

}

extension User {

    public var isAuthenticated: Bool {
        info?.session.isAuthenticated ?? false
    }

    public func authenticate() {
        service.authenticate()
    }

    public func ensureAuthenticated() -> Bool {
        service.authenticateIfNeeded()
    }

    public func withAuthentication<T: Sendable>(
        _ operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await service.withAuthentication(operation)
    }
}

extension User {

    public func signIn() async throws {
        try await service.singIn()
    }

    public func signOut() async throws {
        try await service.signOut()
    }
}

// MARK: - Admin

extension User {

    public var isAdmin: Bool {
        info?.isAdmin ?? false
    }
}

// MARK: - UserService

@MainActor
public protocol UserService: Sendable {

    var isEmailVerified: any AsyncSequence<Bool, Never> & Sendable { get }

    func singIn() async throws
    func signOut() async throws
    func sendVerificationEmail() async throws

    func authenticate()
    func authenticateIfNeeded() -> Bool

    func withAuthentication<T: Sendable>(
        _ operation: @escaping @Sendable () async throws -> T
    ) async throws -> T
}

// MARK: - UserStorage

nonisolated public protocol UserStorage: Sendable {
    func fetch() async -> (any UserInfo)?
    func store(userInfo info: any UserInfo) async
    func clear() async
}

// MARK: - UserSynchronizer

nonisolated public protocol UserSynchronizer: Sendable {
    func install() -> any AsyncSequence<(any UserInfo)?, Never> & Sendable
    func dispose()
}

// MARK: - UserInfo

nonisolated public protocol UserInfo: Sendable, Equatable {
    var id: UserId { get }
    var session: any UserSession { get }
    var profile: any UserProfile { get }

    /// Authorization role for the current user, surfaced from the identity
    /// provider (e.g. a JWT custom claim). `nil` when the provider exposes no
    /// role. Adapters override this; the default keeps provider-agnostic
    /// conformers (mocks, previews) compiling as non-admin.
    var role: String? { get }
}

public extension UserInfo {
    var role: String? { nil }

    var isAdmin: Bool {
        role == "admin"
    }
}

public extension UserInfo {
    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - UserSession

nonisolated public protocol UserSession: Sendable, Equatable {
    var isAuthenticated: Bool { get }
    var refreshToken: String? { get }
    var accessToken: String? { get async }
}

// MARK: - UserProfile

nonisolated public protocol UserProfile: Sendable, Equatable {
    var displayName: String? { get }
}

public extension UserProfile {
    var initials: String {
        let names = displayName?.split(separator: " ") ?? []
        let initials = names.compactMap { $0.first }.map { String($0) }
        return initials.prefix(2).joined()
    }
}
