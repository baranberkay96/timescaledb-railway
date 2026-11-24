# TimescaleDB Backup (Railway cron job): pg_dump 18 + rclone on Alpine.
#
# The PostgreSQL client major must be >= the server's (TimescaleDB runs on
# PostgreSQL 18). When the TimescaleDB service moves to a new PostgreSQL major,
# bump postgresql18-client (and the PATH entry) in the same change.
FROM rclone/rclone:1.76.0@sha256:7cbeec24a44f206067597c0368be4de90ae19a64d5113c7d1938bd737a81e466 AS rclone

FROM alpine:3.24.2@sha256:294b683cb724975bec92580e1e685676bd4b50bda910ddb8c51d4cabeaec77e6

RUN apk add --no-cache bash coreutils ca-certificates postgresql18-client \
 && addgroup -S backup \
 && adduser -S -D -H -h /tmp -G backup backup

COPY --from=rclone /usr/local/bin/rclone /usr/local/bin/rclone

# Alpine links the default client version into /usr/bin; the versioned directory
# comes first so pg_dump is always the 18 client.
ENV PATH="/usr/libexec/postgresql18:${PATH}" \
    HOME=/tmp

COPY --chmod=0755 timescaledb-backup.sh /usr/local/bin/timescaledb-backup

# Fail the build early if a tool is missing or the client is not 18.
RUN pg_dump --version | grep -q ' 18\.' \
 && pg_restore --version >/dev/null \
 && pg_dumpall --version >/dev/null \
 && pg_isready --version >/dev/null \
 && rclone version >/dev/null \
 && date -u -d @0 +%Y >/dev/null \
 && bash -n /usr/local/bin/timescaledb-backup

USER backup
WORKDIR /tmp

ENTRYPOINT ["/usr/local/bin/timescaledb-backup"]
CMD ["backup"]
