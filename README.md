# PZ B42 Docker - Project Zomboid Build 42 server + web panel

***English** | [Français](README.fr.md)*

A ready-to-use Docker stack: a dedicated **Project Zomboid Build 42** server
(installed and updated through SteamCMD) plus the
**[Zomboid Control Panel](https://github.com/fpsacha/zomboid-control-panel)**
to administer it from a browser.

| Service | Role | Ports |
|---|---|---|
| `pz-server` | dedicated PZ B42 server | 16261-16263/udp - RCON 27015, internal |
| `panel` | web admin interface | 3001 |
| `backup` | daily world archiving to `./backups` | - |
| `caddy` | HTTPS reverse proxy (optional, `proxy` profile) | 80, 443 |

All services share two volumes (`pz-install`, `zomboid-data`), so the panel can
read the server's configs, mods, logs and saves, and talks to it over RCON on
the internal `pz-net` network.

---

# 1. Installation

## Requirements

- **Docker Desktop** ([Windows/macOS](https://www.docker.com/products/docker-desktop/))
  or **Docker Engine + compose plugin** (Linux)
- ~10 GB of free disk space
- 6 GB of RAM allocated to the server by default (`SERVER_MEMORY`)

**Windows**: Docker Desktop must run on the **WSL2** backend. The stack only
uses named volumes for game data, so there are no permission or disk
performance issues.

**Linux**: set `PUID`/`PGID` to your own user (`id -u`, `id -g`) in the `.env`,
otherwise files created by the container will not belong to you.

## Getting started

```bash
git clone https://github.com/romainlts/project-zomboid-b42-docker.git
cd project-zomboid-b42-docker
cp .env.example .env      # Windows PowerShell: Copy-Item .env.example .env
```

Edit `.env`: **`ADMIN_PASSWORD` and `RCON_PASSWORD` are mandatory**, the stack
refuses to start without them.

```bash
docker compose up -d --build
docker compose logs -f pz-server
```

The first start downloads ~3-5 GB from Steam and then generates the map: expect
**5 to 15 minutes** before the server is reachable.

## First access

- **Game**: join `SERVER_IP:16261`
- **Panel**: <http://localhost:3001> - create the admin account on first visit
- In the panel settings, enter the **container** paths - `/pz-server` and
  `/zomboid` - and definitely not the paths on your own machine

---

# 2. Configuration

Everything is configured through the `.env` file. Each variable is documented
in [`.env.example`](.env.example); the main ones are listed below.

| Variable | Role |
|---|---|
| `ADMIN_PASSWORD` | password of the in-game `admin` account (mandatory) |
| `RCON_PASSWORD` | RCON password, used by the panel (mandatory) |
| `SERVER_NAME` | internal server name, drives the `.ini` and the save folder |
| `SERVER_PUBLIC` / `SERVER_PUBLIC_NAME` | visibility and name in the public list |
| `SERVER_PASSWORD` | password required to join (empty = open) |
| `SERVER_MEMORY` | Java heap, `6g` by default |
| `MAX_PLAYERS` / `PZ_PORT` | concurrent players and game port |
| `TZ`, `PUID`, `PGID` | timezone and system identity |

After any change: `docker compose up -d`.

## `.env` or panel: which one wins?

Both edit the same `Server/<SERVER_NAME>.ini` file. Responsibilities are split
as follows:

| Setting | Source of truth |
|---|---|
| Ports, RCON, PUID/PGID, Java heap, Steam branch | **`.env`** - reapplied on every start |
| `Public`, `PublicName`, `MaxPlayers`, `Password`, `Mods`, `WorkshopItems` | `.env` on **first start**, then **the panel** |
| Sandbox (loot, zombies, weather), players, bans, backups | **the panel** only |

In other words: `.env` bootstraps the server, the panel drives it day to day. A
change made in the web interface is never overwritten on restart.

To force a `.env` value back in - for example to reset the mod list:

```
MOD_IDS=2392709985;2705938086
PZ_FORCE_INI_KEYS=Mods,WorkshopItems
```

Run `docker compose up -d pz-server`, then **clear `PZ_FORCE_INI_KEYS` again** -
otherwise the key would be forced on every restart and the panel could no
longer manage it.

> Sandbox settings do not live in the `.ini` but in `SandboxVars.lua`: they can
> only be changed from the panel.

## Mods

In `.env`:

```
WORKSHOP_IDS=2392709985;2705938086
MOD_IDS=Authentic Z - Current;VISIBLE_BACKPACK_BACKGROUND
```

`WORKSHOP_IDS` lists the Steam Workshop IDs, `MOD_IDS` the internal mod names -
both are required, separated by `;`.

These values are only applied on **first start**. Afterwards, manage mods from
the panel: it also detects conflicts, missing dependencies and load order
issues.

## Pinning the server version

Steam always serves the **latest** build of the `unstable` branch. An update
mid-playthrough can break mods. Two levels of protection.

### Simple - freeze after installation

Install once, then in `.env`:

```
UPDATE_ON_START=false
```

Run `docker compose up -d`. The container no longer calls Steam on startup and
stays on the downloaded build. Good enough for a server among friends.

### Strict - pin by manifest

Reproducible even on a fresh machine or after losing the volume. Preferred in
production, or with mods that are sensitive to the game version.

On [SteamDB - depots for 380870](https://steamdb.info/app/380870/depots/):

1. open the **Linux dedicated server** depot and note its **Depot ID**;
2. in the *Manifests* tab, pick the `unstable` branch and the build you want,
   then note the **Manifest ID** (a long number).

In `.env`:

```
PZ_DEPOT_ID=<DEPOT_ID>
PZ_MANIFEST_ID=<MANIFEST_ID>
PZ_PIN_STRICT=true
```

The server then downloads that exact build. Worth knowing:

- pinning **takes precedence over `UPDATE_ON_START`**: the build never moves on
  its own;
- on later starts nothing is downloaded again if the build is already correct;
- to change version, change `PZ_MANIFEST_ID` and restart; to go back to
  following the branch, clear the variable.

With `PZ_PIN_STRICT=true` (the default), if Steam refuses the download the
container **stops** instead of installing a different build - a server that
does not start beats a server on the wrong version. Set `PZ_PIN_STRICT=false`
to allow falling back to the latest build.

To check the installed build:

```bash
docker compose exec pz-server sh -c 'grep buildid /pz-server/steamapps/appmanifest_380870.acf'
```

---

# 3. Usage

## Common commands

```bash
docker compose up -d --build      # (re)build and start
docker compose stop pz-server     # clean shutdown (saves the world)
docker compose logs -f pz-server  # follow the logs
docker compose ps                 # service state and health
docker compose exec pz-server bash
./scripts/rcon.sh players         # RCON command from the CLI
./scripts/backup.sh               # immediate manual backup
```

Shutdown gives the server 120 s to save: do not interrupt a
`docker compose stop`, or the world may be lost.

The server runs with `restart: unless-stopped`: a `quit` sent over RCON from
the panel stops the process and Docker restarts the container - that is how the
web interface "restart" button works.

## Automatic backups

A `backup` service archives the world **every day** into `./backups/`. It is
enabled by default, nothing to start.

```
BACKUP_AT=04:00        # daily time (in the .env timezone)
BACKUP_KEEP=7          # archives kept, the oldest ones are pruned
BACKUP_ON_START=false  # true = back up immediately on startup, to test
```

Before each archive the service sends an RCON `save` and waits 15 s so that the
world on disk is consistent. If the server is stopped or unreachable it still
archives, and says so in the logs.

The archive holds `Saves/` and `Server/` - not the ~5 GB Steam installation,
which SteamCMD can download again. It is written as `.part` and then renamed,
so any `pz-backup-*.tar.gz` file you can see is always complete.

```bash
docker compose logs -f backup
ls -lh backups/
```

To **restore**, the panel is the easiest route (Backups tab). Otherwise, with
the server stopped:

```bash
docker compose stop pz-server
docker run --rm -v pz-b42_zomboid-data:/zomboid -v "$PWD/backups:/in:ro" \
  debian:bookworm-slim tar xzf /in/pz-backup-YYYYMMDD-HHMMSS.tar.gz -C /zomboid
docker compose start pz-server
```

## Health status

```bash
docker compose ps          # STATUS column: healthy / unhealthy / starting
```

`pz-server` is probed with an **RCON request**, not by merely checking that a
process exists: a server stuck in garbage collection, or hung while loading a
mod, correctly shows up as `unhealthy`. The panel is probed over HTTP.

The first start stays in `starting` for `PZ_HEALTH_START_PERIOD` (15 min by
default), covering the Steam download and map generation. Raise that value if
your server is slow to boot, otherwise it will wrongly flip to `unhealthy`.

> **An `unhealthy` container is not restarted automatically.**
> `restart: unless-stopped` reacts to the process dying, not to the
> healthcheck. The status is for diagnostics.

## HTTPS for the panel

The panel serves plain HTTP on port 3001: never expose it to the Internet as
is. The `proxy` profile puts a [Caddy](https://caddyserver.com/) in front,
which obtains and renews a Let's Encrypt certificate on its own.

**Requirements**: a domain name pointing at the machine's public IP, and ports
**80** and **443** open.

```
CADDY_DOMAIN=pz.mydomain.com
PANEL_BIND=127.0.0.1
PANEL_CORS_ORIGINS=https://pz.mydomain.com
```

```bash
docker compose --profile proxy up -d
```

The panel is then served at `https://pz.mydomain.com` and port 3001 is no
longer reachable from outside. The certificate arrives within ~30 s of the
first request; use `docker compose logs -f caddy` if it stalls.

Without `CADDY_DOMAIN`, Caddy serves the panel over plain HTTP on port 80 -
handy for local testing, but **not** for public exposure.

> Certificates live in the `caddy-data` volume. Do not delete it: Let's Encrypt
> rate-limits how many certificates it issues per domain per week.

---

# Security

- **Never** commit your `.env` (already covered by `.gitignore`).
- Do not expose port 3001 directly to the Internet: enable Caddy and set
  `PANEL_BIND=127.0.0.1`.
- The RCON port is not published on the host: it is only reachable from the
  internal Docker network.

# Layout

```
.
├── docker-compose.yml        # the whole stack
├── .env.example              # all configuration, commented
├── server/
│   ├── Dockerfile            # SteamCMD + PZ B42 image
│   ├── entrypoint.sh         # Steam install/update, build pinning, UID/GID
│   ├── start-server.sh       # .ini generation, Java heap, clean shutdown
│   ├── backup-runner.sh      # scheduled backup loop
│   └── defaults/
│       └── server.ini.template
├── caddy/
│   └── Caddyfile             # HTTPS reverse proxy ("proxy" profile)
└── scripts/
    ├── backup.sh             # manual backup
    └── rcon.sh               # RCON command from the CLI
```

# Credits

- [Project Zomboid](https://projectzomboid.com/) - The Indie Stone
- [Zomboid Control Panel](https://github.com/fpsacha/zomboid-control-panel) - Sacha Marin

# License

MIT - see [LICENSE](LICENSE).
