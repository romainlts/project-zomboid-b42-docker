# syntax=docker/dockerfile:1
FROM debian:bookworm-slim

ARG UID=1000
ARG GID=1000

ENV DEBIAN_FRONTEND=noninteractive \
    STEAM_DIR=/opt/steamcmd \
    PZ_DIR=/pz-server \
    ZOMBOID_DIR=/zomboid

# steamcmd est 32 bits -> il faut l'archi i386
RUN dpkg --add-architecture i386 \
 && apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates curl tar bzip2 xz-utils \
      lib32gcc-s1 lib32stdc++6 libstdc++6 libcurl4 \
      procps net-tools locales tzdata gosu rsync \
 && sed -i 's/# en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen && locale-gen \
 && rm -rf /var/lib/apt/lists/*

ENV LANG=en_US.UTF-8

RUN groupadd -g "${GID}" pz \
 && useradd -u "${UID}" -g "${GID}" -m -d /home/pz -s /bin/bash pz \
 && mkdir -p "${STEAM_DIR}" "${PZ_DIR}" "${ZOMBOID_DIR}" \
 && chown -R pz:pz "${STEAM_DIR}" "${PZ_DIR}" "${ZOMBOID_DIR}" /home/pz

# steamcmd
RUN curl -sSL https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz \
      | tar -xz -C "${STEAM_DIR}" \
 && chown -R pz:pz "${STEAM_DIR}"

# client rcon en CLI (gorcon) - utilise par scripts/rcon.sh
ARG RCON_CLI_VERSION=0.10.3
RUN curl -sSL "https://github.com/gorcon/rcon-cli/releases/download/v${RCON_CLI_VERSION}/rcon-${RCON_CLI_VERSION}-amd64_linux.tar.gz" \
      -o /tmp/rcon.tgz \
 && tar -xz -C /tmp -f /tmp/rcon.tgz \
 && install -m 0755 "/tmp/rcon-${RCON_CLI_VERSION}-amd64_linux/rcon" /usr/local/bin/rcon \
 && rm -rf /tmp/rcon.tgz "/tmp/rcon-${RCON_CLI_VERSION}-amd64_linux"

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
COPY start-server.sh /usr/local/bin/start-server.sh
COPY backup-runner.sh /usr/local/bin/backup-runner.sh
COPY defaults/ /opt/pz-defaults/
RUN chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/start-server.sh \
             /usr/local/bin/backup-runner.sh

# game / steam query / rcon
EXPOSE 16261/udp 16262/udp 27015/tcp

WORKDIR ${PZ_DIR}
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["/usr/local/bin/start-server.sh"]
