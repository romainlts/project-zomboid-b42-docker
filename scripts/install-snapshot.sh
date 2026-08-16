#!/usr/bin/env bash
# Snapshots the server INSTALLATION (the pz-install volume) into ./backups/.
#
# This is how you freeze a version reproducibly. Steam refuses to pin an exact
# build for anonymous accounts, so the only way to get the same binaries back
# on another machine - or after losing the volume - is to keep a copy of them.
#
# The buildid goes into the file name, so a snapshot says which build it holds.
#
#   ./scripts/install-snapshot.sh
#   -> backups/pz-install-24574884-20260816-160000.tar.gz
#
# To restore, with the server stopped:
#   docker compose stop pz-server
#   docker run --rm -v pz-b42_pz-install:/pz-server -v "$PWD/backups:/in:ro" \
#     debian:bookworm-slim tar xzf /in/<snapshot>.tar.gz -C /pz-server
#   docker compose start pz-server
# Remember to set UPDATE_ON_START=false first, or Steam will update it again.
#
# FR : Archive l'INSTALLATION du serveur (volume pz-install) dans ./backups/.
# FR : C'est la facon de figer une version de maniere reproductible : Steam
# FR : refuse de pinner une build exacte pour les comptes anonymes, donc le
# FR : seul moyen de retrouver les memes binaires ailleurs, ou apres perte du
# FR : volume, est d'en garder une copie. Le buildid figure dans le nom du
# FR : fichier. Pour restaurer, voir les commandes ci-dessus, et pense a
# FR : mettre UPDATE_ON_START=false avant, sinon Steam remet a jour.
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

VOLUME="${VOLUME:-pz-b42_pz-install}"
OUT_DIR="backups"
STAMP="$(date +%Y%m%d-%H%M%S)"

if ! docker volume inspect "$VOLUME" >/dev/null 2>&1; then
  echo "Volume '${VOLUME}' introuvable. Le stack a-t-il deja demarre ?" >&2
  exit 1
fi

mkdir -p "$OUT_DIR"

# Read the buildid from the Steam manifest so the snapshot is self-describing.
# FR : Lit le buildid dans le manifest Steam pour que l'archive s'auto-decrive.
BUILDID="$(docker run --rm -v "${VOLUME}:/pz-server:ro" debian:bookworm-slim \
  sh -c 'grep -oE "\"buildid\"[[:space:]]+\"[0-9]+\"" /pz-server/steamapps/appmanifest_380870.acf 2>/dev/null | grep -oE "[0-9]+" | head -1' \
  || true)"
BUILDID="${BUILDID:-inconnu}"

NAME="pz-install-${BUILDID}-${STAMP}.tar.gz"
echo "[snapshot] volume ${VOLUME}, buildid ${BUILDID} -> ${OUT_DIR}/${NAME}"
echo "[snapshot] l'installation pese plusieurs Go, compte quelques minutes"

docker run --rm \
  -v "${VOLUME}:/pz-server:ro" \
  -v "$(pwd)/${OUT_DIR}:/out" \
  debian:bookworm-slim \
  tar czf "/out/${NAME}.part" -C /pz-server .

mv "${OUT_DIR}/${NAME}.part" "${OUT_DIR}/${NAME}"
echo "[snapshot] termine : ${OUT_DIR}/${NAME}"
ls -lh "${OUT_DIR}/${NAME}"
