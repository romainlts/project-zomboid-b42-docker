#!/usr/bin/env bash
# ============================================================================
#  Scheduled backup service.
#  Runs in a loop: waits for the configured time, asks the server to save the
#  world over RCON, archives Saves/ and Server/, then applies retention.
#
#  FR : Service de backup planifie.
#  FR : Tourne en boucle : attend l'heure dite, demande une sauvegarde du monde
#  FR : en RCON, archive Saves/ et Server/, puis applique la retention.
# ============================================================================
set -euo pipefail

ZOMBOID_DIR="${ZOMBOID_DIR:-/zomboid}"
BACKUP_DIR="${BACKUP_DIR:-/backups}"
# daily time HH:MM (container TZ) / FR : heure quotidienne HH:MM (TZ conteneur)
BACKUP_AT="${BACKUP_AT:-04:00}"
# number of archives kept / FR : nombre d'archives conservees
BACKUP_KEEP="${BACKUP_KEEP:-7}"
BACKUP_ON_START="${BACKUP_ON_START:-false}"
RCON_HOST="${RCON_HOST:-pz-server}"
RCON_PORT="${RCON_PORT:-27015}"
RCON_PASSWORD="${RCON_PASSWORD:-}"

log() { printf '\033[35m[backup]\033[0m %s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }

if ! printf '%s' "$BACKUP_AT" | grep -qE '^[0-2][0-9]:[0-5][0-9]$'; then
  log "BACKUP_AT invalide ('${BACKUP_AT}'), format attendu HH:MM"
  exit 1
fi

# --- ask the server to flush the world to disk ------------------------------
# Best effort: if the server is stopped or unreachable, we archive anyway.
# FR : demande au serveur d'ecrire le monde sur disque
# FR : Best effort : si le serveur est arrete ou injoignable, on archive
# FR : quand meme.
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

# --- archiving --------------------------------------------------------------
# FR : archivage
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
  # Write to .part then rename: any archive you can see is complete.
  #
  # We back up live data: the server keeps writing while tar reads, so files
  # can change or disappear mid-archive. tar reports that with exit code 1,
  # which is a warning, not a failure - the archive is still usable. Only
  # exit 2 and above are fatal. stderr is kept and logged, otherwise a real
  # failure is impossible to diagnose.
  #
  # FR : ecriture sous .part puis renommage : une archive presente est
  # FR : complete. On sauvegarde des donnees vivantes : le serveur ecrit
  # FR : pendant que tar lit, donc des fichiers peuvent changer ou dispara-
  # FR : itre. tar signale cela par le code 1, qui est un avertissement et
  # FR : non un echec. Seuls les codes >= 2 sont fatals. On conserve stderr,
  # FR : sinon un vrai echec est indiagnosticable.
  local err rc
  err="$(mktemp)"
  tar --ignore-failed-read -czf "${out}.part" -C "$ZOMBOID_DIR" "${sources[@]}" 2>"$err"
  rc=$?

  if [ "$rc" -ge 2 ]; then
    log "ECHEC de l'archivage (tar code ${rc}) :"
    sed 's/^/  /' "$err" | head -5 | while read -r l; do log "$l"; done
    rm -f "${out}.part" "$err"
    return 0
  fi

  if [ "$rc" -eq 1 ]; then
    log "avertissements tar (fichiers modifies pendant la lecture) :"
    sed 's/^/  /' "$err" | head -3 | while read -r l; do log "$l"; done
  fi
  rm -f "$err"

  mv "${out}.part" "$out"
  log "termine : $(basename "$out") ($(du -h "$out" | cut -f1))"

  prune
}

# --- retention --------------------------------------------------------------
# FR : retention
prune() {
  local count
  count="$(find "$BACKUP_DIR" -maxdepth 1 -name 'pz-backup-*.tar.gz' | wc -l)"
  if [ "$count" -le "$BACKUP_KEEP" ]; then
    log "retention : ${count}/${BACKUP_KEEP} archives conservees"
    return 0
  fi
  log "retention : ${count} archives > ${BACKUP_KEEP}, suppression des plus anciennes"
  # names are timestamped -> lexicographic sort is enough
  # FR : les noms sont horodates -> le tri lexicographique suffit
  find "$BACKUP_DIR" -maxdepth 1 -name 'pz-backup-*.tar.gz' | sort \
    | head -n "$(( count - BACKUP_KEEP ))" \
    | while read -r old; do
        log "  suppression $(basename "$old")"
        rm -f "$old"
      done
}

# --- wait until the next BACKUP_AT ------------------------------------------
# FR : attente jusqu'au prochain BACKUP_AT
sleep_until_next() {
  local now target delay pid
  now="$(date +%s)"
  target="$(date -d "today ${BACKUP_AT}" +%s)"
  [ "$target" -le "$now" ] && target="$(date -d "tomorrow ${BACKUP_AT}" +%s)"
  delay="$(( target - now ))"
  log "prochain backup le $(date -d "@${target}" '+%Y-%m-%d %H:%M') (dans $(( delay / 3600 ))h$(( (delay % 3600) / 60 ))m)"
  # background sleep + wait: keeps the SIGTERM trap responsive
  # FR : sleep en arriere-plan + wait : le trap SIGTERM reste reactif
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
