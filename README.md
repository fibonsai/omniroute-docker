# omniroute-docker

A minimal Alpine-based Docker image for [OmniRoute](https://github.com/diegosouzapw/OmniRoute) — a unified AI gateway that exposes hundreds of providers behind a single OpenAI-compatible endpoint.

The image is built in two stages: a builder stage installs the official [`omniroute`](https://www.npmjs.com/package/omniroute) npm package into a self-contained prefix, and a fresh `node:lts-alpine` runtime stage receives only the installed application. The server runs as the unprivileged `node` user.

- **Dashboard / API:** `http://localhost:20128`
- **OpenAI-compatible base URL:** `http://localhost:20128/v1`
- **Live monitoring WebSocket:** port `20129`
- **Data directory:** `/home/node/.omniroute` (mount a volume here)

> This is an unofficial packaging wrapper. OmniRoute itself is MIT-licensed and maintained upstream by [Diego Souza](https://github.com/diegosouzapw).

## Requirements

- Docker (or a compatible runtime such as Podman)
- Outbound network access during the build (to install the `omniroute` npm package)

## Quick start

```bash
# 1. Build the image
docker build -t omniroute-docker .

# 2. Run it
docker run -d \
  --name omniroute \
  --restart unless-stopped \
  -p 20128:20128 \
  -p 20129:20129 \
  -e INITIAL_PASSWORD='change-this-password' \
  -e NVIDIA_API_KEY='nvapi-...' \
  -v omniroute-data:/home/node/.omniroute \
  omniroute-docker
```

Then open <http://localhost:20128> and log in with `INITIAL_PASSWORD`.

NVIDIA, DeepSeek, Gemini, and Jina keys are read directly from the environment as provider fallbacks. Declare them at runtime via `docker run -e ...` or `--env-file`; see [Provider credentials](#provider-credentials).

`INITIAL_PASSWORD` is only applied while no dashboard password is stored. Changing the environment variable after the first boot does **not** change an existing password — use [`omniroute reset-password`](#reset-the-dashboard-password) instead.

The default build is lean: optional native/AI extras are omitted to keep the image small. See [Build options](#build-options) if you need local embeddings, LLMLingua compression, or the other optional engines.

## Usage

Once the container is running, point any OpenAI-compatible client at the gateway:

```bash
curl http://localhost:20128/v1/chat/completions \
  -H "Authorization: Bearer YOUR_OMNIROUTE_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "auto",
    "messages": [{ "role": "user", "content": "Hello!" }]
  }'
```

Create OmniRoute client keys in the dashboard under **Endpoints**. Provider API keys are declared via system environment at runtime (see [Provider credentials](#provider-credentials)); they must not be stored in OmniRoute's SQLite database. The `auto` model lets OmniRoute pick among your connected providers; `auto/coding`, `auto/cheap`, `auto/fast`, and other variants bias the selection.

## Provider credentials

Declare upstream provider API keys using system environment variables, passed to the container at runtime (do not bake them into the image). OmniRoute reads them as provider fallbacks:

- `NVIDIA_API_KEY`
- `DEEPSEEK_API_KEY`
- `GEMINI_API_KEY` / `GOOGLE_API_KEY`
- `JINA_AI_API_KEY` / `JINA_API_KEY`

Example:

```bash
docker run -d \
  --name omniroute \
  --restart unless-stopped \
  -p 20128:20128 \
  -e INITIAL_PASSWORD='change-this-password' \
  -e REQUIRE_API_KEY='true' \
  -e NVIDIA_API_KEY="${NVIDIA_API_KEY}" \
  -e DEEPSEEK_API_KEY="${DEEPSEEK_API_KEY}" \
  -e GEMINI_API_KEY="${GEMINI_API_KEY}" \
  -e JINA_AI_API_KEY="${JINA_AI_API_KEY}" \
  -v omniroute-data:/home/node/.omniroute \
  omniroute-docker
```

Or with an `--env-file`:

```bash
docker run -d \
  --name omniroute \
  --restart unless-stopped \
  -p 20128:20128 \
  -e INITIAL_PASSWORD='change-this-password' \
  -e REQUIRE_API_KEY='true' \
  --env-file provider.env \
  -v omniroute-data:/home/node/.omniroute \
  omniroute-docker
```

Where `provider.env` contains:

```
NVIDIA_API_KEY=sk-or-...
DEEPSEEK_API_KEY=sk-...
GEMINI_API_KEY=...
JINA_AI_API_KEY=...
```

For any other provider (not in the fallback list above), set its `*_API_KEY` variable the same way at runtime; OmniRoute reads provider keys from its environment. Do not store provider keys in OmniRoute's SQLite database — the database must not become a credential store. The sandbox agent (OpenShell) only ever sees `OMNIROUTE_API_KEY`, never upstream provider keys.

Provider-specific variables for the other supported providers are documented in OmniRoute's [environment reference](https://github.com/diegosouzapw/OmniRoute/blob/main/docs/reference/ENVIRONMENT.md).

A few variables are also read directly from OmniRoute's environment as fallbacks: `NVIDIA_API_KEY`, `DEEPSEEK_API_KEY`, `GEMINI_API_KEY`/`GOOGLE_API_KEY`, and `JINA_AI_API_KEY`/`JINA_API_KEY`. Declare them at runtime via `docker run -e ...` or `--env-file` (see [Provider credentials](#provider-credentials)).

## Configuration

The image is configured entirely through environment variables. The table below lists the values set in the `Dockerfile` plus the OmniRoute runtime settings that matter most in a container.

| Variable | Default in image | Description |
| --- | --- | --- |
| `INITIAL_PASSWORD` | `q1w2e3` | Dashboard password applied on first boot. **Override it.** |
| `PORT` | `20128` | Dashboard and API port. |
| `LIVE_WS_PORT` | `20129` | Live monitoring WebSocket port. |
| `DATA_DIR` | `/home/node/.omniroute` | SQLite database, secrets, backups, and plugins. |
| `NODE_ENV` | `production` | Node runtime mode. |
| `JWT_SECRET` | auto-generated | Signs dashboard session cookies. Set it explicitly if the data directory is ephemeral. |
| `API_KEY_SECRET` | auto-generated | Encrypts stored API keys at rest. Set it explicitly if the data directory is ephemeral. |
| `STORAGE_ENCRYPTION_KEY` | auto-generated | Optional full-database encryption key. Persisted to `$DATA_DIR/.env`. |
| `REQUIRE_API_KEY` | unset | Set to `true` to require an OmniRoute API key on `/v1/*`. Strongly recommended when publishing the port. |
| `OMNIROUTE_SERVER_HOST` | `0.0.0.0` | Bind address for the server. Use `127.0.0.1` to keep it loopback-only. |

A few provider variables are read directly from OmniRoute's environment as fallbacks: `NVIDIA_API_KEY`, `DEEPSEEK_API_KEY`, `GEMINI_API_KEY`/`GOOGLE_API_KEY`, and `JINA_AI_API_KEY`/`JINA_API_KEY`. Declare them at runtime via `docker run -e ...` (or an `--env-file`) when you want OmniRoute to use them (see [Provider credentials](#provider-credentials)).

Provider-specific variables for the other supported providers are documented in OmniRoute's [environment reference](https://github.com/diegosouzapw/OmniRoute/blob/main/docs/reference/ENVIRONMENT.md).

## Build options

The build accepts three arguments:

| Argument | Default | Description |
| --- | --- | --- |
| `OMNIROUTE_VERSION` | `latest` | npm version or tag to install. Pin it for reproducible deployments, e.g. `3.8.53`. |
| `INSTALL_OPTIONAL_DEPS` | `false` | Install OmniRoute's optional dependencies (about 1 GB extra). Set to `true` for the full feature set. |
| `REMOVE_TRANSLATED_DOCS` | `true` | Remove the non-English documentation tree. English docs are built into the app and remain available; other locales fall back to English. Set to `false` to keep all translations. |

```bash
# Reproducible, lean build
docker build \
  --build-arg OMNIROUTE_VERSION=3.8.53 \
  -t omniroute-docker .

# Full feature build (local ONNX embeddings, LLMLingua, sqlite-vec, ...)
docker build \
  --build-arg INSTALL_OPTIONAL_DEPS=true \
  -t omniroute-docker:full .

# Keep all translated documentation
docker build \
  --build-arg REMOVE_TRANSLATED_DOCS=false \
  -t omniroute-docker:translated .
```

## Image size and optional dependencies

The largest size wins come from installing into a disposable build stage and omitting optional dependencies:

- The runtime image contains only the installed application tree. The builder's `python3`/`make`/`g++` toolchain and the npm download cache stay in the disposable stage.
- The lean install tree is about 2.0 GB. Enabling `INSTALL_OPTIONAL_DEPS=true` adds roughly 1 GB of native and AI packages.
- On the same Podman host, the original single-stage `npm install -g` Dockerfile produced a **4.51 GB** image; this multi-stage lean build is **2.00 GB**, about **56% smaller**.
- OmniRoute's own `dist` tree is about 588 MB after removing translated documentation; it was about 969 MB with all translations. The removed `dist/docs/i18n` tree was about 381 MB. English docs are compiled into the app, so `/docs` still works; other locales fall back to English.
- The native SQLite driver (`better-sqlite3`) is **kept** in lean mode. It is core database functionality, not an optional extra, and ships a musl prebuild for Alpine.

Lean mode omits these optional packages:

| Package | Feature affected |
| --- | --- |
| `onnxruntime-node`, `@huggingface/transformers` | Local embeddings / semantic memory |
| `@atjsh/llmlingua-2`, `js-tiktoken` | LLMLingua-2 compression engine |
| `sqlite-vec` | Vector search in the memory store |
| `keytar` | OS keychain storage (not useful in a container) |
| `wreq-js` | TLS impersonation for certain OAuth/web-cookie providers |

The server boots and the dashboard works without them; only the features listed above are unavailable. Build with `--build-arg INSTALL_OPTIONAL_DEPS=true` to restore them.

Translated documentation is removed separately by `REMOVE_TRANSLATED_DOCS=true` (the default). To keep every locale, rebuild with `--build-arg REMOVE_TRANSLATED_DOCS=false`.

## Docker Compose

```yaml
services:
  omniroute:
    build:
      context: .
      args:
        OMNIROUTE_VERSION: latest
        INSTALL_OPTIONAL_DEPS: "false"
        REMOVE_TRANSLATED_DOCS: "true"
    image: omniroute-docker
    container_name: omniroute
    restart: unless-stopped
    ports:
      - "20128:20128"
      - "20129:20129"
    environment:
      INITIAL_PASSWORD: change-this-password
      REQUIRE_API_KEY: "true"
      NVIDIA_API_KEY: ${NVIDIA_API_KEY}
      # Add the other provider connections in the dashboard or with the CLI.
      TZ: America/Sao_Paulo
    volumes:
      - omniroute-data:/home/node/.omniroute

volumes:
  omniroute-data:
```

## Run an agent through NVIDIA OpenShell

[NVIDIA OpenShell](https://docs.nvidia.com/openshell/) can run an agent in a sandbox while OmniRoute supplies every model provider behind one OpenAI-compatible endpoint:

```text
OpenShell sandbox (OpenCode, curl, ...)
        │  OMNIROUTE_API_KEY (placeholder)
        ▼
OmniRoute :20128/v1
        │  real provider keys (never enter the sandbox)
        ▼
OpenAI, Anthropic, NVIDIA NIM, Gemini, OpenRouter, ...
```

Only an OmniRoute credential enters the sandbox, and OpenShell replaces it with an opaque placeholder. The real OmniRoute key and the upstream `*_API_KEY` values stay outside the sandbox: upstream keys are provided through OmniRoute's system environment (`NVIDIA_API_KEY`, `DEEPSEEK_API_KEY`, `GEMINI_API_KEY`/`GOOGLE_API_KEY`, `JINA_AI_API_KEY`/`JINA_API_KEY`), so the agent cannot read them and you do not need a separate OpenShell profile for every provider.

### Start OmniRoute for OpenShell

Publish the API port so the sandbox can reach it, and require an OmniRoute key:

```bash
docker run -d \
  --name omniroute \
  --restart unless-stopped \
  -p 20128:20128 \
  -e INITIAL_PASSWORD='change-this-password' \
  -e REQUIRE_API_KEY='true' \
  -v omniroute-data:/home/node/.omniroute \
  omniroute-docker
```

Open <http://localhost:20128>, log in, and create an API key under **Endpoints**. Export it for OpenShell; this is the key the sandbox will use, not an upstream provider key:

```bash
export OMNIROUTE_API_KEY='omni-...'
```

Destination provider keys must already be present in OmniRoute's system environment (see [Provider credentials](#provider-credentials)) before starting the container; they are read at startup and are not added afterward through the dashboard or CLI.

### Create the OpenShell provider profile

Use the profile at `openshell/omniroute.yaml`. The endpoint host must be the address the sandbox uses to reach OmniRoute. `host.openshell.internal` is the documented host gateway for a service running on the OpenShell host; if OmniRoute runs elsewhere (or on another container network), replace `host.openshell.internal` with that reachable hostname or IP.

The profile enforces strict credential-to-endpoint binding:

- **Sandbox sees only `OMNIROUTE_API_KEY`.** This is an opaque placeholder for OmniRoute itself. Upstream `{PROVIDER}_API_KEY` values (`NVIDIA_API_KEY`, `DEEPSEEK_API_KEY`, `GEMINI_API_KEY`/`GOOGLE_API_KEY`, `JINA_AI_API_KEY`/`JINA_API_KEY`, and any other `*_API_KEY`) are declared exclusively in OmniRoute's system environment at container startup -- they never enter the sandbox.
- **Each provider key is used only by OmniRoute for its intended endpoint.** OmniRoute reads `{PROVIDER}_API_KEY` on the host and routes to the correct provider (for example `OPENROUTER_API_KEY` → `openrouter.ai`). The sandbox cannot call `openrouter.ai`, `api.openai.com`, or any other provider endpoint directly, so a provider key cannot be exfiltrated or used against the wrong endpoint.
- **`path: /v1/**`** limits the sandbox to OmniRoute's OpenAI-compatible API; the dashboard and any other host are unreachable.
- **`enforcement: enforce`** blocks any request outside the allowed endpoint.
- **`binaries` allowlist** restricts which processes may use the endpoint to `opencode`, `node`, and `curl`.

```yaml
id: omniroute
display_name: OmniRoute
description: Self-hosted OmniRoute OpenAI-compatible gateway with system-env provider keys
category: inference
inference_capable: true

credentials:
  - name: api_key
    description: OmniRoute API key (sandbox-facing, opaque placeholder)
    env_vars: [OMNIROUTE_API_KEY]
    required: true
    auth_style: bearer
    header_name: authorization

discovery:
  credentials: [api_key]

endpoints:
  - host: host.openshell.internal
    port: 20128
    path: /v1/**
    protocol: rest
    access: read-write
    enforcement: enforce

binaries:
  - /usr/local/bin/opencode
  - /usr/local/bin/node
  - /usr/bin/curl
  - /usr/local/bin/curl
```

`binaries` is the allowlist of processes that may use this endpoint; remove entries your image does not have. `path: /v1/**` limits the sandbox to the OpenAI-compatible API, not the dashboard.

Lint, import, and create the provider. `--from-existing` reads `OMNIROUTE_API_KEY` from your shell and stores it in OpenShell; the sandbox receives only an opaque placeholder.

```bash
openshell profile lint -f omniroute.yaml
openshell profile import -f omniroute.yaml
openshell provider create --name omniroute --type omniroute --from-existing
```

### Smoke-test from a sandbox

```bash
openshell sandbox create \
  --name omniroute-smoke \
  --from docker.io/curlimages/curl:latest \
  --provider omniroute \
  --env OPENAI_BASE_URL=http://host.openshell.internal:20128/v1 \
  -- sh -c 'curl -fsS "$OPENAI_BASE_URL/chat/completions" \
    -H "Authorization: Bearer $OMNIROUTE_API_KEY" \
    -H "Content-Type: application/json" \
    -d "{\"model\":\"auto\",\"messages\":[{\"role\":\"user\",\"content\":\"Reply with OK\"}]}"'
```

A JSON completion means the sandbox reached OmniRoute, OpenShell substituted the real OmniRoute key, and OmniRoute routed to one of the connected providers.

### Two-sandbox architecture with two exclusive OpenShell providers

Use two dedicated OpenShell providers, one per sandbox:

| Sandbox | Provider | Purpose |
|---------|----------|---------|
| OmniRoute sandbox | `omniroute-all-providers` | Runs `omniroute --daemon` inside the sandbox. Holds all `{PROVIDER}_API_KEY` values and proxies agent requests to the correct provider endpoint. |
| Agent sandbox (OpenCode, curl) | `omniroute-agent` | Runs the agent. Holds only `OMNIROUTE_API_KEY`. Can reach **only** the OmniRoute gateway endpoint; no provider keys and no direct provider-endpoint access. |

This keeps the agent sandbox free of all provider keys and prevents any credential from being used against the wrong endpoint.

#### 1. OmniRoute sandbox — `omniroute-all-providers` provider

This sandbox runs the OmniRoute daemon. It binds every `{PROVIDER}_API_KEY` to its respective provider endpoint so each key is used only for its intended provider:

```bash
openshell profile lint -f openshell/omniroute-all-providers.yaml
openshell profile import -f openshell/omniroute-all-providers.yaml
openshell provider create --name omniroute-all-providers --type omniroute-all-providers --from-existing
```

```bash
openshell sandbox create \
  --name omniroute \
  --from local/omniroute \
  --provider omniroute-all-providers \
  -- omniroute --daemon
```

The `omniroute-all-providers` profile enforces:
- **OmniRoute gateway endpoint** (`host.openshell.internal:20128/v1`) reachable via `OMNIROUTE_API_KEY`.
- **Each `{PROVIDER}_API_KEY` bound to its own endpoint.** `OPENROUTER_API_KEY` only reaches `openrouter.ai`, `NVIDIA_API_KEY` only NVIDIA endpoints, etc. (`enforcement: enforce`). OmniRoute, as the trusted proxy daemon in this sandbox, holds these keys and routes each request to the correct provider.
- **`binaries` allowlist** restricts this sandbox to the `omniroute` proxy binary and `node`.

#### 2. Agent sandbox — `omniroute-agent` provider

This sandbox runs the agent (OpenCode, curl, ...). It holds **only** `OMNIROUTE_API_KEY` and can reach **only** the OmniRoute gateway endpoint. No provider keys enter this sandbox, and the agent cannot call any provider endpoint directly:

```bash
openshell profile lint -f openshell/omniroute-agent.yaml
openshell profile import -f openshell/omniroute-agent.yaml
openshell provider create --name omniroute-agent --type omniroute-agent --from-existing
```

```bash
openshell sandbox create \
  --name omniroute-agent \
  --from ghcr.io/anomalyco/opencode:latest \
  --provider omniroute-agent \
  --env OMNIROUTE_API_KEY="${OMNIROUTE_API_KEY}" \
  --env OPENAI_BASE_URL=http://host.openshell.internal:20128/v1 \
  --detach \
  -- sh -c 'sleep 86400'
```

The `omniroute-agent` profile enforces:
- **Sandbox agent sees only `OMNIROUTE_API_KEY`.** Upstream `{PROVIDER}_API_KEY` values never enter this sandbox.
- **`path: /v1/**`** limits the agent to OmniRoute's OpenAI-compatible API; every other host (including all provider endpoints) is unreachable from the agent.
- **`enforcement: enforce`** blocks any request outside the allowed endpoint.
- **`binaries` allowlist** restricts agent binaries (`opencode`, `node`, `curl`) to the OmniRoute gateway endpoint.

#### Profile files

The two profiles live in `openshell/`:

- `openshell/omniroute-all-providers.yaml` — for the OmniRoute daemon sandbox.
- `openshell/omniroute-agent.yaml` — for the agent sandbox.

Each provider is exclusive to its sandbox; never share a provider between the omniroute sandbox and the agent sandbox.

### Run OpenCode through OmniRoute

Save this OpenCode config as `opencode.json`:

```json
{
  "$schema": "https://opencode.ai/config.json",
  "providers": {
    "omniroute": {
      "name": "OmniRoute",
      "env": ["OMNIROUTE_API_KEY"],
      "package": "@opencode/ai/providers/openai-compatible",
      "settings": {
        "baseURL": "http://host.openshell.internal:20128/v1"
      },
      "models": {
        "auto": { "name": "OmniRoute auto" }
      }
    }
  }
}
```

Create a detached sandbox from the OpenCode image, upload the config, and start the agent:

```bash
openshell sandbox create \
  --name omniroute-agent \
  --from ghcr.io/anomalyco/opencode:latest \
  --provider omniroute \
  --upload ./opencode.json:/workspace/opencode.json \
  --no-git-ignore \
  --detach

openshell sandbox exec -n omniroute-agent --workdir /workspace -- \
  opencode run --model omniroute/auto "Summarize the files in this workspace."
```

OpenCode reads `OMNIROUTE_API_KEY` from the sandbox environment, sends it to `host.openshell.internal:20128/v1`, and OmniRoute chooses a provider for the `auto` model. For an interactive session in OpenCode 2.x, use `opencode mini --model omniroute/auto`. To pin a destination, use a model ID that OmniRoute exposes, for example `omniroute/nvidia/<model-id>` as listed by `opencode models` or the OmniRoute dashboard.

If the detached login shell exits immediately on your gateway, create the sandbox with a keepalive instead, then upload the config:

```bash
openshell sandbox create \
  --name omniroute-agent \
  --from ghcr.io/anomalyco/opencode:latest \
  --provider omniroute \
  --detach \
  -- sh -c 'sleep 86400'

openshell sandbox upload omniroute-agent ./opencode.json /workspace/opencode.json --no-git-ignore
openshell sandbox exec -n omniroute-agent --workdir /workspace -- \
  opencode run --model omniroute/auto "Summarize the files in this workspace."
```

To clean up:

```bash
openshell sandbox delete omniroute-smoke omniroute-agent
```

### Credential security

The sandbox agent never holds upstream provider keys. It only sees `OMNIROUTE_API_KEY` (an opaque placeholder managed by OpenShell) and reaches OmniRoute at `host.openshell.internal:20128/v1`. Upstream provider keys come through OmniRoute's system environment at startup (`NVIDIA_API_KEY`, `DEEPSEEK_API_KEY`, `GEMINI_API_KEY`/`GOOGLE_API_KEY`, `JINA_AI_API_KEY`/`JINA_API_KEY`) and are never stored in OmniRoute's database for this flow. Even if the sandbox is compromised, the attacker cannot extract upstream API keys.

### OpenShell troubleshooting

| Symptom | Fix |
| --- | --- |
| `credential_endpoint_mismatch` | The profile's `endpoints` host, port, or path does not match the URL the agent calls. `host.openshell.internal` is not `localhost`; use the exact host declared in the profile. |
| Connection refused or timeout to `host.openshell.internal:20128` | OmniRoute is not reachable from the sandbox. Confirm the port is published, the host address is correct for your gateway (host-local, Docker network, or LAN), and the profile declares that host. |
| `403` or policy denial | Check `openshell policy get <sandbox> --full`; the provider must be attached and its `binaries` must include the calling executable (for example `/usr/local/bin/opencode` or `/usr/bin/curl`). |
| `401` from OmniRoute | The OmniRoute key is wrong, or `REQUIRE_API_KEY` is enabled without a valid key. Export the correct `OMNIROUTE_API_KEY` and recreate the provider with `--from-existing`. |
| `429` or upstream provider errors | The selected provider failed or has no key. Check OmniRoute's logs and confirm the provider key is set in OmniRoute's system environment at startup (see [Provider credentials](#provider-credentials)). |

> **Why not add every upstream provider to OpenShell?** The sandbox does not call the upstream APIs; it calls OmniRoute. Adding `api.openai.com`, `api.anthropic.com`, and the rest to the sandbox policy would expose their credentials to the agent and bypass OmniRoute's routing, retries, and accounting. Keep one OpenShell provider for OmniRoute and declare upstream keys through OmniRoute's system environment at startup.

## Persistence

Mount a volume at `/home/node/.omniroute` (or set `DATA_DIR` to another mounted path). That directory holds `storage.sqlite`, the generated secrets in `.env`, database backups, and installed plugins. Without a volume, all configuration is lost when the container is removed.

The image pre-creates `/home/node/.omniroute` with `node:node` ownership, so a named volume mounted there inherits the correct permissions. If you use a bind mount instead, make sure the host directory is writable by UID/GID `1000` (`node`):

```bash
mkdir -p ./omniroute-data
sudo chown -R 1000:1000 ./omniroute-data
```

On rootless Podman, the container's UID 1000 is mapped to a subordinate host UID, and SELinux may block the mount. Use a named volume, or set the ownership inside Podman's user namespace and relabel the directory:

```bash
podman unshare chown -R 1000:1000 ./omniroute-data
podman run -d --name omniroute \
  -p 20128:20128 \
  -e INITIAL_PASSWORD='change-this-password' \
  -v "$PWD/omniroute-data:/home/node/.omniroute:Z" \
  omniroute-docker
```

The `:Z` suffix relabels the directory for exclusive container access. Use `:z` instead if several containers need to share it.

## What the build does

The `Dockerfile` performs the following steps:

1. **Builder stage** — starts from `node:lts-alpine` and installs temporary build tools (`python3`, `make`, `g++`, `linux-headers`) only for the duration of the stage.
2. Installs `omniroute` into `/opt/omniroute` with `--omit=optional` by default. A local (non-global) install is used because npm ignores `--omit=optional` for `npm install -g`.
3. Re-adds `better-sqlite3` at the version OmniRoute declares, so the image keeps the native SQLite driver in lean mode.
4. Runs the CLI version check and `omniroute providers validate` as a build-time smoke check. These run in the builder and do not leave state in the final image.
5. Removes the non-English documentation tree (`dist/docs/i18n`) in the builder before the runtime copy, unless `REMOVE_TRANSLATED_DOCS=false`. English docs are compiled into the Next.js app, so `/docs` continues to work and other locales fall back to English.
6. **Runtime stage** — starts a fresh `node:lts-alpine`, installs only `ca-certificates`, `curl`, `libc6-compat`, and `tzdata`, then copies `/opt/omniroute` from the builder.
7. Creates the `omniroute` and `omniroute-reset-password` symlinks, prepares `/workspace` and `/home/node/.omniroute` with `node:node` ownership, switches to the non-root `node` user, and declares the ports and entrypoint.
8. With no arguments the entrypoint launches `omniroute serve` (the default command), which starts the dashboard and the `/v1` proxy.

Builds are unpinned by default (`OMNIROUTE_VERSION=latest`). Pin the version with `--build-arg OMNIROUTE_VERSION=<version>` for reproducible deployments.

## Operations

### Logs

```bash
docker logs -f omniroute
```

### Shell

```bash
docker exec -it omniroute sh
```

### Reset the dashboard password

```bash
docker exec -it omniroute omniroute reset-password
```

The new password must be at least 8 characters, and the container must be restarted afterwards. For scripted use:

```bash
printf 'NewPass123\nNewPass123\n' | docker exec -i omniroute omniroute reset-password
```

If you use a custom `DATA_DIR`, pass it so the reset targets the right database:

```bash
docker exec -it -e DATA_DIR=/data omniroute omniroute reset-password
```

### Upgrade

```bash
docker build --no-cache -t omniroute-docker .
docker rm -f omniroute
# re-run the docker run command, keeping the same volume
```

To pin a release while upgrading:

```bash
docker build --no-cache \
  --build-arg OMNIROUTE_VERSION=3.8.53 \
  -t omniroute-docker .
```

Because the database and generated secrets live in the data volume, keeping it means existing API keys and the encryption key survive the upgrade.

### Stop

```bash
docker stop omniroute
```

## Security notes

- **Change `INITIAL_PASSWORD`.** The baked-in `q1w2e3` value is a weak placeholder. Use a strong password (8+ characters) and never expose the dashboard to the internet without TLS and a reverse proxy.
- **The fake provider keys are not credentials.** They are placeholders and will fail against real providers. Supply real keys at runtime via `docker run -e ...` (or an `--env-file`); provider keys must not be stored in OmniRoute's database.
- **Protect `/v1/*`.** OmniRoute is local-first, but this container publishes port `20128` on all interfaces. Set `REQUIRE_API_KEY=true` and create an API key, and/or bind the port to loopback (`-p 127.0.0.1:20128:20128`) so only local clients can spend your provider quota. If you use OpenShell, publish the port on an interface the sandbox can reach and keep `REQUIRE_API_KEY=true`.
- **Keep secrets out of images.** Do not bake real keys into the `Dockerfile` or commit them to a `.env` file. Use runtime environment variables, `--env-file`, or your orchestrator's secret store.
- **The container runs as `node` (UID 1000), not root.** Keep the data volume owned by that UID.

## Troubleshooting

| Symptom | Fix |
| --- | --- |
| Build fails during `npm install` | The build needs outbound network access. Check connectivity/proxy settings and retry. |
| A feature that needs local embeddings, LLMLingua, or `sqlite-vec` is missing | Rebuild with `--build-arg INSTALL_OPTIONAL_DEPS=true`. |
| `EACCES` when writing to the data directory | Use a named volume, or fix the bind mount: `sudo chown -R 1000:1000 ./omniroute-data` (Docker), or `podman unshare chown -R 1000:1000 ./omniroute-data` plus a `:Z` mount suffix (rootless Podman with SELinux). |
| Dashboard unreachable from the host | Confirm the container is running (`docker ps`) and that the port mapping is `-p 20128:20128`. The server binds `0.0.0.0` by default. |
| `INITIAL_PASSWORD` appears ignored | A password is already stored. Reset it with `omniroute reset-password`, or start with a fresh data volume. |
| `401` from `/v1/chat/completions` | Create an OmniRoute API key in the dashboard (**Endpoints**) and send it as `Authorization: Bearer <key>`. If `REQUIRE_API_KEY=true`, a valid key is mandatory. |

## Links

- Upstream project: <https://github.com/diegosouzapw/OmniRoute>
- Website and docs: <https://omniroute.online>
- npm package: <https://www.npmjs.com/package/omniroute>
- Docker Hub (official image): <https://hub.docker.com/r/diegosouzapw/omniroute>
- NVIDIA OpenShell: <https://docs.nvidia.com/openshell/>
- OpenShell provider profiles: <https://docs.nvidia.com/openshell/latest/how-it-works/providers/profiles>
- OpenCode provider configuration: <https://opencode.ai/v2/docs/providers>

## License

The packaging files in this repository are provided as-is. OmniRoute is distributed under the MIT License; see the [upstream license](https://github.com/diegosouzapw/OmniRoute/blob/main/LICENSE).
