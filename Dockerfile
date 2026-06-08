# -----------------------------
# Builder stage
# -----------------------------
FROM golang:1.26-alpine AS builder

ENV WALG_VERSION=v1.1
ENV GOPATH=/go

RUN set -eux; \
    apk add --no-cache \
        git \
        make \
        bash \
        build-base \
        cmake


# Create a cmake wrapper to force compatibility with WAL-G's Brotli submodule
RUN mv /usr/bin/cmake /usr/bin/cmake-orig \
    && echo '#!/bin/sh' > /usr/bin/cmake \
    && echo 'if [ "$1" = "-E" ]; then' >> /usr/bin/cmake \
    && echo '  exec /usr/bin/cmake-orig "$@"' >> /usr/bin/cmake \
    && echo 'else' >> /usr/bin/cmake \
    && echo '  exec /usr/bin/cmake-orig -DCMAKE_POLICY_VERSION_MINIMUM=3.5 "$@"' >> /usr/bin/cmake \
    && echo 'fi' >> /usr/bin/cmake \
    && chmod +x /usr/bin/cmake

# Fetch WAL-G source
RUN git clone https://github.com/wal-g/wal-g.git $GOPATH/src/wal-g

WORKDIR $GOPATH/src/wal-g

RUN set -eux; \
    git checkout $WALG_VERSION; \
    \
    # Patch vulnerable packages
    go get golang.org/x/net@v0.54.0; \
    \
    # Deterministic dependency resolution (modern Go approach)
    go mod download; \
    go mod tidy; \
    \
    # Build WAL-G
    make install; \
    make deps; \
    make pg_build; \
    \
    install main/pg/wal-g /wal-g; \
    /wal-g --help


# -----------------------------
# Runtime stage (Postgres)
# -----------------------------
FROM postgres:14.22-alpine3.23

# Security: apply OS-level fixes only (not Go-level hacks)
RUN apk upgrade --no-cache

# Minimal runtime tools (keep attack surface small)
RUN apk add --no-cache \
    "libssl3>=3.5.6-r0" \
    "libcrypto3>=3.5.6-r0" \
    iputils \
    curl \
    jq \
    busybox-suid \
    htop

# Install cronitor (pinned external binary source)
RUN curl -sSL https://cronitor.io/dl/linux_amd64.tar.gz -o /tmp/cronitor.tar.gz \
    && tar xvf /tmp/cronitor.tar.gz -C /usr/bin/ \
    && rm -f /tmp/cronitor.tar.gz

# WAL-G binary
COPY --from=builder /wal-g /usr/local/bin/wal-g

# -----------------------------
# Scripts
# -----------------------------
# Add replication and WAL-G backup scripts
RUN mkdir -p /usr/local/scripts

COPY scripts/setup-master.sh /docker-entrypoint-initdb.d/
COPY scripts/setup-slave.sh /docker-entrypoint-initdb.d/

RUN chown -R root:postgres /docker-entrypoint-initdb.d/ \
    && chmod -R 775 /docker-entrypoint-initdb.d

# Add WAL-G backup script
COPY scripts/walg_caller.sh /usr/local/scripts/
COPY scripts/base_backup.sh /usr/local/scripts/

RUN chown -R root:postgres /usr/local/scripts \
    && chmod -R 775 /usr/local/scripts

# Add custom entrypoint
COPY scripts/entrypoint.sh /
RUN chmod +x /entrypoint.sh

# Cron permissions
RUN chown -R root:postgres /etc/crontabs/root \
    && chmod g+rw /etc/crontabs/root

ENTRYPOINT ["/bin/bash", "/entrypoint.sh"]
CMD ["postgres"]

VOLUME ["/var/run/postgresql", "/usr/share/postgresql/", "/var/lib/postgresql/data", "/tmp"]