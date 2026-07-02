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
