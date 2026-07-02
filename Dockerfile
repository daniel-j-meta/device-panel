# device-panel is a Cloudflare Worker (see wrangler.jsonc `main: src/index.ts`).
# It imports `cloudflare:workers` and needs `nodejs_compat`, so it can only run
# under the workerd runtime — i.e. via `wrangler dev`, not plain `node`.
FROM node:22-bookworm-slim

# Wrangler is chatty about metrics/updates; keep it quiet and non-interactive.
ENV WRANGLER_SEND_METRICS=false \
    CI=true \
    NODE_ENV=development

WORKDIR /app

# Install dependencies first for better layer caching. `npm ci` also pulls the
# platform workerd binary (@cloudflare/workerd-linux-64) that `wrangler dev` runs.
COPY package.json package-lock.json ./
RUN npm ci

# Copy the rest of the source.
COPY . .

# Default wrangler dev port.
EXPOSE 8787

COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

ENTRYPOINT ["docker-entrypoint.sh"]
