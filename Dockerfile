# syntax=docker/dockerfile:1

# Builds the firebolt.dev website (packages/website) against the firebolt
# packages in this repo, so the docs always run on the current source.

FROM node:22-bookworm-slim AS base
WORKDIR /app

FROM base AS dependencies
# Chromium comes from apt in the runtime image, so skip Puppeteer's download.
ENV PUPPETEER_SKIP_DOWNLOAD=true

# Only manifests first, so source changes reuse the installed dependencies.
# Add a line here when a new package is added to packages/.
COPY package.json package-lock.json ./
COPY packages/cors/package.json ./packages/cors/
COPY packages/create-firebolt/package.json ./packages/create-firebolt/
COPY packages/css/package.json ./packages/css/
COPY packages/firebolt/package.json ./packages/firebolt/
COPY packages/icons/package.json ./packages/icons/
COPY packages/jsx/package.json ./packages/jsx/
COPY packages/snap/package.json ./packages/snap/
COPY packages/website/package.json ./packages/website/
RUN --mount=type=cache,target=/root/.npm \
    npm ci --no-audit --no-fund

FROM dependencies AS build
COPY packages ./packages
# Build the packages the website uses, then the website itself. The website
# build calls firebolt's dist directly: npm ci ran before dist existed, so on
# Linux it never linked the `firebolt` bin.
RUN npm run build \
      -w packages/css -w packages/jsx -w packages/firebolt \
      -w packages/icons -w packages/cors -w packages/snap \
    && cd packages/website \
    && node ../firebolt/dist/index.js build

FROM base AS production
# Chromium renders the /og share images via @firebolt-dev/snap.
RUN apt-get update \
    && apt-get install -y --no-install-recommends chromium \
    && rm -rf /var/lib/apt/lists/*

ENV NODE_ENV=production \
    PORT=3000 \
    PUBLIC_DOMAIN=https://firebolt.dev \
    PUPPETEER_EXECUTABLE_PATH=/usr/bin/chromium

COPY --from=build --chown=node:node /app /app
USER node
WORKDIR /app/packages/website

EXPOSE 3000

# Use Node's built-in HTTP client rather than installing curl in the runtime.
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
    CMD node -e "fetch('http://127.0.0.1:' + process.env.PORT + '/', { signal: AbortSignal.timeout(4000) }).then(r => process.exit(r.ok ? 0 : 1)).catch(() => process.exit(1))"

CMD ["node", "../firebolt/dist/index.js", "start"]
