# Native iOS and Android conversion plan

## Shared product requirements — source of truth

This table defines the behavior both native apps must follow. A requirement is not complete until its automated acceptance checks pass on both platforms, except where the row names only one platform. `P0` blocks the first release; `P1` is the first native enhancement release; `P2` is optional follow-up work.

| ID | Priority | Applies to | Requirement | Acceptance criteria |
|---|---|---|---|---|
| AUTH-01 | P0 | Both | Sign in to the configured Device Panel server with the shared panel password. | Correct credentials open the control screen; incorrect, expired, or revoked credentials keep the user signed out and show a useful error. |
| AUTH-02 | P0 | Both + API | Exchange the password for a revocable session token. Never store the password or put it in a cookie/token value. | The password is absent from device storage and request logs after sign-in; the API accepts the token and can revoke it. |
| AUTH-03 | P0 | Both | Store the session token in OS-protected storage that the app and its widget can share. | iOS uses a Keychain access group; Android uses Keystore-backed encrypted storage. Signing out removes app and widget access. |
| AUTH-04 | P0 | Both | Keep the Govee API key only on the Cloudflare Worker. | App packages, local storage, diagnostics, and network requests never contain `GOVEE_API_KEY`. |
| CFG-01 | P0 | Both | Let a user configure an HTTPS server URL during onboarding and edit it later. | Invalid/non-HTTPS URLs are rejected outside debug builds; a connection test distinguishes server, authentication, and network errors. |
| ROOM-01 | P0 | Both | Treat “Living Room” as one controllable group. A command applies to all ten currently configured lights. | One user action produces one room command; the clients do not contain device IDs, SKUs, or Govee temperature ranges. |
| STATE-01 | P0 | Both | Use the same room state model: `on`, `brightness` (1–100), `colorTemperaturePct` (0–100), color mode, connection state, and observation time. | The same API fixture decodes to equivalent values in Swift and Kotlin. Missing or malformed fields fail safely rather than becoming zero/false. |
| STATE-02 | P0 | Both | Fetch observed state after sign-in, whenever the main screen becomes active, on pull-to-refresh, and after a manual retry. | Fresh server state replaces displayed state only when no newer local command is pending. A loading state is visible before the first successful read. |
| STATE-03 | P0 | Both | Show whether state is loading, connected, applying, stale/offline, or failed; do not communicate status by color alone. | VoiceOver/TalkBack announces status text, and the visual design includes an icon or label in addition to color. |
| PWR-01 | P0 | Both | Provide one large power control for the room. Tap toggles it; a second power command is blocked while the first is in flight. | UI updates immediately, one API command is sent, and a failed command restores the last confirmed value and exposes Retry. |
| BRI-01 | P0 | Both | Provide brightness presets at exactly 10%, 50%, 75%, and 100%. | Selecting a preset highlights it immediately and sends one command. Failure restores the last confirmed selection/value. |
| BRI-02 | P0 | Both | Display a server-reported non-preset brightness accurately without falsely selecting a preset. | A state such as 34% displays as 34%, with none of the four preset buttons selected. |
| TMP-01 | P0 | Both | Provide a continuous warm-to-cool control whose API value is 0–100. | The displayed label maps 0 to `Warm −100%`, 50 to `0%`, and 100 to `Cool +100%`. |
| TMP-02 | P0 | Both | Update temperature locally while dragging, then send exactly one command when the interaction commits. | Dragging across many values produces one API call on release; keyboard/switch-control adjustment also has a clear commit. |
| CLR-01 | P0 | Both | Provide the two colors supported by the server: red and orange. | Each selection sends one valid color command and reports success/failure. |
| CLR-02 | P0 | Both | Do not ship the web app’s unsupported “Custom 1” and “Custom 2” actions. | No production control sends `custom1` or `custom2`. Custom colors require a future API contract and a new requirement ID. |
| CMD-01 | P0 | Both + API | Send mutations with `POST`/`PATCH`, a unique command ID, a stable installation ID, and a monotonically increasing client revision. | Automatic retries cannot apply one command twice, and an older response cannot overwrite a newer user choice. |
| CMD-02 | P0 | Both | Use optimistic UI for power, brightness, color, and temperature; retain the last confirmed state for rollback. | Success confirms the optimistic state. Failure restores the affected field, gives haptic/visual feedback, and leaves unrelated newer fields unchanged. |
| SYNC-01 | P0 | Both + API | Reconcile desired state after each successful command using delays of 3, 6, 10, and 15 seconds, stopping when synchronized. A newer action cancels and restarts that sequence. | Contract tests prove early exit, cancellation, stale-revision handling, and at most four reconciliation attempts. |
| SYNC-02 | P0 | Both | Do not reapply temperature while the selected mode is a fixed color, and do not reapply brightness/temperature while desired power is off. | Reconciliation request fixtures omit temperature in color mode; server tests prove an off room is not switched on by level correction. |
| LIFE-01 | P0 | Both | Share desired state, install ID, revision, and last confirmed state with native extensions. | App, widget, shortcut, tile, or system control cannot race with an older revision from the same installation. |
| OFF-01 | P0 | Both | When offline, show the last confirmed state as stale and do not queue home-control commands for later delivery. | Reopening after a failed/offline action does not unexpectedly operate lights; the user can explicitly retry when connected. |
| UX-01 | P0 | Both | Follow each platform’s native layout, navigation, controls, safe areas, dark mode, and text scaling while retaining the current dark blue visual identity. | The apps work in portrait and landscape, on phone and tablet, without clipping at the largest supported text size. |
| A11Y-01 | P0 | Both | Give every control a meaningful label, value, trait/role, and focus order. | Full power, brightness, color, temperature, retry, settings, and sign-out flows work with VoiceOver and TalkBack. |
| A11Y-02 | P0 | Both | Meet platform touch target, contrast, reduced-motion, and haptic-accessibility guidance. | Targets are at least 44×44 pt on iOS and 48×48 dp on Android; animations respect Reduce Motion; haptics are supplemental. |
| ERR-01 | P0 | Both | Distinguish authentication, permission, timeout, offline, server, and malformed-response failures in app behavior. | Authentication returns to sign-in; transient failures preserve state and allow retry; no raw secrets or stack traces appear in UI. |
| SEC-01 | P0 | Both | Require TLS, redact credentials/tokens, and collect no analytics by default. | Release builds block cleartext traffic, security tests inspect logs, and store privacy declarations match actual collection. |
| API-01 | P0 | Both + API | Version and document the mobile API in OpenAPI, with shared request/response/error fixtures. | Swift and Kotlin generated or hand-written models pass the same fixture suite; incompatible changes require a new API version. |
| QA-01 | P0 | Both | Cover state reduction, mapping, command ordering, rollback, reconciliation, auth expiry, lifecycle refresh, and accessibility with automated tests. | Required unit, integration, UI, and contract suites pass in CI for every release branch. |
| IOS-01 | P1 | iOS | Add an interactive WidgetKit widget with room status, power, and brightness presets. | Small widget supports power; medium widget supports power plus presets; actions use App Intents and refresh state after completion. |
| IOS-02 | P1 | iOS | Expose power and brightness through App Intents for Shortcuts, Siri, Spotlight, and an iOS 18+ Control Center control. | An authenticated user can run each action without opening the app; locked-device behavior follows the user’s explicit security setting. |
| IOS-03 | P1 | iOS | Use native haptics and support iPad multitasking. | Success/error haptics are subtle and optional; split view and stage-sized windows remain usable. |
| AND-01 | P1 | Android | Add a Glance home-screen widget with room status, power, and brightness presets. | Small and medium layouts match iOS capabilities; actions refresh the widget and show auth/offline state. |
| AND-02 | P1 | Android | Add a Quick Settings tile and pinned app shortcuts for power and favorite brightness levels. | Tile state is accurate when refreshed and actions never run with an expired session. |
| AND-03 | P1 | Android 11+ | Publish the room through `ControlsProviderService` so it appears in Android Device Controls. | Power and level control work from the system surface with authentication rules matching the main app. |
| NTF-01 | P2 | Both | Notify only for a user-requested automation or repeated command failure; do not notify for ordinary successful taps. | Notifications are opt-in, actionable, and deep-link to the relevant screen. |
| WEA-01 | P2 | Both | Consider Apple Watch and Wear OS companions only after widget usage shows demand. | No watch target blocks the first two releases; a later proposal reuses the versioned API and shared requirements. |

### How to change the source of truth

1. Update the requirement row and keep its ID stable; add a new ID for new behavior.
2. Update the OpenAPI document and shared JSON fixtures when the network contract changes.
3. Update the linked Swift and Kotlin tests before merging either client change.
4. Record intentionally different platform behavior in the “Applies to” column. Unrecorded differences are bugs.

## Current app behavior to preserve or repair

| Area | Current implementation | Native-app decision |
|---|---|---|
| Backend | Cloudflare Worker talks to Govee; clients never see the Govee key. | Keep this boundary. Native apps call the Worker only. |
| Authentication | A 30-day HTTP-only cookie contains the shared password itself. | Replace with a revocable opaque session token; keep cookie routes temporarily for the web app. |
| Room | A hard-coded Living Room group fans commands out to ten Govee lights. | Keep the first release single-room. Move device inventory fully behind the API. |
| State read | Reads one representative light rather than all ten. | Preserve for initial parity, but expose that fact as `stateSource: representative`; add per-device health later if needed. |
| Power | Optimistic draggable/tappable switch, with rollback on failure. | Use a native switch/button with identical single-flight and rollback rules. |
| Brightness | Four presets: 10, 50, 75, 100. | Preserve the presets and correctly show observed non-preset values. |
| Temperature | Raw 0–100, displayed as −100% to +100%; one request on commit. | Preserve the mapping and commit-only network behavior. |
| Colors | Red and orange work. Two custom buttons are sent but rejected by the backend. | Ship red/orange only; design a real RGB/preset contract before adding custom colors. |
| Reconciliation | Desired state is retried at 3/6/10/15 seconds with client revision protection. | Put the same algorithm in a tested domain layer on each platform, using a stable install ID shared with extensions. |
| Errors | A dot turns green/red and some controls roll back. | Use text plus icon/color, field-level rollback, haptics, and explicit Retry. |

## Target architecture

```text
iOS app ─┬─ WidgetKit / App Intents / Control Center ─┐
         └─ Swift domain + API client + shared store ─┤
                                                      ├─ Cloudflare Worker API ─ Govee API
Android ─┬─ Glance / Tile / Device Controls ──────────┤
         └─ Kotlin domain + API client + shared store ┘
```

The native codebases should share behavior and fixtures, not source code. This keeps SwiftUI and Jetpack Compose idiomatic while the requirements and API prevent drift.

### Suggested repository layout

```text
contracts/
  openapi.yaml
  fixtures/
    auth/
    room-state/
    commands/
    errors/
ios/
  DevicePanel.xcodeproj
  DevicePanel/
  DevicePanelWidget/
  DevicePanelTests/
  DevicePanelUITests/
android/
  app/
  core/model/
  core/network/
  core/domain/
  feature/control/
  feature/settings/
  widget/
docs/
  mobile-app-plan.md
```

## API work required before native clients

Add `/api/v1` routes and leave the existing web routes working during migration.

| Method and route | Purpose | Minimum contract |
|---|---|---|
| `POST /api/v1/sessions` | Sign in | Request: password and installation metadata. Response: opaque token, expiry, user-safe server label. Rate-limit failures. |
| `DELETE /api/v1/session` | Sign out/revoke | Invalidates the current token and returns `204`. |
| `GET /api/v1/rooms/living-room` | Read room state | Returns validated `on`, `brightness`, `colorTemperaturePct`, `colorMode`, `observedAt`, and source/health metadata. |
| `POST /api/v1/rooms/living-room/commands` | Apply one atomic user intent | Accepts `commandId`, `clientId`, `revision`, and one or more desired fields. Returns accepted/confirmed state and stable error codes. |
| `POST /api/v1/rooms/living-room/reconcile` | Check and repair drift | Accepts the desired snapshot and revision. Returns observed state, `synchronized`, `corrected`, and `stale`. |

Backend rules:

- Validate all inputs: brightness 1–100, temperature 0–100, and only documented color values.
- Use an idempotency record for `commandId`; do not rely only on Worker memory.
- Persist sessions and latest client revisions in a durable server-side store. Hash session tokens at rest.
- Use stable JSON error codes such as `AUTH_EXPIRED`, `OFFLINE`, `UPSTREAM_TIMEOUT`, `INVALID_VALUE`, and `RATE_LIMITED`.
- Add request timeouts and bounded retry/backoff for safe Govee calls. Never retry a mutation unless the command is idempotent.
- Keep secrets out of bodies, URLs, analytics, and logs. Mutations must not use `GET`.
- Decide whether “room state” means representative-light state or aggregated fleet state. The first release may retain the representative read, but the response must say so.

## iOS implementation plan

Target: Swift 6, SwiftUI, structured concurrency, and iOS 17+. Use iOS 18 APIs conditionally.

1. Create the app, widget extension, app group, Keychain access group, URL schemes/universal links, and build configurations for local, staging, and production servers.
2. Build `APIClient` with `URLSession`, `Codable` models, bearer-token injection, typed server errors, TLS-only policy, cancellation, and request timeouts.
3. Build an `actor`-isolated room repository that owns the install ID, revision counter, last confirmed state, desired state, command single-flight rules, and reconciliation task cancellation.
4. Build onboarding/sign-in and settings. Store only the token in shared Keychain; store non-secret state in the app-group container.
5. Build the SwiftUI control screen: status banner, power control, red/orange swatches, brightness preset grid, temperature slider, refresh, retry, and settings.
6. Add lifecycle refresh with `scenePhase`, pull-to-refresh, accessible labels/adjustable actions, Dynamic Type, Reduce Motion, VoiceOver tests, and haptics.
7. Add WidgetKit/App Intents. Small: status + power. Medium: status + power + four brightness presets. Use shared repository data, show its age, and request a timeline reload after actions.
8. Add App Intents for power and brightness, donate useful shortcuts, and add an iOS 18+ Control Center control. Require device unlock for controls if the user enables the stricter security option.
9. Add unit tests for models/reducer/reconciliation, `URLProtocol` integration tests, snapshot tests at key Dynamic Type sizes, and XCUITests for sign-in and every control flow.

## Android implementation plan

Target: Kotlin, Jetpack Compose, Material 3, coroutines/Flow, and minimum Android 8 (API 26). Enable Android 11+ features conditionally.

1. Create Gradle modules for app UI, domain/model, network, persistence, and widget/system integrations. Add debug, staging, and release server configurations.
2. Build a Retrofit/OkHttp API client with Kotlin serialization, bearer-token injection, typed errors, TLS-only network security config, cancellation, and timeouts.
3. Build a single room repository with coroutines and `StateFlow`; serialize commands with a `Mutex`, persist the install ID/revision, and cancel/restart reconciliation jobs on new actions.
4. Build onboarding/sign-in and settings. Store the token with Keystore-backed encryption and non-secret state in DataStore, with a safe bridge for widgets/system services.
5. Build the Compose control screen: status banner, power control, red/orange swatches, brightness preset grid, temperature slider, swipe-to-refresh, retry, and settings.
6. Add lifecycle refresh, adaptive layouts for phones/tablets/foldables, TalkBack semantics, font scaling, reduced animation, edge-to-edge layout, and haptics.
7. Add a Jetpack Glance widget matching iOS small/medium capabilities. Update it through WorkManager only for explicit refresh/command completion; do not promise live polling.
8. Add a Quick Settings tile, dynamic/pinned shortcuts, and Android 11+ `ControlsProviderService`. All surfaces use the same repository contract and auth state.
9. Add unit tests for models/reducer/reconciliation, MockWebServer integration tests, Compose UI/screenshot tests, accessibility checks, and instrumentation tests for core flows.

## Delivery sequence and exit gates

| Phase | Work | Exit gate |
|---|---|---|
| 0. Contract | Approve the requirements table, minimum OS versions, server URL model, and representative-vs-fleet state decision. | Product decisions recorded; requirement IDs frozen for v1. |
| 1. Backend | Add versioned token auth, state/command/reconcile endpoints, validation, durable idempotency/revisions, OpenAPI, and fixtures. | Worker tests pass; web panel still works; security review finds no credential exposure. |
| 2. Native foundations | Scaffold Swift/Kotlin projects, API clients, secure storage, repositories, shared fixture tests, and CI. | Both apps sign in and pass identical contract fixtures against a mock server. |
| 3. Core parity | Implement power, brightness, colors, temperature, state/status, rollback, reconcile, settings, and accessibility. | Every P0 requirement has an automated check on both platforms; staging smoke test controls the real room. |
| 4. Native surfaces | Add iOS widget/App Intents/Control Center and Android widget/tile/shortcuts/Device Controls. | All P1 actions honor auth, revision ordering, offline behavior, and widget refresh limits. |
| 5. Release | App icons, screenshots, privacy text, support URL, signing, TestFlight/Internal App Sharing, crash-free beta, and store submissions. | Two-device beta passes for one week with no credential, stale-command, or unwanted-operation issue. |

With one backend engineer and one engineer per mobile platform working in parallel, plan for roughly 5–7 weeks through beta: one week for the contract/backend, two to three weeks for native foundations and core parity, one week for native system surfaces, and one week for hardening/beta. A single engineer building both clients sequentially should plan for roughly 9–12 weeks. Treat these as planning ranges until Phase 0 decisions and store-account readiness are confirmed.

## Test and release matrix

Test at minimum:

- iPhone small-screen and current standard size; iPad split view; light/dark mode; largest accessibility text; VoiceOver; reduced motion.
- Android compact phone, large phone, tablet/foldable width; API 26 and current API; light/dark mode; largest font/display size; TalkBack; reduced animation.
- Fresh install, bad URL, bad password, expired/revoked token, server 4xx/5xx, timeout, airplane mode, app killed mid-command, rapid repeated input, app/widget race, and server response arriving out of order.
- State values at boundaries and malformed values: brightness 1/10/34/100, temperature 0/50/100, unknown color mode, missing fields, and clock skew.
- Widget/system actions while signed out, device locked, token expired, network absent, and main app running concurrently.

## Decisions to confirm before implementation

The plan assumes:

1. The first release controls only the existing Living Room group, not individual bulbs or multiple rooms.
2. iOS 17+ and Android 8+/API 26 are acceptable minimums.
3. The Cloudflare Worker remains the only component that talks to Govee.
4. Offline commands are not queued; this prevents a stale tap from operating lights later without context.
5. Red and orange are the only color presets in v1; custom colors wait for a supported API.
6. Widgets expose power and brightness, while full color-temperature control stays in the app.
7. Store distribution is intended. If this is a private household app, TestFlight and private/internal Android distribution can reduce release overhead.
