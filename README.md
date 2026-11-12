# omniroute-docker

A minimal Alpine-based Docker image for [OmniRoute](https://github.com/cheaper-inference/OmniRoute) — a unified AI gateway that exposes hundreds of providers behind a single OpenAI-compatible endpoint.

The image is built in two stages: a builder stage installs the official [`omniroute`](https://www.npmjs.com/package/omniroute) npm package into a self-contained prefix, and a fresh `node:lts-alpine` runtime stage receives only the installed application. The server runs as the unprivileged `node` user.

| Surface | Address |
| --- | --- |
| Dashboard / API | `http://localhost:20128` |
| OpenAI-compatible base URL | `http://localhost:20128/v1` |
| Live monitoring WebSocket | port `20129` |
| Data directory | `/home/node/.omniroute` |

> This is an unofficial packaging wrapper. OmniRoute itself is MIT-licensed and maintained upstream by [Diego Souza](https://github.com/diegosouzapw).

## Requirements

- Docker (or a compatible runtime such as Podman)
- Outbound network access during the build (to install the `omniroute` npm package)
- For the OpenShell workflow only: the `openshell` CLI, a configured OpenShell gateway with `allow_driver_config = true` for the volume mount (see [Volume mounts and `allow_driver_config`](#volume-mounts-and-allow_driver_config)), `jq`, and the gateway's compute-driver CLI (`docker` or `podman`) for volume management

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
  -e REQUIRE_API_KEY='true' \
  -e NVIDIA_API_KEY="${NVIDIA_API_KEY}" \
  -v omniroute-data:/home/node/.omniroute \
  omniroute-docker omniroute --no-open
```

> **The image deliberately has no `ENTRYPOINT` or `CMD`.** The base `node:lts-alpine` layers still carry their default `node` command, so always append the OmniRoute command (`omniroute --no-open`, or `omniroute serve --headless`) after the image name. Without it the container starts a Node REPL and exits.

Then open <http://localhost:20128> and log in with `INITIAL_PASSWORD`. `INITIAL_PASSWORD` is applied only while no dashboard password is stored; changing it later does not change an existing password (see [Reset the dashboard password](#reset-the-dashboard-password)).

Provider keys are supplied at runtime and are never baked into the image. NVIDIA, DeepSeek, Gemini, and Jina keys are also read directly from the environment as provider fallbacks; see [Provider credentials](#provider-credentials).

The default build is lean: optional native/AI extras are omitted to keep the image small. See [Build options](#build-options) if you need local embeddings, LLMLingua compression, or the other optional engines.

## Use the API

Point any OpenAI-compatible client at the gateway:

```bash
curl http://localhost:20128/v1/chat/completions \
  -H "Authorization: Bearer YOUR_OMNIROUTE_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "auto",
    "messages": [{ "role": "user", "content": "Hello!" }]
  }'
```

Create OmniRoute client keys in the dashboard under **Endpoints**. Use `auto` to let OmniRoute pick among your connected providers, or a variant such as `auto/coding`, `auto/cheap`, or `auto/fast` to bias the selection.

## Provider credentials

Declare upstream provider API keys as runtime environment variables. OmniRoute reads them as provider fallbacks:

| Variable(s) | Provider |
| --- | --- |
| `NVIDIA_API_KEY` | NVIDIA NIM |
| `DEEPSEEK_API_KEY` | DeepSeek |
| `GEMINI_API_KEY`, `GOOGLE_API_KEY` | Google Gemini |
| `JINA_AI_API_KEY`, `JINA_API_KEY` | Jina AI |
| `OPENAI_API_KEY` | OpenAI |
| `ANTHROPIC_API_KEY` | Anthropic |
| `OPENROUTER_API_KEY` | OpenRouter |

Any other provider supported by OmniRoute uses the same pattern: set its standard `{PROVIDER}_API_KEY` at runtime. The full list is in OmniRoute's [environment reference](https://github.com/cheaper-inference/OmniRoute/blob/main/docs/reference/ENVIRONMENT.md).

Pass keys with `-e` or an environment file:

```bash
docker run -d \
  --name omniroute \
  --restart unless-stopped \
  -p 20128:20128 \
  -e INITIAL_PASSWORD='change-this-password' \
  -e REQUIRE_API_KEY='true' \
  --env-file provider.env \
  -v omniroute-data:/home/node/.omniroute \
  omniroute-docker omniroute --no-open
```

`provider.env`:

```dotenv
NVIDIA_API_KEY=nvapi-...
DEEPSEEK_API_KEY=sk-...
GEMINI_API_KEY=...
JINA_AI_API_KEY=...
```

Do not store provider keys in OmniRoute's SQLite database or bake them into the image. In the OpenShell sandbox model, the OmniRoute sandbox has the endpoint-bound provider credentials and the agent sandbox only ever sees `OMNIROUTE_API_KEY` (see [OpenShell sandboxes](#openshell-sandboxes)).

## Configuration

The image is configured through environment variables. Values marked **(image)** are set in the `Dockerfile`; the rest are OmniRoute defaults.

| Variable | Default | Description |
| --- | --- | --- |
| `INITIAL_PASSWORD` | `q1w2e3` **(image)** | Dashboard password applied on first boot. **Override it.** |
| `DATA_DIR` | `/home/node/.omniroute` **(image)** | SQLite database, secrets, backups, and plugins. |
| `NODE_ENV` | `production` **(image)** | Node runtime mode. |
| `PORT` | `20128` | Dashboard and API port. |
| `LIVE_WS_PORT` | `20129` | Live monitoring WebSocket port. |
| `JWT_SECRET` | generated | Signs dashboard session cookies. Generated on first boot and persisted in `$DATA_DIR/server.env`; set it explicitly if the data directory is ephemeral. |
| `API_KEY_SECRET` | generated | Encrypts stored API keys at rest. Generated on first boot and persisted in `$DATA_DIR/server.env`; set it explicitly if the data directory is ephemeral. |
| `STORAGE_ENCRYPTION_KEY` | unset | Optional full-database encryption key. Back it up: losing it means losing the data. |
| `REQUIRE_API_KEY` | `false` | Set to `true` to require an OmniRoute key on `/v1/*`. Strongly recommended when publishing the port. |
| `OMNIROUTE_SERVER_HOST` | `0.0.0.0` | Bind address. Use `127.0.0.1` to keep the server loopback-only. |
| `OMNIROUTE_HEADLESS` | unset | Set to `1` to run only the API/proxy and disable the dashboard. Equivalent to `omniroute serve --headless`. |
| `TZ` | unset | Container timezone; `tzdata` is installed. |

A feature flag saved in the dashboard takes precedence over the `REQUIRE_API_KEY` environment variable. If the environment value appears ignored, check the saved setting.

## Build options

| Argument | Default | Description |
| --- | --- | --- |
| `OMNIROUTE_VERSION` | `latest` | npm version or tag to install. Pin it for reproducible deployments, e.g. `3.8.54`. |
| `INSTALL_OPTIONAL_DEPS` | `false` | Install OmniRoute's optional dependencies (about 1 GB extra). Set to `true` for the full feature set. |
| `REMOVE_TRANSLATED_DOCS` | `true` | Remove the non-English documentation tree. English docs stay built in; other locales fall back to English. |

```bash
# Reproducible, lean build
docker build \
  --build-arg OMNIROUTE_VERSION=3.8.54 \
  -t omniroute-docker .

# Full feature build (local ONNX embeddings, LLMLingua, sqlite-vec, ...)
docker build \
  --build-arg INSTALL_OPTIONAL_DEPS=true \
  -t omniroute-docker:full .

# Keep all translated documentation
docker build \
  --build-arg REMOVE_TRANSLATED_DOCS=false \
  -t omniroute-docker:translated .

# Tag used by run-omniroute.sh
docker build -t localhost/fibonsai/omniroute:latest .
```

## Image size and optional dependencies

The largest wins come from installing into a disposable build stage and omitting optional dependencies:

- The runtime image contains only the installed application tree. The builder's `python3`/`make`/`g++` toolchain and the npm download cache stay in the disposable stage.
- The lean install tree is about 2.0 GB. `INSTALL_OPTIONAL_DEPS=true` adds roughly 1 GB of native and AI packages.
- Measured with OmniRoute 3.8.53, the original single-stage `npm install -g` image was **4.51 GB**; this multi-stage lean build was **2.00 GB**, about **56% smaller**.
- Removing `dist/docs/i18n` takes OmniRoute's `dist` tree from about 969 MB to about 588 MB. English docs are compiled into the app, so `/docs` still works and other locales fall back to English.
- The native SQLite driver (`better-sqlite3`) is kept in lean mode: it is core database functionality, not an optional extra, and ships a musl prebuild for Alpine.

Lean mode omits these optional packages:

| Package | Feature affected |
| --- | --- |
| `onnxruntime-node`, `@huggingface/transformers` | Local embeddings / semantic memory |
| `@atjsh/llmlingua-2`, `js-tiktoken` | LLMLingua-2 compression engine |
| `sqlite-vec` | Vector search in the memory store |
| `keytar` | OS keychain storage (not useful in a container) |
| `wreq-js` | TLS impersonation for certain OAuth/web-cookie providers |

The server boots and the dashboard works without them; only the listed features are unavailable. Rebuild with `--build-arg INSTALL_OPTIONAL_DEPS=true` to restore them.

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
    command: ["omniroute", "--no-open"]
    ports:
      - "20128:20128"
      - "20129:20129"
    environment:
      INITIAL_PASSWORD: change-this-password
      REQUIRE_API_KEY: "true"
      NVIDIA_API_KEY: ${NVIDIA_API_KEY}
      TZ: America/Sao_Paulo
    volumes:
      - omniroute-data:/home/node/.omniroute

volumes:
  omniroute-data:
```

`command` is required because the image defines no entrypoint.

## OpenShell sandboxes

[NVIDIA OpenShell](https://docs.nvidia.com/openshell/) can run OmniRoute and the agents that use it in separate sandboxes. The agent holds only an OmniRoute key; the OmniRoute sandbox is the only one with upstream provider credentials attached, and each credential is bound to its own provider endpoint.

```text
 Agent sandbox                              OmniRoute sandbox
 (OpenCode, Claude Code, HermesClaw)        (omniroute --no-open --log --no-recovery)
 ───────────────────────────────────        ─────────────────────────────────
 OMNIROUTE_API_KEY only          ─────────▶ :20128/v1
 (opaque placeholder)                       provider credentials bound to their endpoints
                                                    │
                                                    ▼
                                        OpenAI, Anthropic, NVIDIA NIM, Gemini,
                                        OpenRouter, Groq, ...
```

| Sandbox | Provider profile | Credentials | Purpose |
| --- | --- | --- | --- |
| `omniroute` | `inference-providers` | Endpoint-bound `{PROVIDER}_API_KEY` credentials | Runs the OmniRoute daemon and forwards requests to the correct provider endpoint. |
| Agent (OpenCode, Claude Code, HermesClaw, curl) | `omniroute-agent` | Only `OMNIROUTE_API_KEY` | Runs the agent. Can reach only OmniRoute's `/v1/**`; no provider credentials and no direct provider access. |

Never attach the `inference-providers` provider to an agent sandbox, and never attach `omniroute-agent` to the OmniRoute sandbox.

### Start the OmniRoute sandbox

The repository includes `run-omniroute.sh`, which automates the server-side sandbox: build the image, export the keys, and run the script from the repository root.

Requirements:

- The image must exist as `localhost/fibonsai/omniroute:latest`. If you use another tag, update `OMNIROUTE_IMAGE` at the top of the script.
- `openshell` must be configured, and `~/.config/openshell/gateway.toml` must declare `compute_driver` (for example `"docker"` or `"podman"`). The script uses that driver to manage the `omniroute-data` volume.
- The same gateway config must allow caller-supplied driver config for the volume mount; see [Volume mounts and `allow_driver_config`](#volume-mounts-and-allow_driver_config).
- `jq` is required to read the published service URL.

```bash
# 1. Build the image with the tag expected by the script
docker build -t localhost/fibonsai/omniroute:latest .

# 2. Export the dashboard password and the upstream provider keys for the profile
export INITIAL_PASSWORD='change-this-password'
export NVIDIA_API_KEY='nvapi-...'
export OPENROUTER_API_KEY='...'
# ...any other {PROVIDER}_API_KEY values

# 3. Create the provider, volume, and sandbox
./run-omniroute.sh
```

The script writes the generated OmniRoute API key to `.env` in the repository root and prints the local service URL:

```text
[run-openshell] Updating dashboard password
[run-openshell] Reset all old keys
[run-openshell] OmniRoute sandbox 'omniroute' is up using profile inference-providers.
[run-openshell] OmniRoute OMNIROUTE_API_KEY is saved in '.env' file (always refreshed when reexecuting this script)
[run-openshell] Local access: https://.../v1
```

Load the key for the agent steps:

```bash
export OMNIROUTE_API_KEY="$(sed -n 's/^OMNIROUTE_API_KEY=//p' .env)"
```

An agent outside OpenShell uses the printed `Local access` origin, or resolves the same URL with the `openshell service` command in [Agent connection addresses](#agent-connection-addresses). Append `/v1` for OpenAI-compatible clients; Claude Code uses the origin without `/v1`.

What the script does:

1. Deletes an existing sandbox named `omniroute` (the `omniroute-data` volume is kept) and waits 5 seconds before recreating it.
2. Deletes and recreates the `inference-providers` provider and profile from `openshell/inference-providers.yaml`, then lints and imports the profile.
3. Ensures the `omniroute-data` volume exists, labeled as attachable to the default workspace.
4. Creates the `omniroute` sandbox from `localhost/fibonsai/omniroute:latest`, attaches the provider and `openshell/policy.yaml`, exposes port `20128`, mounts the volume at `/home/node/.omniroute`, and starts `omniroute --no-open --log --no-recovery`.
5. Polls `http://127.0.0.1:20128/login` until the server is reachable, then updates the dashboard password with `omniroute setup --non-interactive --password "$INITIAL_PASSWORD"`.
6. Unless `RESET_ALL_KEYS=false`, deletes every existing OmniRoute API key, creates a new key named `default`, and writes it to `.env`. It then prints the service URL.

Notes:

- `INITIAL_PASSWORD` defaults to `password` in the script. Always override it. Because the script runs `omniroute setup` on every invocation, it also resets the stored dashboard password on every run.
- The gateway must permit the volume mount: set `allow_driver_config = true` under `[openshell.drivers.<driver>]` in `~/.config/openshell/gateway.toml` and restart the gateway. Without it, the sandbox rejects the `--driver-config-json` mount. See [Volume mounts and `allow_driver_config`](#volume-mounts-and-allow_driver_config).
- The sandbox and provider are recreated on every run; the named volume is reused, so the database and generated secrets survive. Other sandboxes using the same provider are affected when it is recreated.
- `RESET_ALL_KEYS` defaults to `true`: each run revokes every existing API key, so keys already exported to agents stop working. Set `RESET_ALL_KEYS=false` to keep existing keys and only add the new `default` key.
- The script overwrites `.env` on every run with the latest `default` key. `.env` holds a plain-text secret: keep it out of version control and restrict its permissions.
- Only variables declared by the profile can be bound. Export the ones you want to enable; OpenShell resolves them only for requests to the matching provider endpoint, so processes in the sandbox see placeholders rather than raw keys. The profile pre-declares: `OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, `GEMINI_API_KEY`/`GOOGLE_API_KEY`, `DEEPSEEK_API_KEY`, `NVIDIA_API_KEY`, `OPENROUTER_API_KEY`, `GROQ_API_KEY`, `MISTRAL_API_KEY`, `XAI_API_KEY`, `TOGETHER_API_KEY`, `FIREWORKS_API_KEY`, `COHERE_API_KEY`, `PERPLEXITY_API_KEY`, `CEREBRAS_API_KEY`, `DEEPINFRA_API_KEY`, `SILICONFLOW_API_KEY`, `NOVITA_API_KEY`, and `JINA_AI_API_KEY`. All are optional; omit a key to leave that provider unrouted.

#### Volume mounts and `allow_driver_config`

`run-omniroute.sh` mounts the `omniroute-data` volume with `--driver-config-json`. OpenShell disables caller-supplied driver config by default, so the gateway must opt in. Add this under the driver table selected by `compute_driver` in `~/.config/openshell/gateway.toml`:

```toml
[openshell.drivers.podman]   # or [openshell.drivers.docker]
allow_driver_config = true
```

Restart the gateway after changing the file. Without this setting, the sandbox rejects the mount and OmniRoute cannot persist its data directory. The script labels the volume `openshell.ai/sandbox-attachable=true` and `openshell.ai/sandbox-attachable-workspace=default`, so the default resource admission still applies.

### What the profiles enforce

`openshell/inference-providers.yaml` (OmniRoute sandbox):

- **Provider credentials are endpoint-bound.** Each declared `{PROVIDER}_API_KEY` is exposed to the sandbox as a placeholder and resolved by OpenShell only when a request targets the matching provider endpoint. Raw values are never readable inside the sandbox.
- **One key, one endpoint.** Provider endpoints use `enforcement: enforce`, so `OPENROUTER_API_KEY` only reaches `openrouter.ai`, `NVIDIA_API_KEY` only NVIDIA endpoints, and so on.
- **Gateway endpoints.** The profile declares `host.openshell.internal:20128` and `host.docker.internal:20128` for `GET /login` and `GET /v1/**`.
- **Binary allowlist.** Only `/usr/local/bin/omniroute`, `/usr/local/bin/node`, and `/usr/bin/curl` may use these endpoints.

`openshell/omniroute-agent.yaml` (agent sandbox):

- **Sandbox sees only `OMNIROUTE_API_KEY`.** The key is a placeholder resolved by OpenShell; upstream provider keys never enter this sandbox.
- **One reachable endpoint.** `host.openshell.internal:20128` with `path: /v1/**` and `enforcement: enforce`. The bundled profile allows only this host; on a Podman-backed gateway, change it to `host.docker.internal` as described in [Agent connection addresses](#agent-connection-addresses). The dashboard and every provider endpoint are unreachable.
- **Binary allowlist.** `/usr/local/bin/opencode`, `/usr/local/bin/node`, `/home/claude/.local/bin/claude`, `/usr/bin/curl`, and `/usr/local/bin/curl` may use the endpoint.

### Sandbox policy

`openshell/policy.yaml` applies to the OmniRoute sandbox:

| Setting | Values |
| --- | --- |
| Work directory | Included and writable |
| Read-only | `/bin`, `/usr`, `/lib`, `/proc`, `/dev/urandom`, `/etc`, `/var/log`, `/opt` |
| Read-write | `/tmp`, `/dev/null`, `/home/node/.omniroute` |
| Landlock | `best_effort` |

Only the data volume is writable for persistent state; the OmniRoute installation under `/opt` cannot be modified.

### Connect an agent sandbox

Create the agent provider from the exported OmniRoute key, then start the agent sandbox:

```bash
export OMNIROUTE_API_KEY="$(sed -n 's/^OMNIROUTE_API_KEY=//p' .env)"   # written by run-omniroute.sh

openshell profile lint -f openshell/omniroute-agent.yaml
openshell profile import -f openshell/omniroute-agent.yaml
openshell provider create --name omniroute-agent --type omniroute-agent --from-existing
```

If the profile or provider already exists, delete it first (`openshell provider delete omniroute-agent`, `openshell profile delete omniroute-agent`) so the new key is picked up.

#### Agent connection addresses

Use the address that matches where the agent runs:

| Agent location | OmniRoute origin | OpenAI-compatible base URL |
| --- | --- | --- |
| OpenShell sandbox, Docker-backed gateway | `http://host.openshell.internal:20128` | `http://host.openshell.internal:20128/v1` |
| OpenShell sandbox, Podman-backed gateway | `http://host.docker.internal:20128` | `http://host.docker.internal:20128/v1` |
| Outside OpenShell (host, LAN, or another machine) | URL from `openshell service list` | `<service-url>/v1` |

On Podman, OpenShell injects `host.docker.internal` into the sandbox's `/etc/hosts` but **not** `host.openshell.internal`. On Docker, `host.openshell.internal` is the gateway alias. If you are unsure, inspect the sandbox:

```bash
openshell sandbox exec -n <sandbox> -- cat /etc/hosts
```

The bundled `openshell/omniroute-agent.yaml` declares only `host.openshell.internal`. On a Podman-backed gateway, either change that profile's endpoint `host` to `host.docker.internal` and re-import it, or run the agent outside OpenShell and use the service URL.

An agent outside OpenShell must resolve the published service URL instead of hardcoding a sandbox address:

```bash
export OMNIROUTE_ORIGIN="$(openshell service list -o json \
  | jq -r '.services[] | select(.sandbox == "omniroute") | .url')"
export OMNIROUTE_BASE_URL="${OMNIROUTE_ORIGIN}/v1"
```

An external agent then calls that URL directly with `OMNIROUTE_API_KEY`; it does not use `openshell sandbox create`.

For an agent inside OpenShell, set the origin for the gateway driver instead:

```bash
# Docker-backed gateway
export OMNIROUTE_ORIGIN=http://host.openshell.internal:20128

# Podman-backed gateway
export OMNIROUTE_ORIGIN=http://host.docker.internal:20128

export OMNIROUTE_BASE_URL="${OMNIROUTE_ORIGIN}/v1"
```

OpenAI-compatible clients (curl, OpenCode, HermesClaw) use `OMNIROUTE_BASE_URL`; Claude Code uses `OMNIROUTE_ORIGIN` without `/v1`. The sandbox examples below pass these values in with `--env`.

Smoke-test with curl:

```bash
openshell sandbox create \
  --name omniroute-smoke \
  --from docker.io/curlimages/curl:latest \
  --provider omniroute-agent \
  --env OPENAI_BASE_URL="$OMNIROUTE_BASE_URL" \
  -- sh -c 'curl -fsS "$OPENAI_BASE_URL/chat/completions" \
    -H "Authorization: Bearer $OMNIROUTE_API_KEY" \
    -H "Content-Type: application/json" \
    -d "{\"model\":\"auto\",\"messages\":[{\"role\":\"user\",\"content\":\"Reply with OK\"}]}"'
```

A JSON completion means the sandbox reached OmniRoute, OpenShell substituted the real OmniRoute key, and OmniRoute routed to a connected provider.

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
        "baseURL": "{env:OMNIROUTE_BASE_URL}"
      },
      "models": {
        "auto": { "name": "OmniRoute auto" }
      }
    }
  }
}
```

Upload it and start the agent:

```bash
openshell sandbox create \
  --name omniroute-agent \
  --from ghcr.io/anomalyco/opencode:latest \
  --provider omniroute-agent \
  --env OMNIROUTE_BASE_URL="$OMNIROUTE_BASE_URL" \
  --upload ./opencode.json:/workspace/opencode.json \
  --no-git-ignore \
  --detach

openshell sandbox exec -n omniroute-agent --workdir /workspace -- \
  opencode run --model omniroute/auto "Summarize the files in this workspace."
```

OpenCode reads `OMNIROUTE_API_KEY` and `OMNIROUTE_BASE_URL` from the sandbox environment, sends requests to that address, and OmniRoute chooses a provider for `auto`. For an interactive session, use `opencode mini --model omniroute/auto`. To pin a provider, use a model ID that OmniRoute exposes, for example `omniroute/nvidia/<model-id>`.

If the detached login shell exits immediately on your gateway, create the sandbox with a keepalive and upload the config afterwards:

```bash
openshell sandbox create \
  --name omniroute-agent \
  --from ghcr.io/anomalyco/opencode:latest \
  --provider omniroute-agent \
  --env OMNIROUTE_BASE_URL="$OMNIROUTE_BASE_URL" \
  --detach \
  -- sh -c 'sleep 86400'

openshell sandbox upload omniroute-agent ./opencode.json /workspace/opencode.json --no-git-ignore
openshell sandbox exec -n omniroute-agent --workdir /workspace -- \
  opencode run --model omniroute/auto "Summarize the files in this workspace."
```

### Run Claude Code through OmniRoute

Anthropic does not publish a publicly pullable `claude-code` image (it is distributed as an authenticated dev-container feature on `ghcr.io/anthropics`), so build your own image with the Claude Code CLI and use it as `<your-claude-code-image>`.

Claude Code expects the Anthropic gateway root, **without** `/v1`. Set `OMNIROUTE_ORIGIN` to the in-sandbox origin from [Agent connection addresses](#agent-connection-addresses):

```bash
openshell sandbox create \
  --name claude-code-agent \
  --from <your-claude-code-image> \
  --provider omniroute-agent \
  --env OMNIROUTE_API_KEY="${OMNIROUTE_API_KEY}" \
  --env ANTHROPIC_BASE_URL="${OMNIROUTE_ORIGIN}" \
  --env ANTHROPIC_AUTH_TOKEN="${OMNIROUTE_API_KEY}" \
  --detach \
  -- sh -c 'sleep 86400'

openshell sandbox exec -n claude-code-agent --workdir /workspace -- \
  claude "Summarize the files in this workspace."
```

Claude Code authenticates to OmniRoute with `OMNIROUTE_API_KEY`, and OmniRoute routes to the configured provider. The sandbox never sees `NVIDIA_API_KEY`, `GEMINI_API_KEY`, or any other upstream key.

### Run Hermes through OmniRoute

To run Hermes Agent (NousResearch) inside OpenShell, use [HermesClaw](https://github.com/TheAiSingularity/hermesclaw) instead of building your own Hermes image. It ships an OpenShell-ready image, so you can connect it to the OmniRoute agent provider like any other agent sandbox.

Add `/usr/local/bin/hermes` to `binaries` in `openshell/omniroute-agent.yaml` so Hermes may call OmniRoute, then create the provider and sandbox (delete an existing `omniroute-agent` provider first, as described in [Connect an agent sandbox](#connect-an-agent-sandbox)):

```bash
export OMNIROUTE_API_KEY="$(sed -n 's/^OMNIROUTE_API_KEY=//p' .env)"   # written by run-omniroute.sh

openshell profile lint -f openshell/omniroute-agent.yaml
openshell profile import -f openshell/omniroute-agent.yaml
openshell provider create --name omniroute-agent --type omniroute-agent --from-existing

openshell sandbox create \
  --name hermesclaw-1 \
  --from ghcr.io/theaisingularity/hermesclaw:latest \
  --provider omniroute-agent \
  --env OMNIROUTE_BASE_URL="$OMNIROUTE_BASE_URL" \
  --detach \
  -- sh -c 'sleep 86400'

openshell sandbox exec -n hermesclaw-1 --workdir /sandbox -- \
  sh -c 'hermes config set model.provider custom
         hermes config set model.base_url "$OMNIROUTE_BASE_URL"
         hermes config set model.key_env OMNIROUTE_API_KEY
         hermes chat -q "Summarize the files in this workspace."'
```

Hermes reads `OMNIROUTE_BASE_URL` from the sandbox environment and authenticates with the `OMNIROUTE_API_KEY` placeholder resolved by OpenShell; upstream provider keys never enter the HermesClaw sandbox. See the [HermesClaw README](https://github.com/TheAiSingularity/hermesclaw) for its CLI, policy presets, and Docker mode.

### Clean up

```bash
openshell sandbox delete omniroute-smoke omniroute-agent
# Keep the OmniRoute sandbox if you want to keep serving agents.
```

Deleting the `omniroute` sandbox does not delete the `omniroute-data` volume. Remove it with the gateway's driver when you want to start fresh:

```bash
docker volume rm omniroute-data    # or: podman volume rm omniroute-data
```

## Persistence

Mount a volume at `/home/node/.omniroute` (or set `DATA_DIR` to another mounted path). That directory holds the SQLite database (`omniroute.db`), the generated secrets in `server.env`, database backups, and installed plugins. Without a volume, all configuration is lost when the container is removed.

The image pre-creates `/home/node/.omniroute` with `node:node` ownership, so a named volume mounted there inherits the correct permissions. For a bind mount, make the host directory writable by UID/GID `1000` (`node`):

```bash
mkdir -p ./omniroute-data
sudo chown -R 1000:1000 ./omniroute-data
```

On rootless Podman, the container's UID 1000 maps to a subordinate host UID and SELinux may block the mount. Use a named volume, or set ownership inside Podman's user namespace and relabel the directory:

```bash
podman unshare chown -R 1000:1000 ./omniroute-data
podman run -d --name omniroute \
  -p 20128:20128 \
  -e INITIAL_PASSWORD='change-this-password' \
  -v "$PWD/omniroute-data:/home/node/.omniroute:Z" \
  omniroute-docker omniroute --no-open
```

The `:Z` suffix relabels the directory for exclusive container access; use `:z` if several containers need to share it.

In the OpenShell workflow, `run-omniroute.sh` creates the `omniroute-data` volume and mounts it at the same path. It survives sandbox recreation; delete the volume to reset the installation.

## What the build does

1. **Builder stage** — starts from `node:lts-alpine` and installs temporary build tools (`python3`, `make`, `g++`, `linux-headers`) only for the duration of the stage.
2. Installs `omniroute` into `/opt/omniroute` with `--omit=optional` by default. A local (non-global) install is used because npm ignores `--omit=optional` for `npm install -g`.
3. Re-adds `better-sqlite3` at the version OmniRoute declares, so the image keeps the native SQLite driver in lean mode.
4. Runs the CLI version check and `omniroute providers validate` as a build-time smoke check. These run in the builder and leave no state in the final image.
5. Removes the non-English documentation tree (`dist/docs/i18n`) unless `REMOVE_TRANSLATED_DOCS=false`. English docs are compiled into the Next.js app, so `/docs` continues to work.
6. **Runtime stage** — starts a fresh `node:lts-alpine`, installs only `ca-certificates`, `curl`, `libc6-compat`, `jq`, and `tzdata`, then copies `/opt/omniroute` from the builder.
7. Creates the `omniroute` and `omniroute-reset-password` symlinks, prepares `/workspace` and `/home/node/.omniroute` with `node:node` ownership, and switches to the non-root `node` user.
8. Sets `NODE_ENV`, `DATA_DIR`, and the placeholder `INITIAL_PASSWORD`, then declares ports `20128` and `20129`. It intentionally defines **no `ENTRYPOINT` or `CMD`**, so the container command must be supplied at run time.

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

Inside OpenShell, prefix commands with `openshell sandbox exec -n omniroute --`:

```bash
openshell sandbox exec -n omniroute -- omniroute logs
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

In OpenShell, re-run `./run-omniroute.sh` with the new `INITIAL_PASSWORD`; the script runs `omniroute setup` and resets the admin password.

### Upgrade

```bash
docker build --no-cache -t omniroute-docker .
docker rm -f omniroute
# re-run the docker run command, keeping the same volume
```

To pin a release while upgrading:

```bash
docker build --no-cache \
  --build-arg OMNIROUTE_VERSION=3.8.54 \
  -t omniroute-docker .
```

The database and generated secrets live in the data volume, so keeping it preserves existing API keys and the encryption key. For OpenShell, rebuild `localhost/fibonsai/omniroute:latest` and re-run `./run-omniroute.sh`; the `omniroute-data` volume is reused, but the script creates a new `default` key and rewrites `.env`. With the default `RESET_ALL_KEYS=true`, keys used by running agents are revoked, so update their `OMNIROUTE_API_KEY` after the upgrade (or set `RESET_ALL_KEYS=false`).

### Stop

```bash
docker stop omniroute
```

For OpenShell:

```bash
openshell sandbox delete omniroute
```

## Security notes

- **Change `INITIAL_PASSWORD`.** The image default `q1w2e3` and the script default `password` are weak placeholders. Use a strong password (8+ characters) and never expose the dashboard to the internet without TLS and a reverse proxy.
- **No provider keys are baked in.** Supply them at runtime via `docker run -e ...`, `--env-file`, or OpenShell. Do not store them in OmniRoute's SQLite database.
- **Protect `/v1/*`.** The container publishes port `20128` on all interfaces. Set `REQUIRE_API_KEY=true` and create an API key, and/or bind the port to loopback (`-p 127.0.0.1:20128:20128`). If you use OpenShell, publish the port on an interface the sandbox can reach and keep `REQUIRE_API_KEY=true`.
- **Treat the generated key as a secret.** `run-omniroute.sh` writes the OmniRoute API key to `.env` and stores it in the sandbox database. Keep `.env` out of version control, restrict its permissions, and rotate the key if it leaks.
- **Keep secrets out of images.** Do not bake real keys into the `Dockerfile` or the image. Pass provider keys at runtime with environment variables, `--env-file`, or your orchestrator's secret store. `.env` is generated locally by `run-omniroute.sh` and must not be committed.
- **The container runs as `node` (UID 1000), not root.** Keep the data volume owned by that UID.
- **Provider credentials stay outside the agent sandbox.** They are bound to the `inference-providers` sandbox and resolved only at provider endpoints; the agent only receives an opaque `OMNIROUTE_API_KEY`.

## Troubleshooting

### Docker and runtime

| Symptom | Fix |
| --- | --- |
| Container exits immediately or shows a Node prompt | The image has no entrypoint. Append `omniroute --no-open` (or `omniroute serve --headless`) to `docker run`. |
| Build fails during `npm install` | The build needs outbound network access. Check connectivity/proxy settings and retry. |
| A feature that needs local embeddings, LLMLingua, or `sqlite-vec` is missing | Rebuild with `--build-arg INSTALL_OPTIONAL_DEPS=true`. |
| `EACCES` when writing to the data directory | Use a named volume, or fix the bind mount: `sudo chown -R 1000:1000 ./omniroute-data` (Docker), or `podman unshare chown -R 1000:1000 ./omniroute-data` plus a `:Z` mount suffix (rootless Podman with SELinux). |
| Dashboard unreachable from the host | Confirm the container is running (`docker ps`) and that the port mapping is `-p 20128:20128`. The server binds `0.0.0.0` by default. |
| `INITIAL_PASSWORD` appears ignored | A password is already stored. Reset it with `omniroute reset-password`, or start with a fresh data volume. |
| `401` from `/v1/chat/completions` | Create an OmniRoute API key in the dashboard (**Endpoints**) and send it as `Authorization: Bearer <key>`. If `REQUIRE_API_KEY=true`, a valid key is mandatory. |
| `429` or upstream provider errors | The selected provider failed or has no key. Check OmniRoute's logs and confirm the provider key is set in the container environment at startup. |

### OpenShell

| Symptom | Fix |
| --- | --- |
| `required command not found: openshell` | Install and configure the OpenShell CLI. |
| `jq: command not found` | Install `jq`; the script uses it to read the service URL. |
| `profile not found: .../openshell/inference-providers.yaml` | Run `./run-omniroute.sh` from the repository root. |
| `Driver` is empty or `volume` fails | Ensure `~/.config/openshell/gateway.toml` declares `compute_driver` (`"docker"`/`"podman"`) and that the driver CLI is installed. |
| Sandbox creation fails with a driver-config, mount, or admission error | Add `allow_driver_config = true` under `[openshell.drivers.<driver>]` in `~/.config/openshell/gateway.toml`, restart the gateway, and retry. See [Volume mounts and `allow_driver_config`](#volume-mounts-and-allow_driver_config). |
| Sandbox creation fails with an image error | Build `localhost/fibonsai/omniroute:latest`, or update `OMNIROUTE_IMAGE` in the script to your tag. |
| `OmniRoute did not become reachable` | The daemon failed to start or is still booting. Inspect the sandbox with `openshell sandbox exec -n omniroute -- omniroute logs`, then re-run the script. |
| `OMNIROUTE_API_KEY` is empty or `.env` was not written | `omniroute setup` or the API-key call failed. Check the sandbox logs, confirm the key was not blocked by `RESET_ALL_KEYS`, and re-run; the volume keeps the database between runs. |
| Agent gets `401` from OmniRoute | The exported key no longer matches the sandbox (the default `RESET_ALL_KEYS=true` revokes keys on every run). Load the key written to `.env` by the last script run and recreate the `omniroute-agent` provider with `--from-existing`. |
| Agent gets `403` or a policy denial | Confirm the call uses the host declared by the profile and injected by your driver (`host.openshell.internal` on Docker, `host.docker.internal` on Podman), not `localhost`; the path is under `/v1/**`; and the calling binary is in the agent profile's `binaries` allowlist. |
| Agent cannot resolve `host.openshell.internal` | On Podman, this host is not in `/etc/hosts`; use `host.docker.internal` and update the agent profile's endpoint host. External agents should use the service URL printed by the script or resolved with `openshell service list` instead. |
| `credential_endpoint_mismatch` | The profile endpoint host, port, or path does not match the URL the client calls. Use the exact host declared in the profile (`host.openshell.internal` on Docker, `host.docker.internal` on Podman) or update the profile to match. |

## Links

- Upstream project: <https://github.com/cheaper-inference/OmniRoute>
- Website and docs: <https://omniroute.online>
- npm package: <https://www.npmjs.com/package/omniroute>
- Docker Hub (official image): <https://hub.docker.com/r/diegosouzapw/omniroute>
- NVIDIA OpenShell: <https://docs.nvidia.com/openshell/>
- OpenShell provider profiles: <https://docs.nvidia.com/openshell/latest/how-it-works/providers/profiles>
- OpenCode provider configuration: <https://opencode.ai/v2/docs/providers>

## License

The packaging files in this repository are provided as-is. OmniRoute is distributed under the MIT License; see the [upstream license](https://github.com/cheaper-inference/OmniRoute/blob/main/LICENSE).
