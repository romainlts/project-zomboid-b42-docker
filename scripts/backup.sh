#!/usr/bin/env bash
# Snapshot of saves and configs into ./backups/
# FR : Snapshot des sauvegardes et configs dans ./backups/
set -euo pipefail
cd "$(dirname "$0")/.."

# Git Bash on Windows rewrites arguments that look like absolute paths, so
# "-C /pz-server" would become "-C C:/Program Files/.../pz-server" and the
# container path would never be seen. These two variables disable that; they
# are ignored everywhere else.
# FR : Git Bash sous Windows reecrit les arguments qui ressemblent a des
# FR : chemins absolus : "-C /pz-server" deviendrait un chemin Windows et le
# FR : chemin conteneur ne serait jamais vu. Ces deux variables desactivent
# FR : cette conversion ; elles sont ignorees ailleurs.
export MSYS_NO_PATHCONV=1
export MSYS2_ARG_CONV_EXCL='*'

STAMP="$(date +%Y%m%d-%H%M%S)"
OUT="backups/pz-backup-${STAMP}.tar.gz"
mkdir -p backups

echo "[backup] archivage du volume zomboid-data -> ${OUT}"
docker run --rm \
  -v pz-b42_zomboid-data:/zomboid:ro \
  -v "$(pwd)/backups:/out" \
  debian:bookworm-slim \
  tar czf "/out/pz-backup-${STAMP}.tar.gz" -C /zomboid Saves Server

echo "[backup] termine : ${OUT}"
ls -lh "${OUT}"
