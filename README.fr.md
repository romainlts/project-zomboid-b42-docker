# PZ B42 Docker - serveur Project Zomboid Build 42 + panel web

*[English](README.md) | **Français***

Stack Docker « ready to use » : un serveur dédié **Project Zomboid Build 42**
(installé et mis à jour par SteamCMD) + le
**[Zomboid Control Panel](https://github.com/fpsacha/zomboid-control-panel)**
pour l'administrer depuis un navigateur.

| Service | Rôle | Ports |
|---|---|---|
| `pz-server` | serveur dédié PZ B42 | 16261-16263/udp - RCON 27015 interne |
| `panel` | interface d'admin web | 3001 |
| `backup` | archivage quotidien du monde vers `./backups` | - |
| `caddy` | reverse proxy HTTPS (optionnel, profil `proxy`) | 80, 443 |

Tous les services partagent deux volumes (`pz-install`, `zomboid-data`) : le
panel voit donc les configs, mods, logs et sauvegardes du serveur, et lui parle
en RCON sur le réseau interne `pz-net`.

---

# 0. Tu pars d'un serveur nu ?

Si tu déploies sur une machine Debian fraîche - un VPS, une machine dédiée, un
PC chez toi - commence par
**[Préparer un serveur dédié Debian](DEBIAN-SETUP.fr.md)**. Le guide déroule
les mises à jour système, la création d'un utilisateur non privilégié, le
durcissement SSH, le pare-feu UFW et l'installation de Docker, puis te renvoie
à la section 1 ci-dessous.

Ton serveur est déjà en place, sécurisé et équipé de Docker ? Passe directement
à la section 1.

---

# 1. Installation

## Prérequis

- **Docker Desktop** ([Windows/macOS](https://www.docker.com/products/docker-desktop/))
  ou **Docker Engine + plugin compose** (Linux)
- ~10 Go de disque libre
- 6 Go de RAM alloués au serveur par défaut (`SERVER_MEMORY`)

**Windows** : Docker Desktop doit tourner sur le backend **WSL2**. Le stack
n'utilise que des volumes nommés pour les données du jeu, donc pas de souci de
permissions ni de perfs disque.

**Linux** : aligne `PUID`/`PGID` sur ton utilisateur (`id -u`, `id -g`) dans le
`.env`, sinon les fichiers créés par le conteneur t'appartiendront pas.

## Démarrage

```bash
git clone https://github.com/romainlts/project-zomboid-b42-docker.git
cd project-zomboid-b42-docker
cp .env.example .env      # Windows PowerShell : Copy-Item .env.example .env
```

Édite `.env` : **`ADMIN_PASSWORD` et `RCON_PASSWORD` sont obligatoires**, le
stack refuse de démarrer sans eux.

```bash
docker compose up -d --build
docker compose logs -f pz-server
```

Le premier démarrage télécharge ~3-5 Go depuis Steam puis génère la carte :
compte **5 à 15 minutes** avant que le serveur soit joignable.

## Premier accès

- **Jeu** : rejoins `IP_DU_SERVEUR:16261`
- **Panel** : <http://localhost:3001> → crée le compte admin au premier accès
- Dans les réglages du panel, saisis les chemins **conteneur** - `/pz-server`
  et `/zomboid` - et surtout pas les chemins de ton PC

---

# 2. Configuration

Toute la configuration passe par le fichier `.env`. Les variables sont
documentées une par une dans [`.env.example`](.env.example) ; voici les
principales.

| Variable | Rôle |
|---|---|
| `ADMIN_PASSWORD` | mot de passe du compte `admin` in-game (obligatoire) |
| `RCON_PASSWORD` | mot de passe RCON, utilisé par le panel (obligatoire) |
| `SERVER_NAME` | nom interne du serveur, détermine le `.ini` et la sauvegarde |
| `SERVER_PUBLIC` / `SERVER_PUBLIC_NAME` | visibilité et nom dans la liste publique |
| `SERVER_PASSWORD` | mot de passe pour rejoindre (vide = libre) |
| `SERVER_MEMORY` | heap Java, `6g` par défaut |
| `MAX_PLAYERS` / `PZ_PORT` | joueurs simultanés et port de jeu |
| `TZ`, `PUID`, `PGID` | fuseau horaire et identité système |

Après modification : `docker compose up -d`.

## `.env` ou panel : qui configure quoi ?

Les deux éditent le même fichier `Server/<SERVER_NAME>.ini`. Le partage des
rôles est le suivant :

| Réglage | Qui fait foi |
|---|---|
| Ports, RCON, PUID/PGID, heap Java, branche Steam | **`.env`** - réappliqué à chaque démarrage |
| `Public`, `PublicName`, `MaxPlayers`, `Password`, `Mods`, `WorkshopItems` | `.env` au **premier démarrage**, puis **le panel** |
| Sandbox (loot, zombies, météo), joueurs, bans, backups | **le panel** uniquement |

Autrement dit : le `.env` amorce le serveur, le panel le pilote au quotidien.
Une modification faite dans l'interface n'est plus écrasée au redémarrage.

Pour réimposer une valeur du `.env` - par exemple remettre la liste de mods à
plat :

```
MOD_IDS=2392709985;2705938086
PZ_FORCE_INI_KEYS=Mods,WorkshopItems
```

`docker compose up -d pz-server`, puis **revide `PZ_FORCE_INI_KEYS`** - sinon
la clé serait réimposée à chaque redémarrage et le panel ne pourrait plus la
gérer.

> Les réglages sandbox ne sont pas dans le `.ini` mais dans `SandboxVars.lua` :
> ils ne sont pilotables que depuis le panel.

## Mods

Dans `.env` :

```
WORKSHOP_IDS=2392709985;2705938086
MOD_IDS=Authentic Z - Current;VISIBLE_BACKPACK_BACKGROUND
```

`WORKSHOP_IDS` liste les IDs Steam Workshop, `MOD_IDS` les noms internes des
mods - les deux sont nécessaires et séparés par des `;`.

Ces valeurs ne sont prises en compte qu'au **premier démarrage**. Ensuite,
gère les mods depuis le panel : il détecte en plus les conflits, les
dépendances manquantes et les problèmes d'ordre de chargement.

## Figer la version du serveur

Steam sert toujours la **dernière** build de la branche `unstable`. Une mise à
jour en cours de partie peut casser des mods. Deux niveaux de protection.

### Simple - geler après installation

Installe une fois, puis dans `.env` :

```
UPDATE_ON_START=false
```

`docker compose up -d`. Le conteneur ne rappelle plus Steam au démarrage et
reste sur la build téléchargée. Suffisant pour un serveur entre amis.

### Strict - pin par manifest

Reproductible même sur une machine neuve ou après la perte du volume. À
privilégier en production ou avec des mods sensibles à la version.

Sur [SteamDB - depots de 380870](https://steamdb.info/app/380870/depots/) :

1. ouvre le depot du **serveur dédié Linux**, note son **Depot ID** ;
2. onglet *Manifests*, choisis la branche `unstable` et la build voulue, note
   le **Manifest ID** (un long nombre).

Dans `.env` :

```
PZ_DEPOT_ID=<DEPOT_ID>
PZ_MANIFEST_ID=<MANIFEST_ID>
PZ_PIN_STRICT=true
```

Le serveur télécharge alors cette build exacte. À retenir :

- le pin **prime sur `UPDATE_ON_START`** : la build ne bouge plus jamais seule ;
- aux démarrages suivants, rien n'est retéléchargé si la build est déjà la
  bonne ;
- pour changer de version, change `PZ_MANIFEST_ID` et redémarre ; pour revenir
  au suivi de la branche, vide la variable.

Avec `PZ_PIN_STRICT=true` (défaut), si Steam refuse le téléchargement le
conteneur **s'arrête** au lieu d'installer une autre build - mieux vaut un
serveur qui ne démarre pas qu'un serveur sur la mauvaise version. Mets
`PZ_PIN_STRICT=false` pour accepter un repli sur la dernière build.

Pour vérifier la build installée :

```bash
docker compose exec pz-server sh -c 'grep buildid /pz-server/steamapps/appmanifest_380870.acf'
```

---

# 3. Utilisation

## Commandes courantes

```bash
docker compose up -d --build      # (re)construire et démarrer
docker compose stop pz-server     # arrêt propre (sauvegarde du monde)
docker compose logs -f pz-server  # suivre les logs
docker compose ps                 # état et santé des services
docker compose exec pz-server bash
./scripts/rcon.sh players         # commande RCON en CLI
./scripts/backup.sh               # backup manuel immédiat
```

L'arrêt laisse 120 s au serveur pour sauvegarder : n'interromps pas un
`docker compose stop`, sinon le monde peut être perdu.

Le serveur tourne avec `restart: unless-stopped` : un `quit` envoyé en RCON
depuis le panel arrête le process et Docker relance le conteneur - c'est le
mécanisme de « restart » de l'interface web.

## Backups automatiques

Un service `backup` archive le monde **tous les jours** dans `./backups/`. Il
est actif par défaut, rien à lancer.

```
BACKUP_AT=04:00        # heure quotidienne (dans le TZ du .env)
BACKUP_KEEP=7          # archives conservées, les plus vieilles sont purgées
BACKUP_ON_START=false  # true = backup immédiat au démarrage, pour tester
```

Avant chaque archive, le service envoie un `save` en RCON et attend 15 s pour
que le monde sur disque soit cohérent. Si le serveur est arrêté ou injoignable,
il archive quand même et le signale dans les logs.

L'archive contient `Saves/` et `Server/` - pas les ~5 Go d'installation Steam,
que SteamCMD sait retélécharger. Elle est écrite en `.part` puis renommée : un
fichier `pz-backup-*.tar.gz` présent est donc toujours complet.

```bash
docker compose logs -f backup
ls -lh backups/
```

Pour **restaurer**, le plus simple est le panel (onglet Backups). Sinon,
serveur arrêté :

```bash
docker compose stop pz-server
docker run --rm -v pz-b42_zomboid-data:/zomboid -v "$PWD/backups:/in:ro" \
  debian:bookworm-slim tar xzf /in/pz-backup-AAAAMMJJ-HHMMSS.tar.gz -C /zomboid
docker compose start pz-server
```

## État de santé

```bash
docker compose ps          # colonne STATUS : healthy / unhealthy / starting
```

`pz-server` est sondé par une **requête RCON**, pas par une simple présence de
processus : un serveur figé en garbage collector ou bloqué au chargement d'un
mod apparaît bien en `unhealthy`. Le panel est sondé en HTTP.

Le premier démarrage reste en `starting` pendant `PZ_HEALTH_START_PERIOD`
(15 min par défaut), le temps du téléchargement Steam et de la génération de la
carte. Allonge cette valeur si ton serveur est lent, sinon il basculera en
`unhealthy` à tort.

> **Un conteneur `unhealthy` n'est pas redémarré automatiquement.**
> `restart: unless-stopped` réagit au processus qui meurt, pas au healthcheck.
> Le statut sert au diagnostic.

## HTTPS pour le panel

Le panel est en HTTP sur le port 3001 : ne l'expose jamais tel quel sur
Internet. Le profil `proxy` ajoute un [Caddy](https://caddyserver.com/) devant,
qui obtient et renouvelle seul un certificat Let's Encrypt.

**Prérequis** : un nom de domaine pointant vers l'IP publique de la machine, et
les ports **80** et **443** ouverts.

```
CADDY_DOMAIN=pz.mondomaine.fr
PANEL_BIND=127.0.0.1
PANEL_CORS_ORIGINS=https://pz.mondomaine.fr
```

```bash
docker compose --profile proxy up -d
```

Le panel est alors sur `https://pz.mondomaine.fr` et le port 3001 n'est plus
joignable de l'extérieur. Le certificat arrive dans les ~30 s qui suivent le
premier accès ; `docker compose logs -f caddy` si ça coince.

Sans `CADDY_DOMAIN`, Caddy sert le panel en HTTP simple sur le port 80 - utile
pour tester en local, mais **pas** pour une exposition publique.

> Les certificats vivent dans le volume `caddy-data`. Ne le supprime pas :
> Let's Encrypt limite le nombre de certificats émis par semaine et par domaine.

---

# Sécurité

- Ne commit **jamais** ton `.env` (déjà couvert par `.gitignore`).
- N'expose pas le port 3001 directement sur Internet : active Caddy et mets
  `PANEL_BIND=127.0.0.1`.
- Le port RCON n'est pas publié sur l'hôte : il n'est joignable que depuis le
  réseau Docker interne.

# Structure

```
.
├── docker-compose.yml        # le stack complet
├── .env.example              # toute la configuration, commentée
├── server/
│   ├── Dockerfile            # image SteamCMD + PZ B42
│   ├── entrypoint.sh         # install / update Steam, pin de build, UID/GID
│   ├── start-server.sh       # génération du .ini, heap Java, arrêt propre
│   ├── backup-runner.sh      # boucle de backup planifié
│   └── defaults/
│       └── server.ini.template
├── caddy/
│   └── Caddyfile             # reverse proxy HTTPS (profil "proxy")
└── scripts/
    ├── backup.sh             # backup manuel
    └── rcon.sh               # commande RCON en CLI
```

# Crédits

- [Project Zomboid](https://projectzomboid.com/) - The Indie Stone
- [Zomboid Control Panel](https://github.com/fpsacha/zomboid-control-panel) - Sacha Marin

# Licence

MIT - voir [LICENSE](LICENSE).
