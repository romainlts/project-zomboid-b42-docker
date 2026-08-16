#!/usr/bin/env bash
# Snapshot des sauvegardes et configs dans ./backups/
set -euo pipefail
cd "$(dirname "$0")/.."

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
