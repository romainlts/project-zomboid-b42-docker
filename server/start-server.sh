#!/usr/bin/env bash
set -euo pipefail

PZ_DIR="${PZ_DIR:-/pz-server}"
ZOMBOID_DIR="${ZOMBOID_DIR:-/zomboid}"
SERVER_NAME="${SERVER_NAME:-servertest}"
ADMIN_PASSWORD="${ADMIN_PASSWORD:-changeme}"
SERVER_MEMORY="${SERVER_MEMORY:-6g}"
RCON_PORT="${RCON_PORT:-27015}"
RCON_PASSWORD="${RCON_PASSWORD:-changeme}"
DEFAULT_PORT="${DEFAULT_PORT:-16261}"
SERVER_PUBLIC="${SERVER_PUBLIC:-false}"
SERVER_PUBLIC_NAME="${SERVER_PUBLIC_NAME:-My B42 Server}"
MAX_PLAYERS="${MAX_PLAYERS:-16}"
SERVER_PASSWORD="${SERVER_PASSWORD:-}"
MOD_IDS="${MOD_IDS:-}"
WORKSHOP_IDS="${WORKSHOP_IDS:-}"

log() { printf '\033[36m[pz]\033[0m %s\n' "$*"; }

CFG_DIR="$ZOMBOID_DIR/Server"
mkdir -p "$CFG_DIR" "$ZOMBOID_DIR/Saves" "$ZOMBOID_DIR/Logs" "$ZOMBOID_DIR/backups"

INI="$CFG_DIR/${SERVER_NAME}.ini"

# --- generate the .ini on first start ---------------------------------------
# FR : generation du .ini au premier demarrage
FIRST_BOOT=0
if [ ! -f "$INI" ]; then
  log "Creation de $INI"
  cp /opt/pz-defaults/server.ini.template "$INI"
  FIRST_BOOT=1
fi

# --- apply env variables onto the .ini (idempotent) -------------------------
# Two regimes, so that we can coexist with the web panel editing the same file:
#
#   set_ini   infrastructure keys (ports, RCON). The .env is the source of
#             truth and the value is reapplied on every start: they must stay
#             aligned with docker-compose.yml.
#   seed_ini  settings the panel manages too (mods, MaxPlayers, ...). The .env
#             only seeds the .ini on the first start; afterwards the panel is
#             the source of truth and nothing is overwritten.
#
# PZ_FORCE_INI_KEYS forces seed_ini keys to be reapplied from the .env (list
# separated by spaces or commas), for one start only.
#
# FR : application des variables d'env sur le .ini (idempotent)
# FR : Deux regimes, pour cohabiter avec le panel web qui edite le meme
# FR : fichier :
# FR :   set_ini   cles d'infrastructure (ports, RCON). Le .env fait foi et la
# FR :             valeur est reappliquee a chaque demarrage : elles doivent
# FR :             rester alignees sur docker-compose.yml.
# FR :   seed_ini  reglages que le panel gere aussi (mods, MaxPlayers, ...).
# FR :             Le .env ne sert qu'a initialiser le .ini au premier
# FR :             demarrage ; ensuite c'est le panel qui fait foi.
# FR : PZ_FORCE_INI_KEYS force la reapplication de cles seed_ini depuis le
# FR : .env, le temps d'un demarrage.
FORCE_KEYS=" $(printf '%s' "${PZ_FORCE_INI_KEYS:-}" | tr ',' ' ') "

write_ini() {
  local key="$1" val="$2" esc
  # escape sed-special characters in the value (& \ and the delimiter)
  # FR : protege les caracteres speciaux de sed dans la valeur
  esc="$(printf '%s' "$val" | sed -e 's/[\\&|]/\\&/g')"
  if grep -q "^${key}=" "$INI"; then
    sed -i "s|^${key}=.*|${key}=${esc}|" "$INI"
  else
    printf '%s=%s\n' "$key" "$val" >> "$INI"
  fi
}

set_ini() { write_ini "$1" "$2"; }

seed_ini() {
  local key="$1" val="$2"
  if [ "$FIRST_BOOT" != "1" ] && [[ "$FORCE_KEYS" != *" ${key} "* ]]; then
    return 0
  fi
  write_ini "$key" "$val"
}

# --- infrastructure: the .env is the source of truth ------------------------
# FR : infrastructure : le .env fait foi
set_ini DefaultPort        "$DEFAULT_PORT"
set_ini RCONPort           "$RCON_PORT"
set_ini RCONPassword       "$RCON_PASSWORD"
set_ini SteamPort1         "16262"
set_ini SteamPort2         "16263"

# --- settings shared with the panel: seeded on first boot only --------------
# FR : reglages partages avec le panel : seeding au premier boot uniquement
seed_ini Public            "$SERVER_PUBLIC"
seed_ini PublicName        "$SERVER_PUBLIC_NAME"
seed_ini MaxPlayers        "$MAX_PLAYERS"
seed_ini Password          "$SERVER_PASSWORD"
seed_ini Mods              "$MOD_IDS"
seed_ini WorkshopItems     "$WORKSHOP_IDS"

if [ "$FIRST_BOOT" = "1" ]; then
  log "Premier demarrage : reglages initialises depuis .env"
else
  log "Reglages serveur/mods : pilotes par le panel (voir PZ_FORCE_INI_KEYS)"
fi

log "Config active : $INI"
log "RCON sur 0.0.0.0:${RCON_PORT}"

cd "$PZ_DIR"

# --- Java heap (B42 reads ProjectZomboid64.json) ----------------------------
# FR : heap Java (B42 lit ProjectZomboid64.json)
if [ -f "$PZ_DIR/ProjectZomboid64.json" ]; then
  sed -i "s/-Xmx[0-9]\+[gGmM]/-Xmx${SERVER_MEMORY}/" "$PZ_DIR/ProjectZomboid64.json"
  sed -i "s/-Xms[0-9]\+[gGmM]/-Xms${SERVER_MEMORY}/" "$PZ_DIR/ProjectZomboid64.json"
  log "Heap Java fixe a ${SERVER_MEMORY}"
fi

# PZ writes its data to \$HOME/Zomboid -> point it at the shared volume
# FR : PZ ecrit ses donnees dans \$HOME/Zomboid -> on pointe vers le volume
# FR : partage
export HOME=/home/pz
mkdir -p "$HOME"
if [ ! -L "$HOME/Zomboid" ]; then
  rm -rf "$HOME/Zomboid"
  ln -s "$ZOMBOID_DIR" "$HOME/Zomboid"
fi

# clean shutdown on SIGTERM (saves the world)
# FR : arret propre sur SIGTERM (sauvegarde du monde)
term_handler() {
  log "SIGTERM recu -> quit propre du serveur"
  if [ -n "${PZ_PID:-}" ]; then
    kill -TERM "$PZ_PID" 2>/dev/null || true
    wait "$PZ_PID" || true
  fi
  exit 0
}
trap term_handler SIGTERM SIGINT

exec_args=(
  -cachedir="$ZOMBOID_DIR"
  -servername "$SERVER_NAME"
  -adminpassword "$ADMIN_PASSWORD"
)
[ -n "$SERVER_PASSWORD" ] && exec_args+=(-password "$SERVER_PASSWORD") || true

log "Demarrage du serveur (${SERVER_MEMORY} de heap)"
JAVA_TOOL_OPTIONS="" ./start-server.sh "${exec_args[@]}" &
PZ_PID=$!
wait "$PZ_PID"
