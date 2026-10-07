# device_panel

A Cloudflare Worker (itty-router) that controls Govee lights. The runtime entry
point is `src/index.ts` (see `wrangler.jsonc`), so it runs under the workerd
runtime via `wrangler dev` — not a plain Node server.

## Run in Docker

Build and boot:

```bash
docker build -t device-panel .
docker run --rm -p 8787:8787 -e GOVEE_API_KEY=your-real-key device-panel
```

Or with Compose:

```bash
GOVEE_API_KEY=your-real-key docker compose up --build
```

Then the worker is available at http://localhost:8787 — e.g.:

```bash
curl http://localhost:8787/                # list of actions
curl http://localhost:8787/home            # HTML panel (ASSETS binding)
curl http://localhost:8787/getLivingRoomState
```

`GOVEE_API_KEY` is optional to boot but required for the Govee API calls to
succeed; when set it's written to `.dev.vars` at startup and overrides the
placeholder in `wrangler.jsonc`. Override the port with `-e PORT=xxxx`.

## Native iOS app

The SwiftUI app, interactive widget, Shortcuts/App Intents, and iOS 18 Control
Center control live in [`ios/`](ios/). It targets iOS 17 and uses the versioned
`/api/v1` Worker routes. The Worker keeps Govee credentials server-side and
issues revocable native-app sessions through a Durable Object.

See [`ios/README.md`](ios/README.md) for Xcode setup and test commands. The
shared mobile requirements and rollout plan are in
[`docs/mobile-app-plan.md`](docs/mobile-app-plan.md).
