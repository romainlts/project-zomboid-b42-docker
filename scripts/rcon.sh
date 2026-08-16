#!/usr/bin/env bash
# Sends an RCON command to the server.
#   ./scripts/rcon.sh players
#   ./scripts/rcon.sh "servermsg \"Restarting in 5 minutes\""
# FR : Envoie une commande RCON au serveur.
set -euo pipefail
cd "$(dirname "$0")/.."
if [ -f .env ]; then set -a; . ./.env; set +a; fi

CMD="${*:-help}"
docker compose exec -T pz-server \
  rcon -a 127.0.0.1:27015 -p "${RCON_PASSWORD}" "${CMD}"
