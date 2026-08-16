#!/usr/bin/env bash
# ============================================================================
#  Service de backup planifie.
#  Tourne en boucle : attend l'heure dite, demande une sauvegarde du monde en
#  RCON, archive Saves/ et Server/, puis applique la retention.
# ============================================================================
set -euo pipefail

ZOMBOID_DIR="${ZOMBOID_DIR:-/zomboid}"
BACKUP_DIR="${BACKUP_DIR:-/backups}"
BACKUP_AT="${BACKUP_AT:-04:00}"          # heure quotidienne HH:MM (TZ du conteneur)
BACKUP_KEEP="${BACKUP_KEEP:-7}"          # nombre d'archives conservees
BACKUP_ON_START="${BACKUP_ON_START:-false}"
RCON_HOST="${RCON_HOST:-pz-server}"
RCON_PORT="${RCON_PORT:-27015}"
RCON_PASSWORD="${RCON_PASSWORD:-}"

log() { printf '\033[35m[backup]\033[0m %s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }

if ! printf '%s' "$BACKUP_AT" | grep -qE '^[0-2][0-9]:[0-5][0-9]$'; then
  log "BACKUP_AT invalide ('${BACKUP_AT}'), format attendu HH:MM"
  exit 1
fi

# --- demande au serveur d'ecrire le monde sur disque ------------------------
# Best effort : si le serveur est arrete ou injoignable, on archive quand meme.
save_world() {
  if [ -z "$RCON_PASSWORD" ]; then
    log "RCON_PASSWORD vide -> pas de save prealable"
    return 0
  fi
  if rcon -a "${RCON_HOST}:${RCON_PORT}" -p "$RCON_PASSWORD" save >/dev/null 2>&1; then
    log "save RCON envoyee, attente de l'ecriture sur disque"
    sleep 15
  else
    log "serveur injoignable en RCON -> archivage sans save prealable"
  fi
}

# --- archivage ---------------------------------------------------------------
do_backup() {
  local stamp out sources=()
  stamp="$(date +%Y%m%d-%H%M%S)"
  out="${BACKUP_DIR}/pz-backup-${stamp}.tar.gz"

  [ -d "${ZOMBOID_DIR}/Saves" ]  && sources+=(Saves)
  [ -d "${ZOMBOID_DIR}/Server" ] && sources+=(Server)
  if [ "${#sources[@]}" -eq 0 ]; then
    log "rien a sauvegarder dans ${ZOMBOID_DIR} (serveur jamais demarre ?)"
    return 0
  fi

  save_world

  log "archivage de ${sources[*]} -> $(basename "$out")"
  # ecriture sous .part puis renommage : une archive presente est complete
  if tar czf "${out}.part" -C "$ZOMBOID_DIR" "${sources[@]}" 2>/dev/null; then
    mv "${out}.part" "$out"
    log "termine : $(basename "$out") ($(du -h "$out" | cut -f1))"
  else
    rm -f "${out}.part"
    log "ECHEC de l'archivage"
    return 0
  fi

  prune
}

# --- retention ---------------------------------------------------------------
prune() {
  local count
  count="$(find "$BACKUP_DIR" -maxdepth 1 -name 'pz-backup-*.tar.gz' | wc -l)"
  if [ "$count" -le "$BACKUP_KEEP" ]; then
    log "retention : ${count}/${BACKUP_KEEP} archives conservees"
    return 0
  fi
  log "retention : ${count} archives > ${BACKUP_KEEP}, suppression des plus anciennes"
  # les noms sont horodates -> le tri lexicographique suffit
  find "$BACKUP_DIR" -maxdepth 1 -name 'pz-backup-*.tar.gz' | sort \
    | head -n "$(( count - BACKUP_KEEP ))" \
    | while read -r old; do
        log "  suppression $(basename "$old")"
        rm -f "$old"
      done
}

# --- attente jusqu'au prochain BACKUP_AT ------------------------------------
sleep_until_next() {
  local now target delay pid
  now="$(date +%s)"
  target="$(date -d "today ${BACKUP_AT}" +%s)"
  [ "$target" -le "$now" ] && target="$(date -d "tomorrow ${BACKUP_AT}" +%s)"
  delay="$(( target - now ))"
  log "prochain backup le $(date -d "@${target}" '+%Y-%m-%d %H:%M') (dans $(( delay / 3600 ))h$(( (delay % 3600) / 60 ))m)"
  # sleep en arriere-plan + wait : le trap SIGTERM reste reactif
  sleep "$delay" &
  pid=$!
  wait "$pid"
}

mkdir -p "$BACKUP_DIR"
trap 'log "arret demande"; exit 0' SIGTERM SIGINT

log "demarre - backup quotidien a ${BACKUP_AT}, retention ${BACKUP_KEEP} archives"
[ "$BACKUP_ON_START" = "true" ] && do_backup || true

while true; do
  sleep_until_next
  do_backup
done
