# omniroute-docker

A minimal Alpine-based Docker image for [OmniRoute](https://github.com/diegosouzapw/OmniRoute) — a unified AI gateway that exposes hundreds of providers behind a single OpenAI-compatible endpoint.

This repository contains a single `Dockerfile` that installs the official [`omniroute`](https://www.npmjs.com/package/omniroute) npm package on `node:lts-alpine`, runs the non-interactive setup, and starts the server as the unprivileged `node` user.

- **Dashboard / API:** `http://localhost:20128`
- **OpenAI-compatible base URL:** `http://localhost:20128/v1`
- **Live monitoring WebSocket:** port `20129`
- **Data directory:** `/home/node/.omniroute` (mount a volume here)

> This is an unofficial packaging wrapper. OmniRoute itself is MIT-licensed and maintained upstream by [Diego Souza](https://github.com/diegosouzapw).

## Requirements

- Docker (or a compatible runtime such as Podman)
- Outbound network access during the build (`npm install` plus OmniRoute's provider validation step)

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
  -e OPENROUTER_API_KEY='sk-or-v1-...' \
  -v omniroute-data:/home/node/.omniroute \
  omniroute-docker
```

Then open <http://localhost:20128> and log in with `INITIAL_PASSWORD`.

`INITIAL_PASSWORD` is only applied while no dashboard password is stored. Changing the environment variable after the first boot does **not** change an existing password — use [`omniroute reset-password`](#reset-the-dashboard-password) instead.

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

Create API keys in the dashboard under **Endpoints**, or use the `omniroute keys` CLI. The `auto` model lets OmniRoute pick among your connected providers; `auto/coding`, `auto/cheap`, `auto/fast`, and other variants bias the selection.

Provider credentials can be added either in the dashboard or with the CLI:

```bash
docker exec -it omniroute omniroute setup --add-provider \
  --provider openrouter \
  --api-key "$OPENROUTER_API_KEY" \
  --non-interactive
```

## Configuration

The image is configured entirely through environment variables. The table below lists the values baked into the `Dockerfile` plus the OmniRoute runtime settings that matter most in a container.

| Variable | Default in image | Description |
| --- | --- | --- |
| `INITIAL_PASSWORD` | `q1w2e3` | Dashboard password applied on first boot. **Override it.** |
| `OPENROUTER_API_KEY` | `fake` | Placeholder provider key; override with a real key to use OpenRouter. |
| `OPENCODE_API_KEY` | `fake` | Placeholder provider key. |
| `CLOUDFLARE_API_KEY` | `fake` | Placeholder provider key. |
| `VERCEL_API_KEY` | `fake` | Placeholder provider key. |
| `DEEPINFRA_API_KEY` | `fake` | Placeholder provider key. |
| `SILICONFLOW_API_KEY` | `fake` | Placeholder provider key. |
| `NOVITA_API_KEY` | `fake` | Placeholder provider key. |
| `PORT` | `20128` | Dashboard and API port. |
| `LIVE_WS_PORT` | `20129` | Live monitoring WebSocket port. |
| `DATA_DIR` | `~/.omniroute` (i.e. `/home/node/.omniroute`) | SQLite database, secrets, backups, and plugins. |
| `JWT_SECRET` | auto-generated | Signs dashboard session cookies. Set it explicitly if the data directory is ephemeral. |
| `API_KEY_SECRET` | auto-generated | Encrypts stored API keys at rest. Set it explicitly if the data directory is ephemeral. |
| `STORAGE_ENCRYPTION_KEY` | auto-generated | Optional full-database encryption key. Persisted to `$DATA_DIR/.env`. |
| `REQUIRE_API_KEY` | unset | Set to `true` to require an OmniRoute API key on `/v1/*`. Strongly recommended when publishing the port. |
| `OMNIROUTE_SERVER_HOST` | `0.0.0.0` | Bind address for the server. Use `127.0.0.1` to keep it loopback-only. |

Provider-specific variables for the other supported providers are documented in OmniRoute's [environment reference](https://github.com/diegosouzapw/OmniRoute/blob/main/docs/reference/ENVIRONMENT.md).

The fake keys are intentionally left in the image so that build-time provider validation can run. Pass real values with `docker run -e ...` (or an `--env-file`) at runtime; they override the baked-in defaults.

## Docker Compose

```yaml
services:
  omniroute:
    build: .
    image: omniroute-docker
    container_name: omniroute
    restart: unless-stopped
    ports:
      - "20128:20128"
      - "20129:20129"
    environment:
      INITIAL_PASSWORD: change-this-password
      REQUIRE_API_KEY: "true"
      OPENROUTER_API_KEY: ${OPENROUTER_API_KEY}
      # OPENCODE_API_KEY: ...
      # CLOUDFLARE_API_KEY: ...
      TZ: America/Sao_Paulo
    volumes:
      - omniroute-data:/home/node/.omniroute

volumes:
  omniroute-data:
```

## Persistence

Mount a volume at `/home/node/.omniroute` (or set `DATA_DIR` to another mounted path). That directory holds `storage.sqlite`, the generated secrets in `.env`, database backups, and installed plugins. Without a volume, all configuration is lost when the container is removed.

If you use a bind mount instead of a named volume, make sure it is writable by UID/GID `1000` (`node`):

```bash
mkdir -p ./omniroute-data
sudo chown -R 1000:1000 ./omniroute-data
```

## What the build does

The `Dockerfile` performs the following steps:

1. Starts from `node:lts-alpine` and installs `curl`, `ca-certificates`, `libc6-compat`, and `tzdata`.
2. Installs the `omniroute` npm package globally (`--dangerously-allow-all-scripts` is required for its native install scripts) and runs `omniroute setup --non-interactive`.
3. Creates `/workspace`, switches to the non-root `node` user, and sets it as the working directory.
4. Declares the provider-key environment defaults and exposes ports `20128` and `20129`.
5. Runs `omniroute providers list`, `providers validate`, and `providers test-all` as a build-time smoke check. These steps need network access and make the build slower; a failure here fails the build.
6. Sets `omniroute` as the entrypoint. With no arguments it launches `omniroute serve` (the default command), which starts the dashboard and the `/v1` proxy.

The image does not pin a package version, so every build installs the latest published `omniroute`. For reproducible deployments, pin the version in the `npm install` line (for example `omniroute@3.8.53`) and rebuild.

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

Because the database and generated secrets live in the data volume, keeping it means existing API keys and the encryption key survive the upgrade.

### Stop

```bash
docker stop omniroute
```

## Security notes

- **Change `INITIAL_PASSWORD`.** The baked-in `q1w2e3` value is a weak placeholder. Use a strong password (8+ characters) and never expose the dashboard to the internet without TLS and a reverse proxy.
- **The fake provider keys are not credentials.** They exist only so the build-time validation steps pass. Supply real keys at runtime.
- **`/v1/*` is unauthenticated by default.** OmniRoute is local-first, but this container publishes port `20128` on all interfaces. On any untrusted network, set `REQUIRE_API_KEY=true` and/or bind it to loopback (`-p 127.0.0.1:20128:20128`) so only local clients can spend your provider quota.
- **Keep secrets out of images.** Do not bake real keys into the `Dockerfile` or commit them to a `.env` file. Use runtime environment variables, `--env-file`, or your orchestrator's secret store.
- **The container runs as `node` (UID 1000), not root.** Keep the data volume owned by that UID.

## Troubleshooting

| Symptom | Fix |
| --- | --- |
| Build fails at `omniroute providers ...` | The build needs outbound network access. Re-run with a working connection/proxy, or remove those validation lines from the `Dockerfile`. |
| `EACCES` when writing to the data directory | Fix ownership of a bind mount: `sudo chown -R 1000:1000 ./omniroute-data`, or use a named volume. |
| Dashboard unreachable from the host | Confirm the container is running (`docker ps`) and that the port mapping is `-p 20128:20128`. The server binds `0.0.0.0` by default. |
| `INITIAL_PASSWORD` appears ignored | A password is already stored. Reset it with `omniroute reset-password`, or start with a fresh data volume. |
| `401` from `/v1/chat/completions` after enabling `REQUIRE_API_KEY` | Create an OmniRoute API key in the dashboard (**Endpoints**) and send it as `Authorization: Bearer <key>`. |

## Links

- Upstream project: <https://github.com/diegosouzapw/OmniRoute>
- Website and docs: <https://omniroute.online>
- npm package: <https://www.npmjs.com/package/omniroute>
- Docker Hub (official image): <https://hub.docker.com/r/diegosouzapw/omniroute>

## License

The packaging files in this repository are provided as-is. OmniRoute is distributed under the MIT License; see the [upstream license](https://github.com/diegosouzapw/OmniRoute/blob/main/LICENSE).
