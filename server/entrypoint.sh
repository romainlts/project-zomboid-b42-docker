#!/usr/bin/env bash
set -euo pipefail

PZ_DIR="${PZ_DIR:-/pz-server}"
ZOMBOID_DIR="${ZOMBOID_DIR:-/zomboid}"
STEAM_DIR="${STEAM_DIR:-/opt/steamcmd}"
PZ_APPID="${PZ_APPID:-380870}"
PZ_BRANCH="${PZ_BRANCH:-unstable}"       # "" = branche publique, "unstable" = Build 42
PZ_BRANCH_PASSWORD="${PZ_BRANCH_PASSWORD:-}"
PZ_MANIFEST_ID="${PZ_MANIFEST_ID:-}"     # pin exact d'une build (ex: 42.20.2)
PZ_DEPOT_ID="${PZ_DEPOT_ID:-}"           # depot auquel appartient le manifest
PZ_PIN_STRICT="${PZ_PIN_STRICT:-true}"   # true = abandonner plutot qu'installer
                                         # une autre build que celle demandee
UPDATE_ON_START="${UPDATE_ON_START:-true}"
PUID="${PUID:-1000}"
PGID="${PGID:-1000}"

log() { printf '\033[36m[pz]\033[0m %s\n' "$*"; }

# --- alignement des UID/GID sur l'hote (utile sous Linux) -------------------
if [ "$(id -u)" = "0" ]; then
  current_uid="$(id -u pz)"; current_gid="$(id -g pz)"
  [ "$PGID" != "$current_gid" ] && groupmod -o -g "$PGID" pz || true
  [ "$PUID" != "$current_uid" ] && usermod  -o -u "$PUID" pz || true
  mkdir -p "$PZ_DIR" "$ZOMBOID_DIR"
  chown -R pz:pz "$PZ_DIR" "$ZOMBOID_DIR" "$STEAM_DIR" /home/pz || true
  exec gosu pz "$0" "$@"
fi

export HOME=/home/pz

# --- installation / mise a jour via steamcmd --------------------------------
install_or_update() {
  log "SteamCMD : app ${PZ_APPID} branche='${PZ_BRANCH:-public}' (derniere build)"

  local args=(+force_install_dir "$PZ_DIR" +login anonymous +app_update "$PZ_APPID")

  if [ -n "$PZ_BRANCH" ]; then
    args+=(-beta "$PZ_BRANCH")
    [ -n "$PZ_BRANCH_PASSWORD" ] && args+=(-betapassword "$PZ_BRANCH_PASSWORD") || true
  fi

  args+=(validate +quit)
  "$STEAM_DIR/steamcmd.sh" "${args[@]}"
}

# --- pin d'une build precise via download_depot ------------------------------
# app_update installe toujours la derniere build d'une branche. Pour figer une
# version exacte, il faut passer par le couple depot + manifest (SteamDB).
PIN_MARKER="$PZ_DIR/.pinned-manifest"

# Telecharge le depot pinne et le deploie sur $PZ_DIR. 0 = succes.
pin_download() {
  local content_root depot_dir

  log "Pin : depot ${PZ_DEPOT_ID}, manifest ${PZ_MANIFEST_ID}"
  # download_depot ignore force_install_dir : le contenu atterrit sous $HOME.
  "$STEAM_DIR/steamcmd.sh" +login anonymous \
    +download_depot "$PZ_APPID" "$PZ_DEPOT_ID" "$PZ_MANIFEST_ID" +quit || true

  # steamcmd renvoie souvent 0 meme en cas d'echec : on verifie le resultat.
  content_root="$HOME/Steam/steamapps/content/app_${PZ_APPID}"
  depot_dir="$(find "$content_root" -maxdepth 1 -type d -name "depot_${PZ_DEPOT_ID}*" 2>/dev/null | head -n1)"

  if [ -z "$depot_dir" ] || [ -z "$(ls -A "$depot_dir" 2>/dev/null)" ]; then
    log "download_depot n'a rien produit (branche non accessible en anonyme ?)"
    return 1
  fi
  if [ ! -f "$depot_dir/ProjectZomboid64" ]; then
    log "depot telecharge mais ProjectZomboid64 absent -> depot ID probablement incorrect"
    rm -rf "$content_root"
    return 1
  fi

  log "Deploiement du depot vers ${PZ_DIR}"
  rsync -a "$depot_dir/" "$PZ_DIR/"
  chmod +x "$PZ_DIR/ProjectZomboid64" "$PZ_DIR/start-server.sh" 2>/dev/null || true

  printf '%s\n' "$PZ_MANIFEST_ID" > "$PIN_MARKER"
  # la copie de travail fait la taille du jeu : on ne la garde pas
  rm -rf "$content_root"
  log "Build pinnee en place (manifest ${PZ_MANIFEST_ID})"
}

# Echec du pin : on n'installe JAMAIS une autre build en mode strict.
pin_failed() {
  if [ "$PZ_PIN_STRICT" = "true" ]; then
    log "ECHEC du pin et PZ_PIN_STRICT=true -> arret."
    log "Voir docs/PINNING.md. Pour installer la derniere build a la place,"
    log "mets PZ_PIN_STRICT=false, ou retire PZ_MANIFEST_ID."
    exit 1
  fi
  log "ECHEC du pin, repli sur app_update (PZ_PIN_STRICT=false)"
  install_or_update
}

ensure_pinned() {
  if ! printf '%s' "$PZ_MANIFEST_ID" | grep -qE '^[0-9]+$'; then
    log "PZ_MANIFEST_ID invalide ('${PZ_MANIFEST_ID}') : attendu un nombre (voir SteamDB)"
    exit 1
  fi
  if ! printf '%s' "$PZ_DEPOT_ID" | grep -qE '^[0-9]+$'; then
    log "PZ_MANIFEST_ID est defini mais PZ_DEPOT_ID est absent ou invalide."
    log "Les deux se recuperent ensemble sur https://steamdb.info/app/${PZ_APPID}/depots/"
    exit 1
  fi

  # deja sur le bon manifest -> rien a faire (et boot rapide)
  if [ -f "$PIN_MARKER" ] && [ "$(cat "$PIN_MARKER")" = "$PZ_MANIFEST_ID" ] \
     && [ -f "$PZ_DIR/ProjectZomboid64" ]; then
    log "Build deja pinnee sur le manifest ${PZ_MANIFEST_ID} : pas de telechargement"
    return 0
  fi

  pin_download || pin_failed
}

if [ -n "$PZ_MANIFEST_ID" ]; then
  # le pin prime sur UPDATE_ON_START : une build pinnee ne se met jamais a jour
  ensure_pinned
elif [ ! -f "$PZ_DIR/ProjectZomboid64" ] || [ "$UPDATE_ON_START" = "true" ]; then
  rm -f "$PIN_MARKER"
  install_or_update
else
  log "Mise a jour desactivee (UPDATE_ON_START=false)"
fi

# --- version installee ------------------------------------------------------
if [ -f "$PZ_DIR/steamapps/appmanifest_${PZ_APPID}.acf" ]; then
  buildid="$(grep -oP '"buildid"\s+"\K[0-9]+' "$PZ_DIR/steamapps/appmanifest_${PZ_APPID}.acf" || true)"
  log "buildid Steam installe : ${buildid:-inconnu}"
fi

exec "$@"
