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

## Rejoindre depuis le jeu

Dans Project Zomboid : **Jouer en ligne** -> **Favoris** -> **Ajouter un
serveur**, puis l'adresse de la machine et le port `16261`. Depuis la machine
elle-même, `127.0.0.1` ; depuis un autre PC du réseau, son adresse LAN.

Laisse le *mot de passe du serveur* vide, sauf si tu as renseigné
`SERVER_PASSWORD`.

Le jeu demande ensuite un **nom d'utilisateur et un mot de passe** : ce sont
ceux de ton compte joueur, pas ceux du serveur. Avec `Open=true` le compte se
crée à la première connexion, choisis ce que tu veux. Pour les droits admin
in-game, connecte-toi en `admin` avec le `ADMIN_PASSWORD` de ton `.env`.

`SERVER_PUBLIC=false` garde le serveur hors de la liste publique, sans effet
sur la connexion directe.

## Ajouter le serveur au panel

Ouvre <http://localhost:3001> et crée le compte admin du panel au premier
accès. Puis ajoute le serveur :

1. Reste sur **Local Server** et saisis les chemins **conteneur** : `/zomboid`
   en *Server Data Path*, `/pz-server` en *Server Install Path*. Jamais les
   chemins de ton PC.
2. Clique **Detect** avant tout - le panel refuse d'ajouter un serveur qu'il
   n'a pas détecté - puis saisis le mot de passe RCON de ton `.env`.
3. Règle *Min* et *Max Memory* sur `SERVER_MEMORY` (6 Go par défaut), et non
   sur les 2 et 4 proposés.
4. **Une fois ajouté, ouvre le menu `...` de la carte -> Edit Server, et mets
   *RCON Host* à `pz-server`.** Cette étape n'est pas optionnelle : le
   formulaire d'ajout ne montre pas ce champ et code en dur `127.0.0.1`, qui
   depuis le conteneur du panel le désigne lui-même. Tant que tu ne l'as pas
   changé, la carte affiche `RCON Down`.

La carte doit alors afficher `RCON Up`, et `docker compose logs panel` montrer
`[RCON] connected to pz-server:27015`.

> Deux indicateurs restent rouges, sans gravité. **Test Connection** signale
> toujours `Unreachable: check host and port` : il sonde `127.0.0.1:27015`
> quelle que soit l'adresse configurée. **Process Down** est attendu aussi - le
> panel cherche le processus Java dans son propre conteneur et ne peut pas en
> voir un autre. Seul le bouton `Start` de la carte est donc inopérant ; le
> serveur est piloté par `docker compose` et sa politique de redémarrage.

## PanelBridge

PanelBridge est l'agent en jeu du panel. Il couvre ce que RCON ne sait pas
faire : téléportation, soin, mode dieu, inventaire, export/import de
personnage, et les contrôles météo avancés. Sans lui ces boutons restent
inopérants, mais le serveur et RCON fonctionnent normalement.

Ce n'est **pas un mod Workshop** : il n'a donc rien à faire dans `Mods` ni
`WorkshopItems`. Le panel copie un unique fichier Lua directement dans les
fichiers du jeu, à `/pz-server/media/lua/server/PanelBridge.lua`, et le fait
automatiquement quand tu actives le serveur. Les deux côtés dialoguent ensuite
par fichiers sous `/zomboid/Lua/panelbridge/<SERVER_NAME>/`, et non par le
réseau, ce qui explique que ça fonctionne ici sans plomberie supplémentaire :
les deux conteneurs partagent déjà le volume `zomboid-data`.

L'ordre compte :

1. Ajoute et active le serveur dans le panel, comme ci-dessus. Le fichier Lua
   est installé à ce moment-là.
2. Redémarre le serveur de jeu pour qu'il le charge :

   ```bash
   docker compose restart pz-server
   ```

`PanelBridge Down` pendant le démarrage du serveur est normal. Une fois lancé,
`docker compose logs panel` affiche :

```
[Bridge] Mod connected (age: 0s, players: 0)
```

Deux points à connaître :

- Le fichier Lua vit dans le volume `pz-install` : il n'est donc **pas** dans
  les sauvegardes quotidiennes, qui ne couvrent que `/zomboid`. Ce n'est pas
  grave : si tu perds ce volume, le panel le réinstalle à la prochaine
  activation.
- SteamCMD revalide l'installation à chaque démarrage quand
  `UPDATE_ON_START=true`, mais il ne touche pas au fichier, qui ne fait pas
  partie du manifeste Steam.

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

> Lance-le **sans nommer de service**. Des variables comme `RCON_PASSWORD` sont
> partagées par plusieurs conteneurs, et `docker compose up -d pz-server` ne
> recrée que celui-là : le panel garde l'ancienne valeur et son authentification
> RCON échoue silencieusement, avec une nouvelle tentative toutes les 60 s
> invisible ailleurs que dans les logs.

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

Build 42 est servi sur la branche **publique**, donc `PZ_BRANCH` reste vide -
c'est ce qu'il faut. Steam publie aussi `legacy41` (Build 41.78.20) et `42.19`
(Build 42.19.1) pour cette app ; il n'existe **aucune branche pour la 42.20.x
actuelle**, et demander une branche inexistante fait échouer SteamCMD avec
`Missing configuration`.

Steam sert toujours la **dernière** build d'une branche, et une mise à jour en
cours de partie peut casser des mods. Deux choses à faire.

### Arrêter les mises à jour

Installe une fois, puis dans `.env` :

```
UPDATE_ON_START=false
```

`docker compose up -d`. Le conteneur ne rappelle plus Steam au démarrage et
reste sur la build déjà installée. C'est le gel.

Pour savoir où tu en es :

```bash
docker compose exec pz-server sh -c 'grep buildid /pz-server/steamapps/appmanifest_380870.acf'
```

### Garder une copie de cette build

Ne plus mettre à jour protège la machine sur laquelle tu es. Ça ne te permet
**pas** de reconstruire la même version ailleurs : repars d'un volume vide dans
six mois et Steam te donnera ce qui est courant à ce moment-là.

Il n'y a pas de contournement côté Steam. Figer une build exacte demande
`download_depot`, et un compte anonyme n'a aucune licence de depot - Steam
répond `missing license for depot (No subscription)`. Seul un compte
propriétaire de la licence le pourrait, ce qui impliquerait de mettre des
identifiants Steam dans le `.env`.

Garde donc les binaires :

```bash
./scripts/install-snapshot.sh
```

Le script archive le volume `pz-install` dans `backups/`, avec le buildid dans
le nom du fichier, par exemple `pz-install-24574884-20260816-160000.tar.gz`.
Ça pèse quelques Go.

Pour restaurer sur n'importe quelle machine, serveur arrêté :

```bash
docker compose stop pz-server
docker run --rm -v pz-b42_pz-install:/pz-server -v "$PWD/backups:/in:ro"   debian:bookworm-slim tar xzf /in/pz-install-24574884-20260816-160000.tar.gz -C /pz-server
docker compose start pz-server
```

Mets `UPDATE_ON_START=false` avant de redémarrer, sinon Steam met à jour les
fichiers que tu viens de restaurer. C'est plus fiable qu'un manifest, que
l'éditeur peut dépublier.

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
./scripts/backup.sh               # backup manuel immédiat du monde
./scripts/install-snapshot.sh     # archive la build installée
```

L'arrêt laisse 120 s au serveur pour sauvegarder : n'interromps pas un
`docker compose stop`, sinon le monde peut être perdu.

> `docker compose up -d --build backup` recrée **aussi pz-server** : les deux
> services partagent la même image, et `backup` dépend du serveur. Reconstruire
> pour l'un redémarre l'autre, ce qui déconnecte les joueurs. L'arrêt reste
> propre (le monde est sauvegardé), mais c'est à anticiper. Pour reconstruire
> le seul service de backup sans toucher à une partie en cours, arrête-le
> d'abord avec `docker compose stop backup`.

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

### Page blanche derrière le proxy

Un écran noir, avec les `/assets/*.js` et `.css` qui répondent `500`, signifie
que `PANEL_CORS_ORIGINS` est absent ou ne correspond pas. Le panel rejette les
origines inconnues avant de servir quoi que ce soit : le HTML arrive - l'onglet
affiche même le bon titre - mais aucun script ni feuille de style.

Le panel nomme lui-même la cause dans ses logs : commence par là plutôt que par
Caddy, qui ne fait que relayer l'erreur.

```bash
docker compose logs --tail 50 panel
```

```
Error: Origin blocked by panel CORS policy.
```

Vérifie ensuite ce que le conteneur a réellement reçu, qui n'est pas toujours
ce que tu as écrit :

```bash
docker compose exec panel printenv CORS_ORIGINS
```

La valeur doit correspondre exactement à l'adresse du navigateur : même schéma,
pas de slash final. Deux choses cassent silencieusement la correspondance - une
valeur vide, et un `\r` final venant d'un `.env` enregistré en CRLF. Les deux
paraissent corrects dans un éditeur. Pour voir les octets bruts :

```bash
docker compose exec panel printenv CORS_ORIGINS | od -c | tail -3
```

`sed -i 's/\r$//' .env` supprime les retours chariot. Après toute
modification, recrée le conteneur pour qu'il prenne la valeur en compte :

```bash
docker compose --profile proxy up -d --force-recreate panel
```

---

## Restreindre l'accès au panel

Un domaine public est découvert et sondé par des scanners de vulnérabilités en
quelques minutes. `PANEL_ALLOWED_IPS` fait refuser par Caddy tout ce qui ne
vient pas des adresses listées, avant même que le panel ne voie la requête :

```
PANEL_ALLOWED_IPS=203.0.113.7/32
```

Des CIDR séparés par des espaces. Vide signifie tout Internet, ce qui est le
défaut. Trouve ton adresse avec `curl -4 ifconfig.me`.

Utile seulement si ton IP domestique est stable, puisque la perdre te ferme le
panel web. Le tunnel SSH ci-dessous reste toujours une porte de secours : c'est
donc récupérable, pas définitif.

## Le contrôle Docker, et ce qu'il coûte

Par défaut le panel ne voit pas le processus du jeu : il cherche dans son
propre conteneur et n'y trouve aucun Java. La carte affiche `Process Down`,
`Start` est inerte, et le cycle de vie appartient à `docker compose`.

Deux réglages donnent au panel un vrai contrôle, ce qui corrige aussi
l'indicateur :

```
PANEL_DOCKER_CONTROL=true
PANEL_DOCKER_SOCKET=/var/run/docker.sock
```

Le conteneur `pz-server` porte déjà le label `zomboid-panel.managed=true` exigé
par le panel. Termine dans l'interface : `...` -> Edit Server -> *Docker
Container Name* -> `pz-server`.

> **Comprends l'échange avant d'activer.** Le socket Docker est une API root
> sans authentification. Tout ce qui l'atteint peut créer un conteneur montant
> le disque de l'hôte, et de là posséder la machine. C'est le fonctionnement
> normal de Docker, pas une faille.
>
> Sans lui, une compromission du panel te coûte `db.json`, le mot de passe RCON
> et le monde de jeu - grave, mais borné, et un backup te remet d'aplomb. Avec
> lui, la même compromission te coûte l'hôte : clés SSH, root, persistance.

Ne l'active donc que si le panel n'est **pas** joignable depuis Internet, soit
en restreignant `PANEL_ALLOWED_IPS` à ton adresse, soit en abandonnant Caddy au
profit d'un tunnel SSH :

```bash
ssh -L 3001:127.0.0.1:3001 user@ton-serveur
```

avec `PANEL_BIND=127.0.0.1`, puis `http://localhost:3001` dans le navigateur.

Un panel joignable publiquement **et** un socket Docker monté est la seule
combinaison à éviter. Chacun pris séparément se défend.

# Sécurité

- Ne commit **jamais** ton `.env` (déjà couvert par `.gitignore`).
- N'expose pas le port 3001 directement sur Internet : active Caddy et mets
  `PANEL_BIND=127.0.0.1`.
- Le port RCON n'est pas publié sur l'hôte : il n'est joignable que depuis le
  réseau Docker interne.
- Ne monte pas le socket Docker dans un panel joignable depuis Internet : voir
  les deux sections ci-dessus.

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
    ├── backup.sh             # backup manuel du monde
    ├── install-snapshot.sh   # archive la build installée
    └── rcon.sh               # commande RCON en CLI
```

# Crédits

- [Project Zomboid](https://projectzomboid.com/) - The Indie Stone
- [Zomboid Control Panel](https://github.com/fpsacha/zomboid-control-panel) - Sacha Marin

# Licence

MIT - voir [LICENSE](LICENSE).
