#!/bin/sh
set -e

# wrangler.jsonc ships GOVEE_API_KEY as "REMOVED". If a real key is provided via
# the environment, write it to .dev.vars so wrangler's local runtime picks it up
# (this overrides the value in wrangler.jsonc for `wrangler dev`).
: > /app/.dev.vars
if [ -n "$GOVEE_API_KEY" ]; then
  echo "GOVEE_API_KEY=$GOVEE_API_KEY" >> /app/.dev.vars
fi
if [ -n "$PANEL_PASSWORD" ]; then
  echo "PANEL_PASSWORD=$PANEL_PASSWORD" >> /app/.dev.vars
fi

# Regenerate the Cloudflare binding types before starting (matches the
# `cf-typegen` npm script), so they stay in sync with wrangler.jsonc.
npx wrangler types --env-interface CloudflareEnv ./cloudflare-env.d.ts

# --ip 0.0.0.0 is required so the worker is reachable from outside the container.
exec npx wrangler dev --ip 0.0.0.0 --port "${PORT:-8787}" "$@"
