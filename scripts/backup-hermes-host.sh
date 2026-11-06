#!/usr/bin/env bash
# Backup do Hermes (rodando em Docker) -> zip local -> rclone crypt -> Google Drive.
# Executar NO HOST (não dentro do container). Requer: docker (usuário no grupo docker), rclone, python3.
set -euo pipefail

CONTAINER="${HERMES_CONTAINER:-hermes}"
REMOTE="${RCLONE_REMOTE:-gdrive-crypt:hermes-backup}"   # remote crypt já configurado no rclone
RCLONE_BIN="${RCLONE_BIN:-rclone}"
STAGE="${STAGE_DIR:-$HOME/.cache/hermes-backup}"
KEEP_LOCAL="${KEEP_LOCAL:-3}"
KEEP_REMOTE_DAYS="${KEEP_REMOTE_DAYS:-14}"

log() { echo "[$(date '+%F %T')] $*"; }

mkdir -p "$STAGE"
NAME="hermes-backup-$(date +%Y%m%d-%H%M%S).zip"
TMP_IN_CONTAINER="/tmp/$NAME"

log "gerando backup no container '$CONTAINER'"
docker exec "$CONTAINER" /opt/hermes/bin/hermes backup -o "$TMP_IN_CONTAINER" -k 0
docker cp "$CONTAINER:$TMP_IN_CONTAINER" "$STAGE/$NAME"
docker exec "$CONTAINER" rm -f "$TMP_IN_CONTAINER"

log "validando zip"
python3 -m zipfile -t "$STAGE/$NAME" >/dev/null

log "enviando para $REMOTE"
"$RCLONE_BIN" copy "$STAGE/$NAME" "$REMOTE" --transfers 1 --retries 3

log "removendo backups remotos com mais de ${KEEP_REMOTE_DAYS}d"
"$RCLONE_BIN" delete "$REMOTE" --min-age "${KEEP_REMOTE_DAYS}d"

log "mantendo os $KEEP_LOCAL zips locais mais recentes"
ls -1t "$STAGE"/hermes-backup-*.zip 2>/dev/null | tail -n +$((KEEP_LOCAL + 1)) | xargs -r rm -f

log "concluído: $NAME"
