# hermes-agent

Docker Compose setup for running [Hermes Agent](https://hermes-agent.nousresearch.com/) (`nousresearch/hermes-agent`) in gateway mode with the web dashboard and API server enabled.

## First-time setup

Run the interactive configuration wizard once to generate `.env` and `config.yaml` under `./hermes-data`:

```bash
mkdir -p hermes-data
docker run -it --rm \
  -v "$(pwd)/hermes-data:/opt/data" \
  nousresearch/hermes-agent setup
```

## Configure secrets

```bash
cp .env.example .env
```

Edit `.env` and set:
- `API_SERVER_KEY` — generate with `openssl rand -hex 32` (minimum 8 characters)
- `PUID` / `PGID` — match your host user (`id -u` / `id -g`) to avoid permission errors on the mounted volume
- `HERMES_DASHBOARD_BASIC_AUTH_USERNAME` / `PASSWORD` / `SECRET` — required because the dashboard is bound to `0.0.0.0`; Hermes refuses to start on a non-loopback bind without an auth provider. Generate the secret with `openssl rand -hex 32`.

> For OAuth (Nous Portal) or self-hosted OIDC instead of basic auth, see the [Docker guide](https://hermes-agent.nousresearch.com/docs/user-guide/docker) and set `HERMES_DASHBOARD_OAUTH_CLIENT_ID` or `HERMES_DASHBOARD_OIDC_ISSUER` + `HERMES_DASHBOARD_OIDC_CLIENT_ID` instead.

## Run

The image is built locally on first run (see [Bot Desktop](#bot-desktop-xfce-over-vnc) below):

```bash
docker compose up -d --build
docker compose logs -f
```

- API server + health endpoint: http://localhost:8642
- Web dashboard: http://localhost:9119 (includes the Bot Desktop pane)

## Bot Desktop (Xfce over VNC)

`Dockerfile` extends the official image with the display stack. The upstream image
already ships everything else the desktop needs — `tools/bot_desktop/launcher.sh`,
the `computer_use` tool, the headed Chromium at `/opt/hermes/tools/chromium-*`, and
the RFB relay in `hermes_cli/web_routers/display.py`. It only lacks the binaries.

The package list is not arbitrary: it is `PACKAGES["apt"]` from
`tools/bot_desktop/runtime.py`, and the build fails if any of the launcher's
`REQUIRED_BINARIES` (`Xvnc`, `xfwm4`, `xfce4-panel`, `xfdesktop`, `xfsettingsd`,
`dbus-run-session`, `xauth`, `xdpyinfo`, `setxkbmap`, `xprop`) is missing. Baking it
into the image matters because Hermes' own `hermes screen install` / the dashboard's
Install button run `apt-get` at runtime, which lands in the container's ephemeral
layer and disappears on recreate.

### Using it

Open the dashboard and use the **Screen** pane (Bot Desktop) → **Start**. The desktop
also starts on demand when the agent uses `computer_use` or opens a headed browser.
To start it with the gateway instead of waiting for the pane:

```yaml
# hermes-data/config.yaml
bot_desktop:
  auto_start: true
  # idle_stop_minutes: 30   # a desktop nobody uses still holds ~220 MiB
```

### How you connect (there is no port 5900)

Xvnc listens on a **private Unix socket** (`<HERMES_HOME>/bot-desktop/rfb.sock`, mode
0600) and the dashboard relays it over WebSocket on port 9119, where keyboard, pointer
and clipboard go through `tools/bot_desktop/rfb_filter.py`. This is deliberate
upstream design — a TCP VNC port reachable from outside the container would expose the
desktop with no auth. So:

- Do **not** add `5900:5900` to the compose file; nothing listens there.
- View the desktop at `http://localhost:9119`, not with a VNC client.

If you need a real VNC client (RealVNC, Screens, TigerVNC) pointed at the container,
that is a custom addition on top of this image: an Xvnc/`-localhost` TCP listener or a
`websockify` bridge plus a reverse proxy with auth. Say so and the compose can grow one.

### Variants

- **Pin the base** for reproducible builds:
  `docker compose build --build-arg HERMES_BASE=nousresearch/hermes-agent:v0.22.5`, or
  set `HERMES_BASE` in `.env`.
- **No build at all**: the official `nousresearch/hermes-agent:latest-desktop` tag is
  a strict superset of this layer (same packages plus apt `chromium`). Drop `build:`
  from compose and set `image: nousresearch/hermes-agent:latest-desktop`.
- **apt chromium fallback**: the pinned Chromium is what the launcher uses; uncomment
  the `chromium` line in `Dockerfile` only if the Screen pane reports
  `Chrome not found` on a host with restricted user namespaces.

## Persistent data

All state lives in `./hermes-data` (mounted at `/opt/data` in the container):

| Path | Contents |
|------|----------|
| `.env` | API keys and secrets |
| `config.yaml` | Configuration |
| `sessions/` | Conversation history |
| `memories/` | Persistent memory store |
| `skills/` | Installed skills |
| `logs/` | Runtime logs |
| `home/` | Subprocess HOME directory |
| `bot-desktop/` | Per-profile Xvnc/Xfce state: RFB socket, Xauthority, XDG config, browser profile |

## Interactive CLI chat

```bash
docker run -it --rm \
  -v "$(pwd)/hermes-data:/opt/data" \
  nousresearch/hermes-agent
```
