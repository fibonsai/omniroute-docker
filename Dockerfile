# ---------------------------------------------------------------------------
# Stage 1 - install OmniRoute into a self-contained prefix
#
# A separate stage keeps build tools, the npm cache, and package-manager
# metadata out of the runtime image.
# ---------------------------------------------------------------------------
FROM node:lts-alpine AS builder

# Only needed if a native dependency has no musl prebuild. They are not copied
# into the final image.
RUN apk add --no-cache --virtual .build-deps python3 make g++ linux-headers

# Pin a release for reproducible builds:
#   docker build --build-arg OMNIROUTE_VERSION=3.8.53 -t omniroute-docker .
ARG OMNIROUTE_VERSION=latest

# Optional dependencies add roughly 1 GB (ONNX runtime, transformers,
# LLMLingua, js-tiktoken, sqlite-vec, keytar, wreq-js). They are omitted by
# default because most container deployments do not need local embeddings or
# OS keychain support. Set to true for the full feature set.
ARG INSTALL_OPTIONAL_DEPS=false

# Remove translated documentation from the runtime tree; English docs stay.
ARG REMOVE_TRANSLATED_DOCS=true

ENV NPM_CONFIG_CACHE=/tmp/npm-cache \
    NPM_CONFIG_AUDIT=false \
    NPM_CONFIG_FUND=false \
    NPM_CONFIG_UPDATE_NOTIFIER=false \
    PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1

# A local install honors --omit=optional; `npm install -g` ignores that flag.
# The package.json written by the first install keeps the second install from
# pruning the tree; both it and the hidden lockfile are removed afterwards.
RUN set -eux; \
    if [ "$INSTALL_OPTIONAL_DEPS" = "true" ]; then \
      OPTIONAL="--include=optional"; \
    else \
      OPTIONAL="--omit=optional"; \
    fi; \
    npm install \
      --prefix /opt/omniroute \
      --no-package-lock \
      --omit=dev \
      "$OPTIONAL" \
      --dangerously-allow-all-scripts \
      "omniroute@$OMNIROUTE_VERSION"; \
    if [ "$INSTALL_OPTIONAL_DEPS" != "true" ]; then \
      SQLITE_RANGE="$(node -p "require('/opt/omniroute/node_modules/omniroute/package.json').optionalDependencies['better-sqlite3']")"; \
      if [ -n "$SQLITE_RANGE" ] && [ "$SQLITE_RANGE" != "undefined" ]; then \
        npm install \
          --prefix /opt/omniroute \
          --no-save \
          --no-package-lock \
          --omit=dev \
          --omit=optional \
          --dangerously-allow-all-scripts \
          "better-sqlite3@$SQLITE_RANGE"; \
      fi; \
    fi; \
    rm -rf /tmp/npm-cache /opt/omniroute/package.json /opt/omniroute/node_modules/.package-lock.json; \
    DATA_DIR=/tmp/omniroute-smoke HOME=/tmp \
      node /opt/omniroute/node_modules/omniroute/bin/omniroute.mjs --version; \
    DATA_DIR=/tmp/omniroute-smoke HOME=/tmp \
      node /opt/omniroute/node_modules/omniroute/bin/omniroute.mjs providers validate; \
    rm -rf /tmp/omniroute-smoke

# English documentation is compiled into the Next.js app. Removing the
# translation tree makes non-English docs fall back to English.
RUN if [ "$REMOVE_TRANSLATED_DOCS" = "true" ]; then \
      rm -rf /opt/omniroute/node_modules/omniroute/dist/docs/i18n; \
    fi

# ---------------------------------------------------------------------------
# Stage 2 - runtime image
# ---------------------------------------------------------------------------
FROM node:lts-alpine

RUN apk add --no-cache ca-certificates curl libc6-compat tzdata

# Copy only the installed application. Build tools, npm cache, and install
# metadata from the builder stage never reach this image.
COPY --from=builder /opt/omniroute /opt/omniroute

RUN ln -s /opt/omniroute/node_modules/omniroute/bin/omniroute.mjs /usr/local/bin/omniroute \
 && ln -s /opt/omniroute/node_modules/omniroute/bin/reset-password.mjs /usr/local/bin/omniroute-reset-password \
 && mkdir -p /workspace /home/node/.omniroute \
 && chown node:node /workspace /home/node/.omniroute \
 && chmod 700 /home/node/.omniroute

USER node
WORKDIR /workspace

ENV NODE_ENV=production \
    DATA_DIR=/home/node/.omniroute \
    INITIAL_PASSWORD=q1w2e3

EXPOSE 20128 20129
