FROM golang:1.24-alpine AS builder

ENV WALG_VERSION=v1.1

ENV _build_deps="wget cmake git build-base bash"

RUN set -ex  \
     && apk add --no-cache $_build_deps \
     && git clone https://github.com/wal-g/wal-g/  $GOPATH/src/wal-g \
     && cd $GOPATH/src/wal-g/ \
     && git checkout $WALG_VERSION \
     # Resolves vulnerability CVE-2021-38561 - Out-of-bounds Read
     && go get golang.org/x/text@v0.3.7 \
     # Resolves vulnerabilities CVE-2023-44487, CVE-2021-44716, CVE-2022-41723 & CVE-2022-27664 - Denial of Service (DoS)
     # Resolves vulnerability CVE-2023-45288 & CVE-2023-39325- Allocation of Resources Without Limits or Throttling
     && go get golang.org/x/net/http2@v0.34.0 \
     # Resolves vulnerability CVE-2023-44487 - Denial of Service (DoS)
     && go get google.golang.org/grpc@v1.71.1 \
     # Resolves vulnerability CVE-2025-22868 - Allocation of Resources Without Limits or Throttling
     && go get golang.org/x/oauth2@v0.28.0 \
     # Resolves vulnerability CVE-2024-27304 - SQL Injection \
     && go get github.com/dgrijalva/jwt-go/v4@v4.0.0-preview1 \
     # Resolves vulnerability CVE-2024-45337 - Incorrect Implementation of Authentication Algorithm
     # Resolves vulnerability CVE-2025-22869 - Allocation of Resources Without Limits or Throttling
     # Resolves vulnerability CVE-2020-29652 - NULL Pointer Dereference
     # Resolves vulnerability CVE-2021-43565 - Denial of Service (DoS)
     && go get -u golang.org/x/crypto@v0.35.0 \
     # Update all dependencies safely
     && go mod tidy \
     && go mod download \
     && make install \
     && make deps \
     && make pg_build \
     && install main/pg/wal-g / \
     && /wal-g --help

FROM postgres:14.18-alpine3.21

# Upgrade vulnerable packages libxml2 - icu-data-full - icu-libs
RUN apk upgrade --no-cache libxml2 icu-data-full icu-libs

RUN apk add --update iputils htop curl busybox-suid jq \
    && curl -sOL https://cronitor.io/dl/linux_amd64.tar.gz \
    && tar xvf linux_amd64.tar.gz -C /usr/bin/ \
    && apk upgrade --no-cache libxml2 \
    && apk info -v libxml2

# Copy compiled wal-g binary from builder
COPY --from=builder /wal-g /usr/local/bin

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

# Add cron permissions to postgres user
RUN chown -R root:postgres /etc/crontabs/root \
    && chmod g+rw /etc/crontabs/root

ENTRYPOINT ["/bin/bash", "/entrypoint.sh"]
CMD ["postgres"]

VOLUME ["/var/run/postgresql", "/usr/share/postgresql/", "/var/lib/postgresql/data", "/tmp"]
