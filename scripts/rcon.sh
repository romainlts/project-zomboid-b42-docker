#!/usr/bin/env bash
# Sends an RCON command to the server.
#   ./scripts/rcon.sh players
#   ./scripts/rcon.sh "servermsg \"Restarting in 5 minutes\""
# FR : Envoie une commande RCON au serveur.
set -euo pipefail
cd "$(dirname "$0")/.."

# Read a single key from the .env WITHOUT sourcing it: the file is not a shell
# script, and any unquoted value containing spaces (SERVER_PUBLIC_NAME=Mon
# serveur B42) would be executed as a command.
# FR : Lit une cle du .env SANS le sourcer : ce fichier n'est pas un script
# FR : shell, et toute valeur non quotee contenant des espaces serait executee
# FR : comme une commande.
env_get() {
  [ -f .env ] || return 0
  sed -n "s/^[[:space:]]*$1=//p" .env | tail -n1 | tr -d '\r'
}

RCON_PASSWORD="${RCON_PASSWORD:-$(env_get RCON_PASSWORD)}"

if [ -z "$RCON_PASSWORD" ]; then
  echo "RCON_PASSWORD introuvable : renseigne-le dans .env" >&2
  exit 1
fi

CMD="${*:-help}"
docker compose exec -T pz-server \
  rcon -a 127.0.0.1:27015 -p "${RCON_PASSWORD}" "${CMD}"
