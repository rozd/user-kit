# Reference: the Firebase adapter (`UserKitFirebase`)

This is the real reference implementation of a UserKit provider adapter — `github.com/rozd/user-kit-firebase`, local clone at `../user-kit-firebase`. Read it when you're building a new adapter and want to see how the seams are wired to a real backend. Every pattern here transfers to a non-Firebase provider (a custom API, Auth0, etc.); only the SDK calls change.

## Package shape

Separate package, depends on `user-kit` (not the other way around):

```swift
// swift-tools-version: 6.2
let package = Package(
    name: "UserKitFirebase",
    platforms: [.iOS(.v18)],
    products: [.library(name: "UserKitFirebase", targets: ["UserKitFirebase"])],
    dependencies: [
        .package(url: "https://github.com/rozd/user-kit", branch: "main"),
        .package(url: "https://github.com/apple/swift-async-algorithms", from: "1.0.0"),
        .package(url: "https://github.com/firebase/firebase-ios-sdk", exact: "12.12.1"),
        .package(url: "https://github.com/firebase/FirebaseUI-iOS", revision: "…"),
    ],
    targets: [
        .target(
            name: "UserKitFirebase",
            dependencies: [
                .product(name: "UserKit", package: "user-kit"),
                .product(name: "FirebaseAuth", package: "firebase-ios-sdk"),
                .product(name: "FirebaseAuthSwiftUI", package: "firebaseui-ios"),
                .product(name: "AsyncAlgorithms", package: "swift-async-algorithms"),
            ],
            // Must match the core + app concurrency dialect.
            swiftSettings: [
                .defaultIsolation(MainActor.self),
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
            ]
        ),
        .testTarget(name: "UserKitFirebaseTests", dependencies: ["UserKitFirebase"], swiftSettings: [ /* same */ ]),
    ]
)
```

Pin the provider SDK versions to exactly what the consuming app already resolves, so adding the adapter doesn't perturb the app's dependency graph.

## `UserSynchronizer` — bridging a listener into an `AsyncSequence`

This is the crux of an adapter. Firebase pushes auth-state changes through a callback listener; UserKit wants an `AsyncSequence`. Bridge with `AsyncStream`, and unsubscribe in `onTermination` so the stream is cancel-safe (remember `User.deinit` calls `dispose()` and the stream terminates):

```swift
import UserKit
@preconcurrency import FirebaseAuth

public struct FirebaseUserSynchronizer: UserSynchronizer {
    public init() {}

    public func install() -> any AsyncSequence<(any UserKit.UserInfo)?, Never> & Sendable {
        AsyncStream { continuation in
            nonisolated(unsafe) let handle = Auth.auth().addStateDidChangeListener { _, user in
                if let user {
                    Task {
                        let userInfo = await user.toUserInfo()   // fetch claims, build UserInfo
                        continuation.yield(userInfo)
                    }
                } else {
                    continuation.yield(nil)                       // signed out
                }
            }
            continuation.onTermination = { @Sendable _ in
                Auth.auth().removeStateDidChangeListener(handle)  // clean up
            }
        }
    }

    public func dispose() { /* no-op; onTermination already removes the listener */ }
}
```

Note the `@preconcurrency import` and `nonisolated(unsafe)` on the handle — pragmatic escapes for an Objective-C SDK that predates strict concurrency. Use them narrowly.

## Value types — `@unchecked Sendable` over a non-Sendable SDK object

`FirebaseAuth.User` isn't `Sendable`, but the UserKit value protocols require `Sendable`. Wrap it and vouch for it with `@unchecked Sendable` + `nonisolated(unsafe)` stored properties. The `role` override is what makes `isAdmin` work — it reads the JWT custom claim:

```swift
public struct FirebaseUserInfo: UserKit.UserInfo, @unchecked Sendable {
    nonisolated(unsafe) let user: FirebaseAuth.User
    nonisolated(unsafe) let claims: [String: Any]
    let userId: UserId

    public var id: UserId { userId }

    /// Overrides the core default (`nil`) with the Firebase JWT `role` claim,
    /// which is exactly what `UserInfo.isAdmin` (`role == "admin"`) reads.
    public var role: String? { claims["role"] as? String }

    public var session: any UserSession { FirebaseUserSession(user: user) }
    public var profile: any UserProfile { FirebaseUserProfile(user: user) }
}

public struct FirebaseUserProfile: UserProfile, @unchecked Sendable {
    nonisolated(unsafe) let user: FirebaseAuth.User
    public var displayName: String? { user.displayName }
}

public struct FirebaseUserSession: UserSession, @unchecked Sendable {
    nonisolated(unsafe) let user: FirebaseAuth.User
    public var isAuthenticated: Bool { user.refreshToken != nil }
    public var refreshToken: String? { user.refreshToken }

    // Async getter: bridges a completion-handler token fetch (may refresh).
    public var accessToken: String? {
        get async {
            await withCheckedContinuation { continuation in
                user.getIDToken { token, _ in continuation.resume(returning: token) }
            }
        }
    }
}
```

Fetching claims to build the `UserInfo` is itself async (a token-result callback), bridged the same way:

```swift
extension FirebaseAuth.User {
    func toUserInfo() async -> FirebaseUserInfo {
        let claims = await withCheckedContinuation { (c: CheckedContinuation<SendableClaims, Never>) in
            self.getIDTokenResult { result, _ in c.resume(returning: SendableClaims(result?.claims ?? [:])) }
        }
        return FirebaseUserInfo(user: self, claims: claims.value)
    }
}

private struct SendableClaims: @unchecked Sendable {  // ferry a [String: Any] across the continuation
    let value: [String: Any]
    init(_ value: [String: Any]) { self.value = value }
}
```

## Injecting app configuration (don't reach into the app)

A package can't see the app's `AppEnvironment`. Inject what the service needs through a config struct the app fills in:

```swift
public struct FirebaseUserServiceConfiguration: Sendable {
    public var authDomain: String
    public var bundleID: String
    public var tosURL: URL?
    public var privacyPolicyURL: URL?
    public init(authDomain: String, bundleID: String, tosURL: URL? = nil, privacyPolicyURL: URL? = nil) { … }
}

public struct FirebaseUserService: UserService {
    public init(configuration: FirebaseUserServiceConfiguration) { … }
    // singIn()/signOut()/sendVerificationEmail()/authenticate()/authenticateIfNeeded()/withAuthentication call FirebaseAuth
}
```

The app passes real values (`AppEnvironment.firebaseAuthDomain`, `Bundle.main.bundleIdentifier!`, real ToS/privacy URLs) when it constructs `User.current` — see the composition-root example in the main `SKILL.md`.

## What the adapter deliberately does NOT do

- **No `User.current` singleton.** That lives in the app (it depends on app config). The adapter only supplies the pieces.
- **No admin/role policy.** The adapter only surfaces the raw `role` string from the claim; `role == "admin"` lives in the core.
- **Nothing forced into the core.** Everything Firebase-specific stays in this package; the core stays provider-free.
