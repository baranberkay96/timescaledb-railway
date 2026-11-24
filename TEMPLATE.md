# TimescaleDB 2.32 on PostgreSQL 18: Railway template spec

## Listing

| Field | Value |
|---|---|
| Name | **TimescaleDB 2.32 on PostgreSQL 18** (33 chars) |
| Description | Time-series Postgres with TimescaleDB, PgBouncer and daily backups. (67 chars) |
| Category | Storage |
| Tags | timescaledb, postgres, postgresql, time-series, iot, metrics, pgbouncer, backups |
| Icon | `https://cdn.jsdelivr.net/npm/simple-icons@16/icons/timescale.svg` (200, image/svg+xml; no Timescale icon in homarr dashboard-icons) |

## Base market templates

| Market template | Topology | Kept | Problems fixed |
|---|---|---|---|
| `VSbF5V` "TimescaleDB" (94 active) | `timescale/timescaledb:latest-pg17`, volume, TCP proxy, Railway `PG*` variables, `unset PGHOST` start command | Variable contract, PGDATA subfolder, unsetting `PGHOST` before the entrypoint | Floating `latest` tag, no TLS on the public proxy, no tuning (image's one-time `timescaledb-tune` sizes for the host), no healthcheck, no pooling, no backups |
| `timescaledb-postgis` (Railway's own, 59 active) | `timescale-postgis-ssl:pg16-ts2.13` | TLS idea, `NO_TS_TUNE` | PostgreSQL 16 + TimescaleDB 2.13 (19 minors behind), runs as root, no backups |
| `timescaledb-time-series-db` (8 active) | `timescale/timescaledb:2.18.0-pg16`, telemetry off | Telemetry off by default | Old versions, no TCP proxy or URLs for other services, no healthcheck |

### Improvements over market templates

1. Current TimescaleDB 2.32.1 on PostgreSQL 18.7, pinned by digest; the image keeps older extension `.so` files so `ALTER EXTENSION ... UPDATE` works after upgrades.
2. Boot-time tuning from cgroup memory/CPU (capped 8 GB / 8 CPUs, overridable), rewritten every boot so it follows plan changes; `ALTER SYSTEM` still wins.
3. Self-signed TLS (P-256, 820 days, renewed within 30 days of expiry) for the TCP proxy; `DATABASE_PUBLIC_URL` carries `sslmode=require`.
4. Healthcheck: private `/healthz` on port 8080 backed by `pg_isready` (STANDARD 8.34).
5. `pg_stat_statements` preloaded and created on first boot; telemetry off.
6. PgBouncer (transaction mode, SCRAM, prepared statements, listens on IPv4 **and** IPv6, verified in the deploy log).
7. Daily verified `pg_dump` backups to a Railway Bucket with retention, plus a tested restore command using `timescaledb_pre_restore()` / `timescaledb_post_restore()`.

## Pinned versions (checked 2026-11-24)

| Service | Image / build | Version |
|---|---|---|
| TimescaleDB | repo `services/timescaledb`, `FROM timescale/timescaledb:2.32.1-pg18@sha256:70e6526a…` (built 2026-11-19) + Alpine `openssl`, `python3` | TimescaleDB 2.32.1, PostgreSQL 18.7 (musl) |
| PgBouncer | `edoburu/pgbouncer:v1.26.1-p0` | PgBouncer 1.26.1 |
| TimescaleDB Backup | repo `services/backup`, `alpine:3.24.2` + `postgresql18-client` + rclone 1.76.0 | pg_dump 18.7 |

## Architecture

```
 Apps on Railway ── DATABASE_POOL_URL ──► PgBouncer :6432 ──► TimescaleDB :5432 (private, IPv4+IPv6)
                 ── DATABASE_URL ────────────────────────────►   volume /var/lib/postgresql/data
 External clients ── DATABASE_PUBLIC_URL (TLS) ── TCP proxy ─►   pgdata/ + certs/
 Railway healthcheck ── :8080/healthz (pg_isready) ──────────►   helper in the same container
 TimescaleDB Backup (cron 03:15 UTC) ── pg_dumpall -g + pg_dump -Fc per DB ──► Bucket timescaledb/{run}/
```

## Services

### TimescaleDB

- Source: repo, root `/services/timescaledb`. Entrypoint `railway-timescaledb-start` (root): tuning file, certificate, healthcheck helper (drops to `postgres`), `unset PGHOST PGPORT`, then `docker-entrypoint.sh postgres -p 5432 -c listen_addresses=* -c ssl=on ...`.
- First boot: image init creates the extension in `postgres`, `template1` and `POSTGRES_DB`; `zz-railway.sh` adds `include_dir = 'conf.d'`, `shared_preload_libraries = 'timescaledb,pg_stat_statements'` and creates `pg_stat_statements`.
- Volume `/var/lib/postgresql/data`, `PGDATA=/var/lib/postgresql/data/pgdata`. TCP proxy → 5432. Healthcheck `/healthz`, timeout 600 s. Restart ON_FAILURE ×10. Draining 60 s. `/dev/shm` 1 GiB.
- Bad values (`TS_MEMORY_LIMIT_MB=abc`, unknown licence, PGDATA outside the volume) fall back to defaults with a log line; nothing exits on a variable (8.29).

### PgBouncer

Image service, unchanged from our pgvector template except `LISTEN_ADDR=0.0.0.0,::` (`*` bound IPv4 only in the test log).

### TimescaleDB Backup

Cron `15 3 * * *`, restart NEVER. `backup` (default): globals + `pg_dump -Fc --compress=zstd:3` per database streamed to the Bucket, `pg_restore --list` check, `MANIFEST.txt` last (with TimescaleDB version per DB), retention 14 days / min 3 runs. `restore`: new database only.

## Resources and cost

| Service | Idle RAM (measured) | Typical | Notes |
|---|---|---|---|
| TimescaleDB | 168 MB | 0.5–2 GB (cache grows with data) | shared_buffers is sized from the limit, but only touched pages count |
| PgBouncer | 15 MB | 20–40 MB | |
| TimescaleDB Backup | 0 (runs ~1 min/day) | | |

Idle ≈ 0.19 GB → about $1.90/month RAM + volume ($0.15/GB) + bucket storage. Typical small production use $10–25/month. Fits Trial (1 GB per service) for small datasets; Hobby recommended for real workloads.

## Verification checklist

- [x] All three services SUCCESS on the pre-publish test; `/healthz` passed.
- [x] TLS over the TCP proxy (`pg_stat_ssl`: TLSv1.3), PostgreSQL 18.7, timescaledb 2.32.1, pg_stat_statements loaded, licence `timescale`, telemetry off, tuning applied (shared_buffers 1907 MB on an 8 GB limit, max_worker_processes 27).
- [x] Hypertable created, 25,921 rows inserted, compression enabled, `time_bucket` query, continuous aggregate created and refreshed (802 rows).
- [x] Backup cron run: 2 databases dumped and verified, MANIFEST written, retention ran.
- [x] Restore run: `railway_restored` created with 25,921 rows, 802 aggregate rows, 1 continuous aggregate.
- [x] PgBouncer listening on 0.0.0.0:6432 and [::]:6432.

## Open questions

- PgBouncer has no HTTP healthcheck (image service, same as our published pgvector template); the main service has one.
- pg_dump of TimescaleDB prints "circular foreign-key constraints" warnings for the catalog; expected per Timescale's docs.
