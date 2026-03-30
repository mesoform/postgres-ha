FROM golang:1.22-alpine AS builder

ENV WALG_VERSION=v1.1

RUN set -eux; \
    apk add --no-cache \
        git \
        make \
        bash \
        build-base \
        cmake; \
    \
    git clone https://github.com/wal-g/wal-g.git /go/src/wal-g; \
    cd /go/src/wal-g; \
    git checkout $WALG_VERSION; \
    \
    go mod download; \
    go mod tidy; \
    \
    make install; \
    make deps; \
    make pg_build; \
    \
    install main/pg/wal-g /wal-g; \
    /wal-g --help

# -----------------------------
# Runtime image (Postgres base)
# -----------------------------
FROM postgres:14.22-alpine3.23

# Fix CVEs in base Alpine packages where applicable
RUN apk upgrade --no-cache

# Install runtime tools
RUN apk add --no-cache \
    iputils \
    htop \
    curl \
    busybox-suid \
    jq

# Install cronitor
RUN curl -sSL https://cronitor.io/dl/linux_amd64.tar.gz -o /tmp/cronitor.tar.gz \
    && tar xvf /tmp/cronitor.tar.gz -C /usr/bin/ \
    && rm -f /tmp/cronitor.tar.gz

# Copy wal-g binary
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

# Fix cron permissions
RUN chown -R root:postgres /etc/crontabs/root \
    && chmod g+rw /etc/crontabs/root

ENTRYPOINT ["/bin/bash", "/entrypoint.sh"]
CMD ["postgres"]

VOLUME ["/var/run/postgresql", "/usr/share/postgresql/", "/var/lib/postgresql/data", "/tmp"]