FROM golang:1.15-alpine AS builder

ENV WALG_VERSION=v0.2.19

ENV _build_deps="wget cmake git build-base bash"

RUN set -ex  \
     && apk add --no-cache $_build_deps \
     && git clone https://github.com/wal-g/wal-g/  $GOPATH/src/wal-g \
     && cd $GOPATH/src/wal-g/ \
     && git checkout $WALG_VERSION \
     && make install \
     && make deps \
     && make pg_build \
     && install main/pg/wal-g / \
     && /wal-g --help

FROM postgres:14.3-alpine3.15

RUN apk add --update iputils htop curl busybox-suid \
    && curl -sOL https://cronitor.io/dl/linux_amd64.tar.gz \
    && tar xvf linux_amd64.tar.gz -C /usr/bin/

# Copy compiled wal-g binary from builder
COPY --from=builder /wal-g /usr/local/bin

# Add replication and WAL-G backup scripts
RUN mkdir -p /usr/local/scripts
COPY scripts/setup-master.sh /docker-entrypoint-initdb.d/
COPY scripts/setup-slave.sh /docker-entrypoint-initdb.d/
RUN chown -R root:postgres /docker-entrypoint-initdb.d/
RUN chmod -R 775 /docker-entrypoint-initdb.d

# Add WAL-G backup script
COPY scripts/walg_caller.sh /usr/local/scripts/
COPY scripts/base_backup.sh /usr/local/scripts/
RUN chown -R root:postgres /usr/local/scripts
RUN chmod -R 775 /usr/local/scripts

# Add custom entrypoint
COPY scripts/entrypoint.sh /
RUN chmod +x /entrypoint.sh

# Add cron permissions to postgres user
RUN chown -R root:postgres /etc/crontabs/root
RUN chmod g+rw /etc/crontabs/root

ENTRYPOINT ["/bin/bash", "/entrypoint.sh"]
CMD ["postgres"]

VOLUME ["/var/run/postgresql", "/usr/share/postgresql/", "/var/lib/postgresql/data", "/tmp"]
