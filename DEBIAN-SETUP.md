# Preparing a Debian dedicated server

***English** | [Français](DEBIAN-SETUP.fr.md)*

This guide takes a **bare Debian server** - a VPS, a dedicated box, a machine
at home - and brings it to the point where you can install this stack. It
covers system updates, an unprivileged admin user, SSH hardening, the UFW
firewall, and Docker.

Once you are done here, continue with the [main README](README.md#1-installation).

If your server is already set up and secured, you do not need this guide.

**Target**: Debian 12 (bookworm) or 13 (trixie). Most of it applies to Ubuntu
as well, apart from the Docker repository URL.

**Recommended sizing**: 2 vCPU, **8 GB of RAM** (the server allocates 6 GB of
Java heap by default), 20 GB of disk.

---

## 1. First connection and updates

Connect as `root`, or as the user your host provided:

```bash
ssh root@YOUR_SERVER_IP
```

Bring the system up to date before anything else:

```bash
apt update && apt upgrade -y
```

Set the timezone and hostname, so logs are readable:

```bash
timedatectl set-timezone Europe/Paris
hostnamectl set-hostname pz-server
```

## 2. Create an admin user

Working as `root` over SSH is the single most common way to lose a server.
Create a normal user and give it `sudo`:

```bash
apt install -y sudo
adduser romain
usermod -aG sudo romain
```

`adduser` prompts for a password; the other fields can be left empty.

Test the new account **from a second terminal**, without closing your current
session:

```bash
ssh romain@YOUR_SERVER_IP
sudo whoami        # must print: root
```

Only once that works should you move on. Everything below is run as this user,
with `sudo`.

## 3. SSH keys and hardening

### Copy your key

From **your own machine**, not from the server:

```bash
ssh-keygen -t ed25519 -C "pz-server"     # skip if you already have a key
ssh-copy-id romain@YOUR_SERVER_IP
```

On Windows PowerShell, if `ssh-copy-id` is missing:

```bash
type $env:USERPROFILE\.ssh\id_ed25519.pub | ssh romain@YOUR_SERVER_IP "mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys"
```

Check that `ssh romain@YOUR_SERVER_IP` now connects **without asking for a
password**. Do not go further until it does.

### Disable password login

```bash
sudo nano /etc/ssh/sshd_config
```

Set these three directives:

```
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
```

Then reload SSH:

```bash
sudo systemctl restart ssh
```

> Keep your current session open while you test a new connection in another
> terminal. If you get locked out, that open session is your only way back in.

## 4. Firewall (UFW)

```bash
sudo apt install -y ufw
```

Default policy: block everything inbound, allow everything outbound.

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
```

**SSH first**, otherwise enabling the firewall cuts your own connection:

```bash
sudo ufw allow OpenSSH
```

Game ports (UDP), needed for players to connect:

```bash
sudo ufw allow 16261/udp
sudo ufw allow 16262/udp
sudo ufw allow 16263/udp
```

Web ports, **only if** you plan to use the Caddy reverse proxy:

```bash
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw allow 443/udp
```

Enable and check:

```bash
sudo ufw enable
sudo ufw status verbose
```

### Important: Docker bypasses UFW

Docker writes its own iptables rules, **before** UFW's. A port published by a
container is therefore reachable from the Internet even if UFW claims to deny
it. `sudo ufw deny 3001` will not protect the web panel.

The stack already provides the right answer: in your `.env`, set

```
PANEL_BIND=127.0.0.1
```

The panel is then bound to the loopback interface only, and Docker publishes
nothing publicly. To reach it, either use the Caddy profile - which is what the
80/443 rules above are for - or tunnel over SSH from your own machine:

```bash
ssh -L 3001:127.0.0.1:3001 romain@YOUR_SERVER_IP
```

then open <http://localhost:3001> locally.

The RCON port needs no rule: it is never published on the host, and only
reachable from the internal Docker network.

## 5. Base packages

```bash
sudo apt install -y ca-certificates curl git rsync unzip zip htop
```

- `git` to clone this repository
- `rsync` and `unzip`/`zip` to move saves and backups around
- `htop` to watch RAM, which is what a PZ server consumes most of

## 6. Docker Engine and Compose

Debian's own `docker.io` package is often outdated and ships without the
`compose` plugin. Use Docker's official repository.

Add the GPG key:

```bash
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
```

Add the repository:

```bash
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
```

Install:

```bash
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
```

Let your user drive Docker without `sudo`:

```bash
sudo usermod -aG docker $USER
```

**Log out and back in** for the group change to take effect, then verify:

```bash
docker run --rm hello-world
docker compose version
```

> Being in the `docker` group is equivalent to root access on the machine. Only
> add users you would trust with `sudo`.

## 7. Recommended extras

### Automatic security updates

```bash
sudo apt install -y unattended-upgrades
sudo dpkg-reconfigure -plow unattended-upgrades
```

### Protection against SSH brute force

```bash
sudo apt install -y fail2ban
sudo systemctl enable --now fail2ban
```

### Swap, if you have 8 GB of RAM or less

The Java heap is set to 6 GB by default. A bit of swap avoids the kernel
killing the server during a load spike:

```bash
sudo fallocate -l 2G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
```

## 8. Checklist before installing the stack

```bash
sudo ufw status          # active, SSH + UDP game ports allowed
docker compose version   # the plugin answers
free -h                  # enough RAM for SERVER_MEMORY
df -h /                  # at least 10 GB free
id                       # your user is in the docker group
```

## 9. Install the server

The machine is ready. Head to the
[main README, section 1](README.md#1-installation), and pick up at the
`git clone`.

Two things worth setting in your `.env`, given this guide:

```
PANEL_BIND=127.0.0.1
PUID=1000
PGID=1000
```

Check `PUID`/`PGID` against your actual user with `id -u` and `id -g`, so files
created by the containers belong to you.

---

## Ports summary

| Port | Protocol | Role | Open in UFW |
|---|---|---|---|
| 22 | tcp | SSH | yes |
| 16261 | udp | game | yes |
| 16262-16263 | udp | Steam query | yes |
| 80, 443 | tcp/udp | Caddy (HTTPS) | only if reverse proxy |
| 3001 | tcp | web panel | **no** - bind to loopback |
| 27015 | tcp | RCON | **no** - internal to Docker |
