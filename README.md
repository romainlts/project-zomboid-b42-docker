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

# 0. Starting from a bare server?

If you are deploying on a fresh Debian machine - a VPS, a dedicated box, a PC
at home - start with **[Preparing a Debian dedicated server](DEBIAN-SETUP.md)**.
It walks through system updates, an unprivileged admin user, SSH hardening, the
UFW firewall and the Docker installation, then hands over to section 1 below.

Already have a set up and secured server with Docker on it? Skip straight to
section 1.

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
git clone --recurse-submodules https://github.com/romainlts/project-zomboid-b42-docker.git
cd project-zomboid-b42-docker
cp .env.example .env      # Windows PowerShell: Copy-Item .env.example .env
```

> The panel is built from source, vendored as a **git submodule**
> (`panel/upstream`, a fork of `fpsacha/zomboid-control-panel`). The
> `--recurse-submodules` above fetches it. If you cloned without it, run
> `git submodule update --init --recursive` to catch up.

Edit `.env`: **`ADMIN_PASSWORD` and `RCON_PASSWORD` are mandatory**, the stack
refuses to start without them.

```bash
docker compose up -d --build
docker compose logs -f pz-server
```

The first start downloads ~3-5 GB from Steam and then generates the map: expect
**5 to 15 minutes** before the server is reachable.

## Joining from the game

In Project Zomboid: **Join** -> **Favorites** -> **Add server**, then the
machine's address and port `16261`. Use `127.0.0.1` from the machine itself,
its LAN address from another computer on the same network.

Leave the *server password* empty unless you set `SERVER_PASSWORD`.

The game then asks for a **username and password**: those are your player
account, not the server's. With `Open=true` the account is created on first
join, so pick whatever you like. To get in-game admin rights, log in as
`admin` with the `ADMIN_PASSWORD` from your `.env`.

`SERVER_PUBLIC=false` keeps the server out of the public list. Direct
connection is unaffected.

## Adding the server to the panel

Open <http://localhost:3001> and create the panel admin account on first
visit. Then add the server:

1. Keep **Local Server**, and enter the **container** paths: `/zomboid` as
   *Server Data Path*, `/pz-server` as *Server Install Path*. Never the paths
   on your own machine.
2. Click **Detect** before anything else - the panel refuses to add a server it
   has not detected - then enter the RCON password from your `.env`.
3. Set *Min* and *Max Memory* to `SERVER_MEMORY` (6 GB by default), not the 2
   and 4 the form suggests.
4. **Once added, open the card's `...` menu -> Edit Server, and set *RCON Host*
   to `pz-server`.** This step is not optional: the add form does not show the
   field and hardcodes `127.0.0.1`, which inside the panel container points at
   the panel itself. Until you change it, the card shows `RCON Down`.

The card should then read `RCON Up`, and `docker compose logs panel` show
`[RCON] connected to pz-server:27015`.

> Two indicators stay red, and both are harmless. **Test Connection** always
> reports `Unreachable: check host and port`: it probes `127.0.0.1:27015`
> regardless of the host you configured. **Process Down** is expected too - the
> panel looks for the Java process inside its own container and cannot see
> another one. Only the card's `Start` button is inert as a result; the server
> is driven by `docker compose` and its restart policy.

## PanelBridge

PanelBridge is the panel's in-game agent. It covers what RCON cannot do:
teleport, heal, god mode, inventory, character export/import, and the advanced
weather controls. Without it those buttons stay inert, but the server and RCON
work fine.

It is **not a Workshop mod**, so it needs no entry in `Mods` or
`WorkshopItems`. The panel copies a single Lua file straight into the game
files, at `/pz-server/media/lua/server/PanelBridge.lua`, and does it
automatically when you activate the server. The two sides then talk through
files under `/zomboid/Lua/panelbridge/<SERVER_NAME>/`, not over the network,
which is why it works here without extra plumbing: both containers already
share the `zomboid-data` volume.

The order matters:

1. Add and activate the server in the panel, as above. The Lua file is
   installed at that moment.
2. Restart the game server so it loads it:

   ```bash
   docker compose restart pz-server
   ```

`PanelBridge Down` while the server is booting is normal. Once it is up,
`docker compose logs panel` shows:

```
[Bridge] Mod connected (age: 0s, players: 0)
```

Two things worth knowing:

- The Lua file lives in the `pz-install` volume, so it is **not** part of the
  daily backups, which only cover `/zomboid`. That is fine: if you lose that
  volume, the panel reinstalls it on the next activation.
- SteamCMD revalidates the install on every start when `UPDATE_ON_START=true`,
  but it leaves the file alone, since it is not part of the Steam manifest.

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

> Run it **without naming a service**. Variables such as `RCON_PASSWORD` are
> shared by several containers, and `docker compose up -d pz-server` recreates
> that one alone: the panel keeps the old value and its RCON authentication
> fails silently, retrying every 60 s with nothing visible outside the logs.

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

## Freezing the server version

Build 42 is served on the **public** branch, so `PZ_BRANCH` stays empty - that
is what you want. Steam also publishes `legacy41` (Build 41.78.20) and `42.19`
(Build 42.19.1) for this app; there is **no branch for the current 42.20.x**,
and asking for a branch that does not exist makes SteamCMD fail with
`Missing configuration`.

Steam always serves the **latest** build of a branch, and an update
mid-playthrough can break mods. Two things to do about it.

### Stop updating

Install once, then in `.env`:

```
UPDATE_ON_START=false
```

Run `docker compose up -d`. The container no longer calls Steam on startup and
stays on the build already installed. This is the freeze.

To check what you are on:

```bash
docker compose exec pz-server sh -c 'grep buildid /pz-server/steamapps/appmanifest_380870.acf'
```

### Keep a copy of that build

Not updating protects the machine you are on. It does **not** let you rebuild
the same version elsewhere: start from an empty volume six months from now and
Steam hands you whatever is current.

There is no way around that through Steam. Pinning an exact build needs
`download_depot`, and an anonymous account has no depot license - Steam answers
`missing license for depot (No subscription)`. Only an account owning the
license could, which means putting Steam credentials in the `.env`.

So keep the binaries instead:

```bash
./scripts/install-snapshot.sh
```

This archives the `pz-install` volume into `backups/`, with the buildid in the
file name, e.g. `pz-install-24574884-20260816-160000.tar.gz`. It is a few GB.

To restore it on any machine, with the server stopped:

```bash
docker compose stop pz-server
docker run --rm -v pz-b42_pz-install:/pz-server -v "$PWD/backups:/in:ro"   debian:bookworm-slim tar xzf /in/pz-install-24574884-20260816-160000.tar.gz -C /pz-server
docker compose start pz-server
```

Set `UPDATE_ON_START=false` before starting again, otherwise Steam updates the
files you just restored. This is more dependable than a manifest, which the
publisher can unpublish.

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
./scripts/backup.sh               # immediate manual backup of the world
./scripts/install-snapshot.sh     # archive the installed build
```

Shutdown gives the server 120 s to save: do not interrupt a
`docker compose stop`, or the world may be lost.

> `docker compose up -d --build backup` also recreates **pz-server**: both
> services share the same image, and `backup` depends on the server. Rebuilding
> for one restarts the other, which disconnects players. The shutdown stays
> clean (the world is saved), but plan it. To rebuild only the backup service
> without touching a running game, stop it first with
> `docker compose stop backup`.

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

### Blank page behind the proxy

A black screen, with `/assets/*.js` and `.css` answering `500`, means
`PANEL_CORS_ORIGINS` is missing or does not match. The panel rejects unknown
origins before serving anything, so the HTML arrives - the tab even shows the
right title - while no script or stylesheet does.

The panel names the cause in its own logs, so start there rather than with
Caddy, which only relays the error:

```bash
docker compose logs --tail 50 panel
```

```
Error: Origin blocked by panel CORS policy.
```

Then check what the container actually received, which is not always what you
wrote:

```bash
docker compose exec panel printenv CORS_ORIGINS
```

It must match the address in the browser exactly: same scheme, no trailing
slash. Two things silently break the match - an empty value, and a trailing
`\r` from a `.env` saved with CRLF line endings. Both look correct in an
editor. To see the raw bytes:

```bash
docker compose exec panel printenv CORS_ORIGINS | od -c | tail -3
```

`sed -i 's/\r$//' .env` strips the carriage returns. After any change, recreate
the container so it picks the value up:

```bash
docker compose --profile proxy up -d --force-recreate panel
```

---

## Restricting who reaches the panel

A public domain is found and probed by vulnerability scanners within minutes.
`PANEL_ALLOWED_IPS` makes Caddy refuse everything but the addresses you list,
before the panel ever sees the request:

```
PANEL_ALLOWED_IPS=203.0.113.7/32
```

Space-separated CIDRs. Empty means the whole Internet, which is the default.
Find your address with `curl -4 ifconfig.me`.

Only worth it on a stable home IP, since losing it locks you out of the web
panel. The SSH tunnel below always remains as a way back in, so this is
recoverable, not final.

## Docker control, and what it costs

By default the panel cannot see the game process: it looks inside its own
container and finds no Java. The card reads `Process Down`, `Start` does
nothing, and lifecycle actions belong to `docker compose`.

These settings hand the panel real control, which also fixes the indicator:

```
PANEL_BIND=127.0.0.1
PANEL_ALLOWED_IPS=your.ip.here/32
PANEL_DOCKER_CONTROL=true
PANEL_DOCKER_SOCKET=/var/run/docker.sock
PANEL_DOCKER_GID=<stat -c '%g' /var/run/docker.sock>
```

`PANEL_BIND=127.0.0.1` is **required**, not merely advised. Left at `0.0.0.0`,
port 3001 is published straight to the Internet, which bypasses Caddy and
therefore bypasses `PANEL_ALLOWED_IPS` completely - you would believe yourself
restricted while the panel answers the whole world on another port. UFW does
not cover this either: Docker writes its iptables rules upstream of it, so
`ufw deny 3001` has no effect on a published port.

`PANEL_DOCKER_GID` is needed because the panel drops to `PUID:PGID` and the
socket belongs to the host's `docker` group. Without it the socket is mounted
but unreadable: the card reads `Container Down` while RCON reports the server
up, and the logs repeat `connect EACCES /var/run/docker.sock`.

The `pz-server` container already carries the `zomboid-panel.managed=true`
label the panel requires. Finish in the UI: `...` -> Edit Server -> *Docker
Container Name* -> `pz-server`.

Check the result rather than trusting the card - `Stop` must leave the
container stopped, which the old RCON `quit` never managed:

```bash
docker compose logs panel | grep -i dockerclient
docker compose ps
```

> **Understand the trade before enabling it.** The Docker socket is an
> unauthenticated root-level API. Anything that reaches it can create a
> container mounting the host filesystem, and from there own the machine. This
> is normal Docker behaviour, not a vulnerability.
>
> Without it, a panel compromise costs you `db.json`, the RCON password and the
> game world - bad, but bounded, and a backup restores it. With it, the same
> compromise costs you the host: SSH keys, root, persistence.

So enable it only when the panel is **not** reachable from the Internet, either
by narrowing `PANEL_ALLOWED_IPS` to your own address, or by dropping Caddy and
going through an SSH tunnel:

```bash
ssh -L 3001:127.0.0.1:3001 user@your-server
```

with `PANEL_BIND=127.0.0.1`, then browse to `http://localhost:3001`.

A publicly reachable panel *and* a mounted Docker socket is the one combination
to avoid. Either alone is defensible.

# Security

- **Never** commit your `.env` (already covered by `.gitignore`).
- Do not expose port 3001 directly to the Internet: enable Caddy and set
  `PANEL_BIND=127.0.0.1`.
- The RCON port is not published on the host: it is only reachable from the
  internal Docker network.
- Do not mount the Docker socket into a panel that the Internet can reach: see
  the two sections above.

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
    ├── backup.sh             # manual world backup
    ├── install-snapshot.sh   # archive the installed build
    └── rcon.sh               # RCON command from the CLI
```

# Credits

- [Project Zomboid](https://projectzomboid.com/) - The Indie Stone
- [Zomboid Control Panel](https://github.com/fpsacha/zomboid-control-panel) - Sacha Marin

# License

MIT - see [LICENSE](LICENSE).
