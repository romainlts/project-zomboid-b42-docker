#!/usr/bin/env bash
set -euo pipefail

PZ_DIR="${PZ_DIR:-/pz-server}"
ZOMBOID_DIR="${ZOMBOID_DIR:-/zomboid}"
STEAM_DIR="${STEAM_DIR:-/opt/steamcmd}"
PZ_APPID="${PZ_APPID:-380870}"
# "" = public branch, which is Build 42 since B42 went stable.
# Other known branches: "legacy41" (Build 41.78.20), "42.19" (Build 42.19.1).
# FR : "" = branche publique, c'est-a-dire Build 42 depuis sa sortie stable.
# FR : Autres branches connues : "legacy41" (Build 41.78.20), "42.19".
PZ_BRANCH="${PZ_BRANCH:-}"
PZ_BRANCH_PASSWORD="${PZ_BRANCH_PASSWORD:-}"
UPDATE_ON_START="${UPDATE_ON_START:-true}"
PUID="${PUID:-1000}"
PGID="${PGID:-1000}"
# Pause before exiting on a fatal configuration error. The compose restart
# policy is "unless-stopped", so exiting immediately spins the container in a
# tight loop, hammering Steam and drowning the useful message in the logs.
# FR : Pause avant de sortir sur une erreur de configuration fatale. La
# FR : politique de redemarrage etant "unless-stopped", sortir immediatement
# FR : fait boucler le conteneur, martele Steam et noie le message utile.
FATAL_DELAY="${FATAL_DELAY:-60}"

log() { printf '\033[36m[pz]\033[0m %s\n' "$*"; }

fatal() {
  local line
  for line in "$@"; do log "$line"; done
  log "Arret dans ${FATAL_DELAY}s (corrige la configuration puis relance)."
  sleep "$FATAL_DELAY"
  exit 1
}

# --- align UID/GID with the host (useful on Linux) --------------------------
# FR : alignement des UID/GID sur l'hote (utile sous Linux)
if [ "$(id -u)" = "0" ]; then
  current_uid="$(id -u pz)"; current_gid="$(id -g pz)"
  [ "$PGID" != "$current_gid" ] && groupmod -o -g "$PGID" pz || true
  [ "$PUID" != "$current_uid" ] && usermod  -o -u "$PUID" pz || true
  mkdir -p "$PZ_DIR" "$ZOMBOID_DIR"
  chown -R pz:pz "$PZ_DIR" "$ZOMBOID_DIR" "$STEAM_DIR" /home/pz || true
  exec gosu pz "$0" "$@"
fi

export HOME=/home/pz

# --- install / update through steamcmd --------------------------------------
# Only app_update is used. Pinning an exact build with download_depot is not
# possible here: an anonymous Steam account may install the app but holds no
# depot license, and Steam answers "missing license for depot (No
# subscription)". To freeze a version, install once then set
# UPDATE_ON_START=false, and snapshot the install volume with
# scripts/install-snapshot.sh if you need to reproduce it elsewhere.
#
# FR : installation / mise a jour via steamcmd
# FR : Seul app_update est utilise. Figer une build exacte via download_depot
# FR : est impossible ici : un compte Steam anonyme peut installer l'app mais
# FR : n'a aucune licence de depot, et Steam repond "missing license for depot
# FR : (No subscription)". Pour figer une version, installe une fois puis mets
# FR : UPDATE_ON_START=false, et archive le volume d'installation avec
# FR : scripts/install-snapshot.sh si tu veux la reproduire ailleurs.
install_or_update() {
  log "SteamCMD : app ${PZ_APPID} branche='${PZ_BRANCH:-public}' (derniere build)"

  local args=(+force_install_dir "$PZ_DIR" +login anonymous +app_update "$PZ_APPID")

  if [ -n "$PZ_BRANCH" ]; then
    args+=(-beta "$PZ_BRANCH")
    [ -n "$PZ_BRANCH_PASSWORD" ] && args+=(-betapassword "$PZ_BRANCH_PASSWORD") || true
  fi

  args+=(validate +quit)
  # steamcmd exits 0 even when it failed, so check the result instead.
  # FR : steamcmd sort en 0 meme en cas d'echec : on verifie le resultat.
  "$STEAM_DIR/steamcmd.sh" "${args[@]}" || true

  if [ ! -f "$PZ_DIR/ProjectZomboid64" ]; then
    fatal "ECHEC : SteamCMD n'a pas installe le serveur." \
          "Branche demandee : '${PZ_BRANCH:-public}'." \
          "Branches connues : '' (=public, Build 42), 'legacy41', '42.19'." \
          "Une branche inexistante donne 'Missing configuration'."
  fi
}

if [ ! -f "$PZ_DIR/ProjectZomboid64" ] || [ "$UPDATE_ON_START" = "true" ]; then
  install_or_update
else
  log "Mise a jour desactivee (UPDATE_ON_START=false)"
fi

# --- installed version ------------------------------------------------------
# FR : version installee
if [ -f "$PZ_DIR/steamapps/appmanifest_${PZ_APPID}.acf" ]; then
  buildid="$(grep -oP '"buildid"\s+"\K[0-9]+' "$PZ_DIR/steamapps/appmanifest_${PZ_APPID}.acf" || true)"
  log "buildid Steam installe : ${buildid:-inconnu}"
fi

exec "$@"
