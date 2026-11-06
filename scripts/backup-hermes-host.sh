#!/usr/bin/env bash
# Backup do Hermes (rodando em Docker) -> zip local -> rclone crypt -> Google Drive.
# Executar NO HOST (não dentro do container). Requer: docker (usuário no grupo docker), rclone, python3.
#
# Uso:
#   backup-hermes-host.sh              # backup + retenção
#   backup-hermes-host.sh --prune-only # só aplica retenção (remoto e local)
#   DRY_RUN=1 backup-hermes-host.sh --prune-only   # mostra o que seria apagado
set -euo pipefail

CONTAINER="${HERMES_CONTAINER:-hermes}"
REMOTE="${RCLONE_REMOTE:-gdrive-crypt:hermes-backup}"   # remote crypt já configurado no rclone
RCLONE_BIN="${RCLONE_BIN:-rclone}"
STAGE="${STAGE_DIR:-$HOME/.cache/hermes-backup}"

# Retenção local: últimos N zips.
KEEP_LOCAL="${KEEP_LOCAL:-3}"
# Retenção remota (GFS): mantém o backup mais recente de cada um dos últimos N dias,
# semanas (ISO) e meses com backup. Um backup pode ser mantido por mais de um critério.
KEEP_DAILY="${KEEP_DAILY:-7}"
KEEP_WEEKLY="${KEEP_WEEKLY:-4}"
KEEP_MONTHLY="${KEEP_MONTHLY:-6}"
DRY_RUN="${DRY_RUN:-0}"

log() { echo "[$(date '+%F %T')] $*"; }

# Lê nomes de arquivo no stdin e imprime os que NÃO estão na política de retenção.
# Arquivos fora do padrão hermes-backup-YYYYMMDD-HHMMSS.zip são ignorados (nunca apagados).
read -r -d '' RETENTION_PY <<'PY' || true
import re, sys
from datetime import datetime

kd, kw, km = (int(x) for x in sys.argv[1:4])
pat = re.compile(r'^hermes-backup-(\d{8})-(\d{6})\.zip$')

items = []
for line in sys.stdin:
    name = line.strip()
    m = pat.match(name)
    if m:
        items.append((datetime.strptime(m.group(1), '%Y%m%d'), name))
items.sort(reverse=True)  # mais recente primeiro

keep = set()

def pick(bucket, n):
    seen = set()
    for dt, name in items:
        k = bucket(dt)
        if k in seen:
            continue
        if len(seen) >= n:
            break
        seen.add(k)
        keep.add(name)

pick(lambda d: d.date(), kd)
pick(lambda d: d.isocalendar()[:2], kw)
pick(lambda d: (d.year, d.month), km)

for _, name in items:
    if name not in keep:
        print(name)
PY

# Lê nomes no stdin e imprime os que devem ser apagados (ver RETENTION_PY).
# Usa -c para não competir com o stdin (um heredoc com "python3 -" o sobrescreveria).
retention_plan() {
  python3 -c "$RETENTION_PY" "$KEEP_DAILY" "$KEEP_WEEKLY" "$KEEP_MONTHLY"
}

prune_remote() {
  log "retenção remota em $REMOTE (diários=$KEEP_DAILY semanais=$KEEP_WEEKLY mensais=$KEEP_MONTHLY)"
  local names
  names="$("$RCLONE_BIN" lsf "$REMOTE" | retention_plan)"
  if [ -z "$names" ]; then
    log "nada a apagar no remoto"
    return
  fi
  while IFS= read -r name; do
    if [ "$DRY_RUN" = "1" ]; then
      log "[dry-run] apagaria: $name"
    else
      log "apagando do remoto: $name"
      "$RCLONE_BIN" deletefile "$REMOTE/$name"
    fi
  done <<< "$names"
}

prune_local() {
  log "retenção local em $STAGE (últimos $KEEP_LOCAL)"
  ls -1t "$STAGE"/hermes-backup-*.zip 2>/dev/null | tail -n +$((KEEP_LOCAL + 1)) | while IFS= read -r f; do
    if [ "$DRY_RUN" = "1" ]; then
      log "[dry-run] apagaria local: $f"
    else
      log "apagando local: $f"
      rm -f -- "$f"
    fi
  done
}

main() {
  mkdir -p "$STAGE"

  if [ "${1:-}" = "--prune-only" ]; then
    prune_remote
    prune_local
    return
  fi

  local name="hermes-backup-$(date +%Y%m%d-%H%M%S).zip"
  local tmp_in_container="/tmp/$name"

  log "gerando backup no container '$CONTAINER'"
  docker exec "$CONTAINER" /opt/hermes/bin/hermes backup -o "$tmp_in_container" -k 0
  docker cp "$CONTAINER:$tmp_in_container" "$STAGE/$name"
  docker exec "$CONTAINER" rm -f "$tmp_in_container"

  log "validando zip"
  python3 -m zipfile -t "$STAGE/$name" >/dev/null

  log "enviando para $REMOTE"
  "$RCLONE_BIN" copy "$STAGE/$name" "$REMOTE" --transfers 1 --retries 3

  prune_remote
  prune_local

  log "concluído: $name"
}

# Permite importar as funções em testes: source backup-hermes-host.sh
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  main "$@"
fi
