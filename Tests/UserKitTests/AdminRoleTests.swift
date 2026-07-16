import Testing
import Foundation
@testable import UserKit

// MARK: - Admin Role Tests

@Suite("Admin Role Tests")
@MainActor
struct AdminRoleTests {

    // MARK: - UserInfo.isAdmin (via hoisted `role`)

    @Test("isAdmin is true when role is admin")
    func isAdminTrueForAdminRole() {
        let info = StubUserInfo(id: UserId("u"), role: "admin")
        #expect(info.isAdmin)
    }

    @Test("isAdmin is false for a non-admin role")
    func isAdminFalseForClientRole() {
        let info = StubUserInfo(id: UserId("u"), role: "client")
        #expect(!info.isAdmin)
    }

    @Test("isAdmin is false when role is nil (default conformer)")
    func isAdminFalseWhenRoleNil() {
        let info = StubUserInfo(id: UserId("u"), role: nil)
        #expect(!info.isAdmin)
    }

    @Test("isAdmin is false for empty role")
    func isAdminFalseForEmptyRole() {
        let info = StubUserInfo(id: UserId("u"), role: "")
        #expect(!info.isAdmin)
    }

    @Test("isAdmin is case sensitive")
    func isAdminCaseSensitive() {
        #expect(!StubUserInfo(id: UserId("u"), role: "ADMIN").isAdmin)
        #expect(!StubUserInfo(id: UserId("u"), role: "Admin").isAdmin)
    }

    // MARK: - User.isAdmin

    @Test("User.isAdmin is false when info is nil")
    func userIsAdminFalseWhenInfoNil() {
        let user = User(
            service: StubUserService(),
            storage: StubUserStorage(userInfo: nil),
            synchronizer: StubUserSynchronizer()
        )
        #expect(user.isAdmin == false)
    }
}

// MARK: - Stubs

private struct StubUserSession: UserSession {
    var isAuthenticated: Bool { true }
    var refreshToken: String? { "stub-refresh-token" }
    var accessToken: String? {
        get async { "stub-access-token" }
    }
}

private struct StubUserProfile: UserProfile {
    var displayName: String? { "Stub User" }
}

private struct StubUserInfo: UserInfo {
    let id: UserId
    let role: String?

    var session: any UserSession { StubUserSession() }
    var profile: any UserProfile { StubUserProfile() }
}

@MainActor
private struct StubUserService: UserService {
    var isEmailVerified: any AsyncSequence<Bool, Never> & Sendable {
        AsyncStream { continuation in
            continuation.yield(true)
            continuation.finish()
        }
    }

    func singIn() async throws {}
    func signOut() async throws {}
    func sendVerificationEmail() async throws {}
    func authenticate() {}
    func authenticateIfNeeded() -> Bool { true }
    func withAuthentication<T: Sendable>(_ operation: @escaping @Sendable () async throws -> T) async throws -> T {
        try await operation()
    }
}

private struct StubUserStorage: UserStorage {
    let userInfo: (any UserInfo)?

    func fetch() async -> (any UserInfo)? { userInfo }
    func store(userInfo info: any UserInfo) async {}
    func clear() async {}
}

private struct StubUserSynchronizer: UserSynchronizer {
    func install() -> any AsyncSequence<(any UserInfo)?, Never> & Sendable {
        AsyncStream { continuation in
            continuation.finish()
        }
    }

    func dispose() {}
}
