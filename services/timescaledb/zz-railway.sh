#!/bin/bash
# First boot only (docker-entrypoint-initdb.d, runs as postgres after the
# TimescaleDB extension script): wire in the tuning file written by
# railway-timescaledb-start, and create pg_stat_statements next to timescaledb.
set -e
install -d -m 0700 "$PGDATA/conf.d"
if [ -s /tmp/railway-tuning.conf ]; then
  cp /tmp/railway-tuning.conf "$PGDATA/conf.d/50-railway-tuning.conf"
  chmod 0600 "$PGDATA/conf.d/50-railway-tuning.conf"
fi
grep -qE "^[[:space:]]*include_dir[[:space:]]*=[[:space:]]*'conf\.d'" "$PGDATA/postgresql.conf" \
  || printf "\n# Added by railway-timescaledb\ninclude_dir = 'conf.d'\n" >> "$PGDATA/postgresql.conf"
# pg_stat_statements needs to be preloaded next to timescaledb.
sed -ri "s/^#?[[:space:]]*shared_preload_libraries[[:space:]]*=.*/shared_preload_libraries = 'timescaledb,pg_stat_statements'/" "$PGDATA/postgresql.conf"
psql -v ON_ERROR_STOP=1 --no-psqlrc --username "$POSTGRES_USER" --dbname "${POSTGRES_DB:-$POSTGRES_USER}" \
  -c "CREATE EXTENSION IF NOT EXISTS pg_stat_statements"
echo "railway-timescaledb: tuning file and shared_preload_libraries (timescaledb, pg_stat_statements) set"
