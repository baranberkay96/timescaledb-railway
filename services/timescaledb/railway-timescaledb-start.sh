#!/bin/bash
# railway-timescaledb-start: boots TimescaleDB (PostgreSQL 18) on Railway. Runs as root.
#
#   1. Writes conf.d/50-railway-tuning.conf from the container's memory and CPU
#      limits (every boot, so it follows plan changes). ALTER SYSTEM still wins.
#   2. Creates or renews a self-signed TLS certificate in the volume (TCP proxy
#      clients can use sslmode=require).
#   3. Starts the healthcheck helper on $PORT (pg_isready over TCP).
#   4. Execs the image's docker-entrypoint.sh, which runs initdb on an empty
#      volume (plus /docker-entrypoint-initdb.d: TimescaleDB extension, then
#      zz-railway.sh, which wires in the tuning file).
#
# A bad variable value never stops the start (STANDARD 8.29): it is logged and
# the default is used.
set -uo pipefail
export LC_ALL=C

VOLUME=/var/lib/postgresql/data
CERT_DIR="$VOLUME/certs"
TUNING=/tmp/railway-tuning.conf
export PGDATA="${PGDATA:-$VOLUME/pgdata}"

log() { printf 'railway-timescaledb: %s\n' "$*"; }
is_uint() { [[ "${1:-}" =~ ^[0-9]+$ ]]; }
clamp() { local v=$1; [ "$v" -lt "$2" ] && v=$2; [ "$v" -gt "$3" ] && v=$3; echo "$v"; }

case "$PGDATA" in
  "$VOLUME"/?*) ;;
  *) log "WARNING: PGDATA='${PGDATA}' is not a folder inside ${VOLUME}; using ${VOLUME}/pgdata"; export PGDATA="$VOLUME/pgdata" ;;
esac

# --- 1. tuning ------------------------------------------------------------------
memory_mb() {
  local raw host limit
  if [ -n "${TS_MEMORY_LIMIT_MB:-}" ] && [ "${TS_MEMORY_LIMIT_MB}" != auto ]; then
    if is_uint "$TS_MEMORY_LIMIT_MB" && [ "$TS_MEMORY_LIMIT_MB" -ge 256 ]; then echo "$TS_MEMORY_LIMIT_MB"; return; fi
    log "WARNING: TS_MEMORY_LIMIT_MB='${TS_MEMORY_LIMIT_MB}' is not 'auto' or a whole number >= 256; detecting the limit" >&2
  fi
  host=$(awk '/^MemTotal:/ { printf "%d", $2 / 1024; exit }' /proc/meminfo 2>/dev/null)
  raw=$(cat /sys/fs/cgroup/memory.max 2>/dev/null || echo max)
  if is_uint "$raw"; then limit=$((raw / 1048576)); else limit=${host:-1024}; fi
  if is_uint "$host" && [ "$host" -gt 0 ] && [ "$host" -lt "$limit" ]; then limit=$host; fi
  clamp "$limit" 256 8192
}

cpu_count() {
  local quota period n
  if [ -n "${TS_CPU_LIMIT:-}" ] && [ "${TS_CPU_LIMIT}" != auto ]; then
    if is_uint "$TS_CPU_LIMIT" && [ "$TS_CPU_LIMIT" -ge 1 ]; then clamp "$TS_CPU_LIMIT" 1 64; return; fi
    log "WARNING: TS_CPU_LIMIT='${TS_CPU_LIMIT}' is not 'auto' or a whole number >= 1; detecting the quota" >&2
  fi
  n=$(nproc 2>/dev/null || echo 1)
  if read -r quota period < /sys/fs/cgroup/cpu.max 2>/dev/null && is_uint "$quota" && is_uint "$period" && [ "$period" -gt 0 ]; then
    n=$(((quota + period - 1) / period))
  fi
  clamp "$n" 1 8
}

write_tuning() {
  local m n conns bgw license telemetry
  m=$(memory_mb)
  n=$(cpu_count)
  conns=${TS_MAX_CONNECTIONS:-100}
  if ! is_uint "$conns" || [ "$conns" -lt 10 ]; then
    log "WARNING: TS_MAX_CONNECTIONS='${conns}' is not a whole number >= 10; using 100"
    conns=100
  fi
  bgw=${TS_MAX_BACKGROUND_WORKERS:-16}
  if ! is_uint "$bgw" || [ "$bgw" -lt 1 ]; then
    log "WARNING: TS_MAX_BACKGROUND_WORKERS='${bgw}' is not a whole number >= 1; using 16"
    bgw=16
  fi
  license=${TIMESCALEDB_LICENSE:-timescale}
  case "$license" in
    timescale | apache) ;;
    *) log "WARNING: TIMESCALEDB_LICENSE='${license}' must be timescale or apache; using timescale"; license=timescale ;;
  esac
  case "${TIMESCALEDB_TELEMETRY:-off}" in
    off | basic) telemetry=${TIMESCALEDB_TELEMETRY:-off} ;;
    *) log "WARNING: TIMESCALEDB_TELEMETRY must be off or basic; using off"; telemetry=off ;;
  esac
  if [ "${TS_TUNING:-auto}" = off ]; then
    log "TS_TUNING=off: only licence and telemetry are set; PostgreSQL defaults apply"
    {
      echo "timescaledb.license = '${license}'"
      echo "timescaledb.telemetry_level = '${telemetry}'"
    } > "$TUNING"
    return
  fi
  cat > "$TUNING" <<EOF
# Written by railway-timescaledb at every boot from the service limits:
# ${m} MB memory budget, ${n} CPUs. Do not edit; use ALTER SYSTEM (wins over
# this file) or the TS_* variables and redeploy.
timescaledb.license = '${license}'
timescaledb.telemetry_level = '${telemetry}'
shared_buffers = '$(clamp $((m / 4)) 128 1048576)MB'
effective_cache_size = '$((m * 3 / 4))MB'
maintenance_work_mem = '$(clamp $((m / 16)) 64 2048)MB'
work_mem = '$(clamp $((m / (conns * 3))) 4 64)MB'
max_connections = ${conns}
timescaledb.max_background_workers = ${bgw}
max_worker_processes = $((bgw + n + 3))
max_parallel_workers = ${n}
max_parallel_workers_per_gather = $(clamp $((n / 2)) 1 4)
max_parallel_maintenance_workers = $(clamp $((n / 2)) 1 4)
wal_buffers = '16MB'
min_wal_size = '512MB'
max_wal_size = '$(clamp $((m / 2)) 1024 8192)MB'
checkpoint_completion_target = 0.9
random_page_cost = 1.1
effective_io_concurrency = 200
default_statistics_target = 100
track_io_timing = on
EOF
  log "tuning: ${m} MB, ${n} CPUs, max_connections ${conns}, licence ${license}, telemetry ${telemetry}"
}

write_tuning
chmod 0644 "$TUNING"
if [ -s "$PGDATA/PG_VERSION" ]; then
  install -d -o postgres -g postgres -m 0700 "$PGDATA/conf.d"
  install -o postgres -g postgres -m 0600 "$TUNING" "$PGDATA/conf.d/50-railway-tuning.conf"
  grep -qE "^[[:space:]]*include_dir[[:space:]]*=[[:space:]]*'conf\.d'" "$PGDATA/postgresql.conf" \
    || printf "\n# Added by railway-timescaledb\ninclude_dir = 'conf.d'\n" >> "$PGDATA/postgresql.conf"
fi

# --- 2. TLS certificate ---------------------------------------------------------
days=${SSL_CERT_DAYS:-820}
is_uint "$days" && [ "$days" -ge 30 ] || { log "WARNING: SSL_CERT_DAYS='${days}' is not a whole number >= 30; using 820"; days=820; }
install -d -o postgres -g postgres -m 0700 "$CERT_DIR"
if ! openssl x509 -checkend 2592000 -noout -in "$CERT_DIR/server.crt" >/dev/null 2>&1 || [ ! -s "$CERT_DIR/server.key" ]; then
  log "creating a self-signed TLS certificate valid for ${days} days"
  openssl req -new -x509 -nodes -days "$days" -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \
    -subj "/CN=${RAILWAY_PRIVATE_DOMAIN:-localhost}" \
    -keyout "$CERT_DIR/server.key" -out "$CERT_DIR/server.crt" >/dev/null 2>&1 \
    || log "WARNING: could not create the certificate; TLS stays off"
  chown postgres:postgres "$CERT_DIR"/server.* 2>/dev/null
  chmod 0600 "$CERT_DIR/server.key" 2>/dev/null
fi
SSL_ARGS=()
if [ -s "$CERT_DIR/server.crt" ] && [ -s "$CERT_DIR/server.key" ]; then
  SSL_ARGS=(-c ssl=on -c "ssl_cert_file=$CERT_DIR/server.crt" -c "ssl_key_file=$CERT_DIR/server.key")
fi

# --- 3. healthcheck helper ------------------------------------------------------
python3 /usr/local/lib/railway-timescaledb/railway-healthz.py &

# --- 4. PostgreSQL --------------------------------------------------------------
export NO_TS_TUNE=true  # the image's one-time timescaledb-tune; tuning above runs every boot
# PGHOST/PGPORT are set on this service for Railway's Data tab and other services.
# The entrypoint's init scripts run psql against the local socket and must not
# try the private hostname, which does not resolve before the deploy is healthy.
unset PGHOST PGHOSTADDR PGPORT PGSSLMODE
exec docker-entrypoint.sh postgres -p 5432 -c listen_addresses='*' "${SSL_ARGS[@]}"
