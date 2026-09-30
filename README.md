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

## Run

```bash
docker compose up -d
docker compose logs -f
```

- API server + health endpoint: http://localhost:8642
- Web dashboard: http://localhost:9119

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

## Interactive CLI chat

```bash
docker run -it --rm \
  -v "$(pwd)/hermes-data:/opt/data" \
  nousresearch/hermes-agent
```
