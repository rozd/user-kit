# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

UserKit is the **provider-neutral core** of a "current authenticated user" layer for SwiftUI apps. It ships only protocols and the `@MainActor @Observable final class User` orchestrator — no concrete auth provider. Its only dependency is `swift-async-algorithms`.

Concrete providers live in **separate repos** (e.g. `rozd/user-kit-firebase`, module `UserKitFirebase`, local clone at `../user-kit-firebase`). **Never add a provider SDK** (FirebaseAuth, Auth0, etc.) as a dependency here: SPM resolves every dependency declared in a manifest for every consumer, so a provider dependency here would drag that SDK into every app that links UserKit. Keeping the core provider-free is the whole point of the package.

## Build & test

- Build: `swift build`
- Test: `swift test` — tests use **swift-testing** (`import Testing`, `@Suite`/`@Test`/`#expect`), not XCTest.
- Single suite/test: `swift test --filter AdminRoleTests` (append `/isAdminCaseSensitive` for one test).
- Format: `swift format --in-place --recursive Sources Tests` (config in `.swift-format`; lint-only: `swift format lint --recursive Sources Tests`). `public extension` blocks are intentional — the `NoAccessLevelOnExtensionDeclaration` rule is disabled.

## Concurrency dialect (do not break)

Every target sets these Swift settings, and any new target must mirror them:

```swift
swiftSettings: [
    .defaultIsolation(MainActor.self),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
]
```

They match the consumer apps' "Approachable Concurrency" dialect so async-closure isolation lines up across the package boundary. Drop them and adapter protocol conformances mismatch (`nonisolated(nonsending)` vs `@concurrent`). Types meant to run off the main actor are explicitly marked `nonisolated` (`UserId`, `UserStorage`, `UserSynchronizer`, `UserInfo`, `UserSession`, `UserProfile`, and `User.infos`); `User` and `UserService` are `@MainActor`.

## Skip / Android compatibility (do not break)

UserKit works in [Skip](https://skip.dev) Fuse (native) apps as a **plain SwiftPM dependency**, so it must keep cross-compiling with the Swift SDK for Android. There is deliberately **no Skip integration** in this repo (no `skip.yml`, no `skipstone` plugin, no `SkipFuse` dependency): Fuse apps compile plain packages directly, and declaring Skip packages in the manifest would drag them into every consumer — the same reasoning that bans provider SDKs. Skip Lite (transpiled) apps are out of scope: the API surface (`any AsyncSequence<…>` existentials, macros, AsyncAlgorithms) can neither transpile to Kotlin nor be bridged.

- Foundation re-exports Observation **only on Darwin** — keep the explicit `import Observation` in `User.swift`, and add it to any new file using `@Observable`.
- No Darwin-only frameworks (UIKit, Security, os.log, …) in core.
- CI builds and runs the test suite on an Android emulator via `skiptools/swift-android-action` (`.github/workflows/android.yml`).
- Verify locally (requires the swift.org toolchain matching the installed Android SDK — Xcode's toolchain fails with a module-version mismatch):

```sh
TOOLCHAINS=$(/usr/libexec/PlistBuddy -c "Print CFBundleIdentifier" \
    ~/Library/Developer/Toolchains/swift-6.3.3-RELEASE.xctoolchain/Info.plist) \
    swift build --swift-sdk swift-6.3.3-RELEASE_android
```

## Conventions & gotchas

- `UserService.singIn()` is **misspelled** (should be `signIn`); `User.signIn()` (correct) forwards to `service.singIn()`. Adapters conform to the misspelled name, so renaming the protocol requirement is a breaking change across every adapter repo — don't "fix" it in isolation.
- `User.service` is intentionally `public` because adapters downcast it (e.g. `firebaseAuthService`). Don't tighten its access. `storage`/`synchronizer` stay internal.
- `isAdmin` is core sugar for `role == "admin"` — **case-sensitive**; `nil`/empty → not admin. `UserInfo.role` defaults to `nil`; adapters override it (e.g. from a JWT custom claim).
- All `UserInfo` conformers are `Equatable` **by `id` only** (default `==` in the extension) — session/profile differences don't affect equality.
- Platforms: iOS 18, macOS 15.

## Adding a provider adapter

Adapters are separate packages that `import UserKit`, conform concrete types to `UserService` / `UserStorage` / `UserSynchronizer` (plus the value protocols `UserInfo` / `UserSession` / `UserProfile`), and construct `User(service:storage:synchronizer:)`. `Tests/UserKitTests/AdminRoleTests.swift` holds the canonical minimal set (the `Stub*` types); `../user-kit-firebase` is the reference implementation. The `using-userkit` skill under `.claude/skills/` documents this contract for consuming apps.
