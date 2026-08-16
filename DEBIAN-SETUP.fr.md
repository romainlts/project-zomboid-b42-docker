# Préparer un serveur dédié Debian

*[English](DEBIAN-SETUP.md) | **Français***

Ce guide part d'un **serveur Debian nu** - un VPS, une machine dédiée, un PC
chez toi - et l'amène jusqu'au point où tu peux installer ce stack. Il couvre
les mises à jour système, la création d'un utilisateur non privilégié, le
durcissement SSH, le pare-feu UFW et Docker.

Une fois arrivé au bout, enchaîne avec le
[README principal](README.fr.md#1-installation).

Si ton serveur est déjà en place et sécurisé, ce guide ne te sert à rien.

**Cible** : Debian 12 (bookworm) ou 13 (trixie). L'essentiel s'applique aussi à
Ubuntu, à l'exception de l'URL du dépôt Docker.

**Dimensionnement conseillé** : 2 vCPU, **8 Go de RAM** (le serveur alloue
6 Go de heap Java par défaut), 20 Go de disque.

---

## 1. Première connexion et mises à jour

Connecte-toi en `root`, ou avec l'utilisateur fourni par ton hébergeur :

```bash
ssh root@IP_DE_TON_SERVEUR
```

Mets le système à jour avant toute chose :

```bash
apt update && apt upgrade -y
```

Règle le fuseau horaire et le nom de machine, pour des logs lisibles :

```bash
timedatectl set-timezone Europe/Paris
hostnamectl set-hostname pz-server
```

## 2. Créer un utilisateur d'administration

Travailler en `root` par SSH est le moyen le plus courant de perdre un serveur.
Crée un utilisateur normal et donne-lui `sudo` :

```bash
apt install -y sudo
adduser romain
usermod -aG sudo romain
```

`adduser` demande un mot de passe ; les autres champs peuvent rester vides.

Teste le nouveau compte **depuis un second terminal**, sans fermer ta session
actuelle :

```bash
ssh romain@IP_DE_TON_SERVEUR
sudo whoami        # doit afficher : root
```

Ne passe à la suite qu'une fois que ça fonctionne. Tout ce qui suit s'exécute
avec cet utilisateur, via `sudo`.

## 3. Clés SSH et durcissement

### Copier ta clé

Depuis **ta propre machine**, pas depuis le serveur :

```bash
ssh-keygen -t ed25519 -C "pz-server"     # a sauter si tu as deja une cle
ssh-copy-id romain@IP_DE_TON_SERVEUR
```

Sous Windows PowerShell, si `ssh-copy-id` n'existe pas :

```bash
type $env:USERPROFILE\.ssh\id_ed25519.pub | ssh romain@IP_DE_TON_SERVEUR "mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys"
```

Vérifie que `ssh romain@IP_DE_TON_SERVEUR` te connecte désormais **sans
demander de mot de passe**. Ne va pas plus loin tant que ce n'est pas le cas.

### Désactiver la connexion par mot de passe

```bash
sudo nano /etc/ssh/sshd_config
```

Règle ces trois directives :

```
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
```

Puis recharge SSH :

```bash
sudo systemctl restart ssh
```

> Garde ta session en cours ouverte pendant que tu testes une nouvelle
> connexion dans un autre terminal. Si tu te verrouilles dehors, cette session
> ouverte est ton seul moyen de revenir.

## 4. Pare-feu (UFW)

```bash
sudo apt install -y ufw
```

Politique par défaut : tout bloquer en entrée, tout autoriser en sortie.

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
```

**SSH d'abord**, sinon activer le pare-feu coupe ta propre connexion :

```bash
sudo ufw allow OpenSSH
```

Ports du jeu (UDP), nécessaires pour que les joueurs se connectent :

```bash
sudo ufw allow 16261/udp
sudo ufw allow 16262/udp
sudo ufw allow 16263/udp
```

Ports web, **uniquement si** tu comptes utiliser le reverse proxy Caddy :

```bash
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw allow 443/udp
```

Active et vérifie :

```bash
sudo ufw enable
sudo ufw status verbose
```

### Important : Docker contourne UFW

Docker écrit ses propres règles iptables, **avant** celles d'UFW. Un port
publié par un conteneur est donc joignable depuis Internet même si UFW prétend
le bloquer. `sudo ufw deny 3001` ne protégera pas le panel web.

Le stack fournit déjà la bonne réponse : dans ton `.env`, mets

```
PANEL_BIND=127.0.0.1
```

Le panel n'écoute alors que sur la boucle locale, et Docker ne publie rien
publiquement. Pour y accéder, soit tu utilises le profil Caddy - c'est à ça que
servent les règles 80/443 ci-dessus - soit tu passes par un tunnel SSH depuis
ta machine :

```bash
ssh -L 3001:127.0.0.1:3001 romain@IP_DE_TON_SERVEUR
```

puis tu ouvres <http://localhost:3001> en local.

Le port RCON ne demande aucune règle : il n'est jamais publié sur l'hôte, et
n'est joignable que depuis le réseau Docker interne.

## 5. Paquets de base

```bash
sudo apt install -y ca-certificates curl git rsync unzip zip htop
```

- `git` pour cloner ce dépôt
- `rsync` et `unzip`/`zip` pour déplacer sauvegardes et backups
- `htop` pour surveiller la RAM, ce qu'un serveur PZ consomme le plus

## 6. Docker Engine et Compose

Le paquet `docker.io` de Debian est souvent dépassé et livré sans le plugin
`compose`. Utilise le dépôt officiel de Docker.

Ajoute la clé GPG :

```bash
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
```

Ajoute le dépôt :

```bash
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
```

Installe :

```bash
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
```

Autorise ton utilisateur à piloter Docker sans `sudo` :

```bash
sudo usermod -aG docker $USER
```

**Déconnecte-toi et reconnecte-toi** pour que le changement de groupe prenne
effet, puis vérifie :

```bash
docker run --rm hello-world
docker compose version
```

> Appartenir au groupe `docker` équivaut à un accès root sur la machine.
> N'y ajoute que des utilisateurs à qui tu confierais `sudo`.

## 7. Compléments recommandés

### Mises à jour de sécurité automatiques

```bash
sudo apt install -y unattended-upgrades
sudo dpkg-reconfigure -plow unattended-upgrades
```

### Protection contre le bruteforce SSH

```bash
sudo apt install -y fail2ban
sudo systemctl enable --now fail2ban
```

### Swap, si tu as 8 Go de RAM ou moins

Le heap Java est réglé à 6 Go par défaut. Un peu de swap évite que le noyau
tue le serveur lors d'un pic de charge :

```bash
sudo fallocate -l 2G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
```

## 8. Vérifications avant d'installer le stack

```bash
sudo ufw status          # actif, SSH + ports UDP du jeu autorises
docker compose version   # le plugin repond
free -h                  # assez de RAM pour SERVER_MEMORY
df -h /                  # au moins 10 Go libres
id                       # ton utilisateur est dans le groupe docker
```

## 9. Installer le serveur

La machine est prête. Direction le
[README principal, section 1](README.fr.md#1-installation), et reprends au
`git clone`.

Deux réglages à penser dans ton `.env`, compte tenu de ce guide :

```
PANEL_BIND=127.0.0.1
PUID=1000
PGID=1000
```

Vérifie `PUID`/`PGID` avec `id -u` et `id -g`, pour que les fichiers créés par
les conteneurs t'appartiennent.

---

## Récapitulatif des ports

| Port | Protocole | Rôle | Ouvrir dans UFW |
|---|---|---|---|
| 22 | tcp | SSH | oui |
| 16261 | udp | jeu | oui |
| 16262-16263 | udp | requête Steam | oui |
| 80, 443 | tcp/udp | Caddy (HTTPS) | seulement si reverse proxy |
| 3001 | tcp | panel web | **non** - à lier sur la loopback |
| 27015 | tcp | RCON | **non** - interne à Docker |
