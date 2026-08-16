#!/usr/bin/env bash
# Envoie une commande RCON au serveur.
#   ./scripts/rcon.sh players
#   ./scripts/rcon.sh "servermsg \"Redemarrage dans 5 min\""
set -euo pipefail
cd "$(dirname "$0")/.."
if [ -f .env ]; then set -a; . ./.env; set +a; fi

CMD="${*:-help}"
docker compose exec -T pz-server \
  rcon -a 127.0.0.1:27015 -p "${RCON_PASSWORD}" "${CMD}"
