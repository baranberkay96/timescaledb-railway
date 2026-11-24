# TimescaleDB on PostgreSQL 18 for Railway.
#
# Base: Timescale's official image (Alpine, PostgreSQL 18, TimescaleDB with the
# community (TSL) features, pgvector, timescaledb-tune and -parallel-copy, plus
# the .so files of earlier TimescaleDB releases so ALTER EXTENSION ... UPDATE
# works after an image upgrade). Pinned by tag and digest.
#
# Added here: openssl (self-signed TLS), python3 (healthcheck helper), the start
# script and a first-boot init script. Alpine packages are not version-pinned
# (STANDARD 8.27).
#
# Upgrade: change the tag/digest below, redeploy, then run
#   ALTER EXTENSION timescaledb UPDATE;
# as the first command of a fresh session (psql -X) in every database.
FROM timescale/timescaledb:2.32.1-pg18@sha256:70e6526ad8e31e3f4833f2c5863b50b92d7a6bee4d432ad1f660e2c6dd956d94

RUN apk add --no-cache openssl python3 \
 && postgres --version | grep -q ' 18\.' \
 && ls /usr/local/lib/postgresql/timescaledb-2.32.1.so \
 && test -f /usr/local/share/postgresql/extension/vector.control

COPY --chmod=0755 railway-timescaledb-start.sh /usr/local/bin/railway-timescaledb-start
COPY --chmod=0755 railway-healthz.py /usr/local/lib/railway-timescaledb/railway-healthz.py
COPY --chmod=0755 zz-railway.sh /docker-entrypoint-initdb.d/zz-railway.sh

RUN bash -n /usr/local/bin/railway-timescaledb-start \
 && bash -n /docker-entrypoint-initdb.d/zz-railway.sh \
 && python3 -m py_compile /usr/local/lib/railway-timescaledb/railway-healthz.py

STOPSIGNAL SIGINT
ENTRYPOINT ["/usr/local/bin/railway-timescaledb-start"]
