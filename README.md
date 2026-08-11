# UserKit

**A provider-neutral “current user” layer for SwiftUI.**

UserKit gives your app one observable `User` you inject once and read anywhere. It owns the session *as seen from the client* and stays out of the identity business — you plug a real auth backend in behind it with a small adapter (Firebase, your own API, …).

- 🧩 **Provider-neutral** — the core knows nothing about Firebase, Auth0, or your backend. Swap providers without touching your app code.
- 👀 **SwiftUI-native** — `User` is `@Observable`; views update automatically on sign-in, sign-out, and token refresh.
- 🪶 **Tiny** — one dependency ([swift-async-algorithms](https://github.com/apple/swift-async-algorithms)). No SDK bloat dragged into your app.
- 🤖 **Android-ready** — pure cross-platform Swift: works in [Skip](https://skip.dev) Fuse apps and compiles with the [Swift SDK for Android](https://www.swift.org/android/) as-is.

```swift
@Environment(User.self) private var user

if user.isAuthenticated {
    Text(user.info?.profile.displayName ?? "Signed in")
}
```

---

## Installation

Add the package in Xcode (**File ▸ Add Package Dependencies…**) with:

```
https://github.com/rozd/user-kit
```

Or in `Package.swift`:

```swift
.package(url: "https://github.com/rozd/user-kit", branch: "main"),
```

You’ll usually also add a **provider adapter**, e.g. [`user-kit-firebase`](https://github.com/rozd/user-kit-firebase). The adapter is a separate package so apps that don’t use a given provider never pull in its SDK.

## Quick start

**1. Build one `User` from an adapter and inject it.** Only this file imports the adapter; the rest of your app imports just `UserKit`.

```swift
import SwiftUI
import UserKit
import UserKitFirebase   // your chosen adapter

extension User {
    @MainActor static let current = User(
        service: FirebaseUserService(configuration: .init(
            authDomain: "auth.example.com",
            bundleID: Bundle.main.bundleIdentifier!
        )),
        storage: FirebaseUserStorage(),
        synchronizer: FirebaseUserSynchronizer()
    )
}

@main
struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            RootView().environment(User.current)
        }
    }
}
```

**2. Read the current user anywhere.**

```swift
import SwiftUI
import UserKit

struct ProfileView: View {
    @Environment(User.self) private var user

    var body: some View {
        if user.isAuthenticated {
            Text(user.info?.profile.displayName ?? "Signed in")
            if user.isAdmin { AdminPanelLink() }          // gate admin-only UI
            Button("Sign out") { Task { try? await user.signOut() } }
        } else {
            Button("Sign in") { Task { try? await user.signIn() } }
        }
    }
}
```

## What you get

Everything below is on `User`:

| Member | What it does |
| --- | --- |
| `info` | Current user snapshot (`id`, `session`, `profile`, `role`), or `nil` when signed out. |
| `isAuthenticated` | Whether there’s a valid session. |
| `isAdmin` | Convenience for `role == "admin"`. |
| `signIn()` / `signOut()` | Sign in / out via the provider. |
| `authenticate()` | Present the provider’s auth UI. |
| `withAuthentication { … }` | Run work with a guaranteed-valid session (refreshes as needed). |
| `infos` | An `AsyncSequence` of distinct user changes, for observing outside SwiftUI. |

## Bring your own provider

An adapter is a small package that `import UserKit` and provides concrete conformers to six protocols:

- **Behavior:** `UserService` (sign in/out, verify email, present auth UI), `UserStorage` (persist the last-known user), `UserSynchronizer` (auth state as an `AsyncSequence`).
- **Data:** `UserInfo`, `UserSession`, `UserProfile`.

Then the app builds `User(service:storage:synchronizer:)`. See [`user-kit-firebase`](https://github.com/rozd/user-kit-firebase) for a complete reference implementation, and `Tests/UserKitTests/AdminRoleTests.swift` for the smallest possible conformer set.

## Requirements

- Swift **6.2+**, iOS **18+**, macOS **15+**
- UserKit is built with *Approachable Concurrency* (`MainActor` default isolation + `NonisolatedNonsendingByDefault`). Enable the same on your app target so isolation lines up across the package boundary.
- **Android / Skip:** UserKit is a plain cross-platform Swift package — [Skip](https://skip.dev) Fuse (native) apps can depend on it directly, with no Skip-specific setup on either side, and CI verifies the test suite on an Android emulator. Skip's transpiled (Lite) mode is not supported.

## License

[MIT](LICENSE) © Max Rozdobudko
