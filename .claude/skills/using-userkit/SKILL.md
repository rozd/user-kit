---
name: using-userkit
description: How to use the UserKit Swift package (github.com/rozd/user-kit) from an app that integrates it — inject and read the current `User` via `@Environment(User.self)`, sign in/out, gate features on `isAdmin`, observe user changes, and author or modify a provider adapter (`UserService`/`UserStorage`/`UserSynchronizer` + `UserInfo`/`UserSession`/`UserProfile`). Use when working in a Swift/SwiftUI app that imports `UserKit` or a UserKit provider adapter such as `UserKitFirebase`, when touching the `User` type or authentication / session / admin-role code, or when adding a new auth-provider adapter (`user-kit-<impl>` / `UserKit<Impl>`).
---

# Using UserKit

UserKit is a **provider-neutral "current authenticated user" layer for SwiftUI**. The core package (`import UserKit`) owns the session *as seen from the client* — it does **not** manage identity itself. A separate **provider adapter** package (e.g. `UserKitFirebase`) plugs a real auth backend in behind it.

The type you read and type every day is `User`: a `@MainActor @Observable final class` injected once and read via `@Environment(User.self)`.

There are two jobs this skill covers. Jump to the one you're doing:

- **[Consuming the current user](#consuming-the-current-user)** — you're building app UI/logic and need the signed-in user, sign in/out, or admin gating.
- **[Writing a provider adapter](#writing-a-provider-adapter)** — you're adding or changing an auth backend (Firebase, a custom API, etc.).

Read **[Non-negotiables](#non-negotiables)** first either way — a couple of these will bite you if you don't know them.

---

## Non-negotiables

1. **Match the concurrency dialect.** UserKit and its adapters are compiled with `.defaultIsolation(MainActor.self)` + the `NonisolatedNonsendingByDefault` upcoming feature ("Approachable Concurrency"). The consuming **app target must use the same dialect**, or protocol conformances mismatch across the package boundary (`nonisolated(nonsending)` vs `@concurrent`) and you'll get confusing isolation errors. In Xcode this is the target's *Default Actor Isolation = MainActor* + *Approachable Concurrency* build settings; in a SwiftPM target it's the two `swiftSettings` above.
2. **`UserService.singIn()` is misspelled** (should be `signIn`). The public façade `User.signIn()` is spelled correctly and forwards to `service.singIn()`. In app code you call `user.signIn()`. In an adapter you must implement `singIn()`. Don't "fix" the protocol name — it's the conformance point for every existing adapter.
3. **`isAdmin` is `role == "admin"`, case-sensitive.** `"Admin"`, `"ADMIN"`, `""`, and `nil` are all non-admin.
4. **Don't add a provider SDK to the core `user-kit` repo.** Provider code lives in its own package. See [Writing a provider adapter](#writing-a-provider-adapter).

---

## Consuming the current user

### 1. There is one `User`, injected at the root

The app constructs a single `User` from a provider adapter and injects it into the environment once. The idiomatic pattern is an app-side `User.current` (kept in the app because it depends on app config), injected at the root view:

```swift
import SwiftUI
import UserKit
import UserKitFirebase   // your chosen adapter

extension User {
    @MainActor static let current = User(
        service: FirebaseUserService(configuration: .init(
            authDomain: AppEnvironment.firebaseAuthDomain,
            bundleID: Bundle.main.bundleIdentifier!,
            tosURL: URL(string: "https://example.com/tos"),
            privacyPolicyURL: URL(string: "https://example.com/privacy")
        )),
        storage: FirebaseUserStorage(),
        synchronizer: FirebaseUserSynchronizer()
    )
}

@main
struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView().environment(User.current)
        }
    }
}
```

Only the file that builds `User.current` needs `import UserKitFirebase`. Everything else needs only `import UserKit`.

### 2. Read it anywhere with `@Environment`

```swift
import SwiftUI
import UserKit

struct ProfileView: View {
    @Environment(User.self) private var user

    var body: some View {
        if user.isAuthenticated {
            Text(user.info?.profile.displayName ?? "Signed in")
            if user.isAdmin { AdminButton() }        // gate admin-only UI
            Button("Sign out") { Task { try? await user.signOut() } }
        } else {
            Button("Sign in") { Task { try? await user.signIn() } }
        }
    }
}
```

Because `User` is `@Observable`, views re-render automatically when `info` changes (login, logout, token/claims refresh).

### 3. The consumer API surface

All on `User` unless noted:

| Member | Meaning |
|---|---|
| `info: (any UserInfo)?` | Current user snapshot, or `nil` when signed out. `private(set)`. |
| `isAuthenticated: Bool` | `info?.session.isAuthenticated ?? false`. |
| `isAdmin: Bool` | `info?.isAdmin ?? false` (i.e. `role == "admin"`). |
| `signIn() async throws` | Sign the user in via the provider. |
| `signOut() async throws` | Sign out. |
| `authenticate()` | Present the provider's auth UI (fire-and-forget). |
| `ensureAuthenticated() -> Bool` | Authenticate only if needed; returns whether authenticated. |
| `withAuthentication(_:) async throws -> T` | Run `operation` with a guaranteed-valid session (refreshes/prompts as needed). |
| `infos` | `nonisolated` `AsyncSequence<(any UserInfo)?, Never>` of distinct user changes (de-duped by `id`). For `for await` observation outside SwiftUI. |

`UserInfo` exposes `id: UserId`, `session: any UserSession`, `profile: any UserProfile`, `role: String?`, `isAdmin: Bool`.
`UserSession` exposes `isAuthenticated: Bool`, `refreshToken: String?`, `accessToken: String? { get async }`.
`UserProfile` exposes `displayName: String?` and a computed `initials: String`.

To make an authenticated network call, prefer `withAuthentication`:

```swift
let data = try await user.withAuthentication {
    try await api.fetchSomethingRequiringAuth()
}
```

### Gotchas when consuming

- `UserInfo` conformers are `Equatable` **by `id` only** — two `info` values with the same id compare equal even if the profile/session differ. Don't rely on `==` to detect a profile change; observe `info` directly.
- `accessToken` is an **async** getter (it may refresh). Don't expect a synchronous read.
- `user.info` is `nil` until the first async load completes after launch; write UI that tolerates the signed-out/loading state.

---

## Writing a provider adapter

An adapter is a **separate Swift package** named `user-kit-<impl>` with module `UserKit<Impl>` (e.g. `user-kit-firebase` / `UserKitFirebase`). It `import UserKit`, provides concrete conformers to the three seam protocols plus the three value protocols, and lets the app construct `User(service:storage:synchronizer:)`.

**Never add provider SDKs to the core `user-kit` repo** — SPM resolves every dependency in a manifest for every consumer, so a Firebase dependency in the core would force Firebase into every app that links UserKit. That is the entire reason adapters are separate packages.

### The six protocols to conform

```swift
// The three seams (behavior):
@MainActor public protocol UserService: Sendable {
    var isEmailVerified: any AsyncSequence<Bool, Never> & Sendable { get }
    func singIn() async throws            // NOTE: misspelled on purpose — conform to this exact name
    func signOut() async throws
    func sendVerificationEmail() async throws
    func authenticate()
    func authenticateIfNeeded() -> Bool
    func withAuthentication<T: Sendable>(_ operation: @escaping @Sendable () async throws -> T) async throws -> T
}

nonisolated public protocol UserStorage: Sendable {
    func fetch() async -> (any UserInfo)?           // seed the last-known user on launch
    func store(userInfo info: any UserInfo) async
    func clear() async
}

nonisolated public protocol UserSynchronizer: Sendable {
    func install() -> any AsyncSequence<(any UserInfo)?, Never> & Sendable   // live auth-state stream
    func dispose()
}

// The three value types (data):
nonisolated public protocol UserInfo: Sendable, Equatable {
    var id: UserId { get }
    var session: any UserSession { get }
    var profile: any UserProfile { get }
    var role: String? { get }             // override to surface the provider's role; default nil
}
nonisolated public protocol UserSession: Sendable, Equatable {
    var isAuthenticated: Bool { get }
    var refreshToken: String? { get }
    var accessToken: String? { get async }
}
nonisolated public protocol UserProfile: Sendable, Equatable {
    var displayName: String? { get }
}
```

### How `User` drives the adapter

On `init`, `User` first `await`s `storage.fetch()` to seed `info`, then loops over `synchronizer.install()` forever, assigning each emission to `info`. On `deinit` it cancels that task and calls `synchronizer.dispose()`. So:

- `install()` must return a **cold, cancel-safe** `AsyncSequence` that yields the current user (or `nil`) whenever auth state changes, and cleans up in `onTermination`.
- `role` must be overridden on your `UserInfo` to return the provider's role (e.g. a JWT custom claim), or admin gating never works.
- Match the concurrency dialect (`.defaultIsolation(MainActor.self)` + `NonisolatedNonsendingByDefault`) in your adapter's `Package.swift` `swiftSettings`.

### Minimal skeleton

The smallest complete conformer set — copy and fill in the provider calls. (This is the shape of `UserKitTests/AdminRoleTests.swift`'s `Stub*` types, which are the canonical minimal reference.)

```swift
import UserKit

struct MyUserSession: UserSession {
    var isAuthenticated: Bool { /* provider */ true }
    var refreshToken: String? { /* provider */ nil }
    var accessToken: String? { get async { /* provider, may refresh */ nil } }
}
struct MyUserProfile: UserProfile {
    var displayName: String? { /* provider */ nil }
}
struct MyUserInfo: UserInfo {
    let id: UserId
    var role: String? { /* provider claim */ nil }
    var session: any UserSession { MyUserSession() }
    var profile: any UserProfile { MyUserProfile() }
}

@MainActor struct MyUserService: UserService {
    var isEmailVerified: any AsyncSequence<Bool, Never> & Sendable {
        AsyncStream { $0.finish() }
    }
    func singIn() async throws { /* provider sign-in */ }
    func signOut() async throws { /* provider sign-out */ }
    func sendVerificationEmail() async throws { /* provider */ }
    func authenticate() { /* present auth UI */ }
    func authenticateIfNeeded() -> Bool { true }
    func withAuthentication<T: Sendable>(_ operation: @escaping @Sendable () async throws -> T) async throws -> T {
        try await operation()
    }
}

struct MyUserStorage: UserStorage {
    func fetch() async -> (any UserInfo)? { nil }
    func store(userInfo info: any UserInfo) async {}
    func clear() async {}
}

struct MyUserSynchronizer: UserSynchronizer {
    func install() -> any AsyncSequence<(any UserInfo)?, Never> & Sendable {
        AsyncStream { continuation in
            // subscribe to provider auth-state changes; yield MyUserInfo(...) or nil
            continuation.onTermination = { _ in /* unsubscribe */ }
        }
    }
    func dispose() {}
}
```

For a **real, production adapter** — bridging a live auth-state listener into `install()`, mapping JWT claims to `role`, implementing an async `accessToken`, and injecting app config instead of reaching into `AppEnvironment` — read the Firebase reference:

**→ See [`references/firebase-adapter.md`](references/firebase-adapter.md)** for the full `UserKitFirebase` implementation with commentary.
