# Deploy and Host TimescaleDB with Railway

TimescaleDB turns PostgreSQL into a time-series database: hypertables partition data by time automatically, native compression shrinks old data, and continuous aggregates keep rollups fresh. This community template runs TimescaleDB 2.32 on PostgreSQL 18 with PgBouncer pooling, TLS for outside connections and daily backups to a Railway Bucket.

## About Hosting TimescaleDB

A production TimescaleDB needs memory settings that match the machine, enough background workers for compression, retention and continuous-aggregate jobs, a connection pooler for many writers, and backups that can actually be restored. This template uses Timescale's official image (which also ships pgvector), writes its tuning file from the service's memory and CPU limits at every boot, enables `pg_stat_statements`, generates a TLS certificate for the TCP proxy, and adds PgBouncer plus a cron job that dumps every database to a Bucket with retention. Restores use Timescale's documented `timescaledb_pre_restore()` / `timescaledb_post_restore()` steps and were tested on Railway.

## Common Use Cases

- IoT and sensor data: millions of readings per day, compressed after a few days and kept for years
- Application, infrastructure and business metrics with Grafana dashboards on continuous aggregates
- Financial tick data, candles and order-book snapshots with `time_bucket()` queries
- Event and log analytics that still need joins with relational data in plain SQL
- A regular PostgreSQL 18 database (with pgvector available) that can grow into time-series workloads

## Dependencies for TimescaleDB Hosting

- TimescaleDB 2.32 on PostgreSQL 18 (included: `timescale/timescaledb:2.32.1-pg18`)
- PgBouncer for connection pooling (included: `edoburu/pgbouncer` 1.26.1)
- A Railway Bucket for backups (included, created by the template)

### Deployment Dependencies

- TimescaleDB documentation: https://docs.timescale.com/
- TimescaleDB source and licences: https://github.com/timescale/timescaledb
- Timescale Docker image: https://github.com/timescale/timescaledb-docker
- PostgreSQL 18 documentation: https://www.postgresql.org/docs/18/
- PgBouncer documentation: https://www.pgbouncer.org/config.html
- Railway Storage Buckets: https://docs.railway.com/storage-buckets

### Implementation Details

| Service | Source | Purpose |
|---|---|---|
| TimescaleDB | built from this repo (`services/timescaledb`, `FROM timescale/timescaledb:2.32.1-pg18`) | PostgreSQL 18 + TimescaleDB + pg_stat_statements, volume at `/var/lib/postgresql/data`, TCP proxy with TLS, healthcheck helper on port 8080 (private) |
| PgBouncer | `edoburu/pgbouncer:v1.26.1-p0` | Transaction pooling on the private network (port 6432, IPv4 and IPv6) |
| TimescaleDB Backup | built from this repo (`services/backup`) | Daily cron (03:15 UTC): roles + every database with `pg_dump`, verified, 14-day retention (at least 3 runs kept) |
| Bucket | Railway Bucket | Private S3 storage for the backups |

**Connection strings** (on the TimescaleDB service, reference them as `${{TimescaleDB.NAME}}`):

- `DATABASE_POOL_URL`: pooled, for application queries from other Railway services
- `DATABASE_URL`: direct, for migrations, bulk `COPY` / `timescaledb-parallel-copy` ingest and `LISTEN/NOTIFY`
- `DATABASE_PUBLIC_URL`: from outside Railway through the TCP proxy, `sslmode=require` (self-signed certificate). Remove the TCP proxy in Settings → Networking for a private-only database.

The usual `PGHOST`, `PGUSER`, `PGPASSWORD` and `PGDATABASE` variables are set too, so Railway's Data tab works.

**First steps**

1. Connect: `psql "{DATABASE_PUBLIC_URL}"` (copy the value from the TimescaleDB service).
2. Create a hypertable: `CREATE TABLE metrics (time timestamptz NOT NULL, device int, value double precision);` then `SELECT create_hypertable('metrics', by_range('time'));`
3. Turn on compression: `ALTER TABLE metrics SET (timescaledb.compress, timescaledb.compress_segmentby = 'device');` and `SELECT add_compression_policy('metrics', INTERVAL '7 days');`
4. Add a continuous aggregate with `CREATE MATERIALIZED VIEW ... WITH (timescaledb.continuous)` and `add_continuous_aggregate_policy`.
5. Create a dedicated role for your app instead of using the `postgres` superuser.

**Tuning**: at every boot the start script writes `conf.d/50-railway-tuning.conf` from the service's memory and CPU limits (auto budget capped at 8 GB / 8 CPUs) and logs the result: `shared_buffers`, `effective_cache_size`, WAL sizes, parallel workers and `timescaledb.max_background_workers` (16). Override any setting with `ALTER SYSTEM`, or set `TS_MEMORY_LIMIT_MB`, `TS_CPU_LIMIT`, `TS_MAX_CONNECTIONS` after resizing. Only memory actually in use is billed.

**Licence note**: TimescaleDB's core is Apache-2.0; compression, continuous aggregates and the job scheduler are under the Timescale License (TSL), which allows running TimescaleDB for your own applications but not offering it to third parties as a hosted database service. `TIMESCALEDB_LICENSE=apache` limits the server to Apache-2.0 features. Telemetry is off by default (`TIMESCALEDB_TELEMETRY`).

**Backups and restore**: dumps land in the Bucket under `timescaledb/{timestamp}/` with a `MANIFEST.txt` that records the TimescaleDB version. Trigger one now with `railway cron run --service "TimescaleDB Backup"`. To restore, set the backup service's start command to `/usr/local/bin/timescaledb-backup restore`, optionally set `RESTORE_RUN`, `RESTORE_DATABASE` and `RESTORE_TARGET`, and run it once; it restores into a new database (`railway_restored` by default) and never overwrites one. Clear the start command afterwards. pg_dump's warnings about circular foreign keys in TimescaleDB's catalog are expected.

**Scaling**: give TimescaleDB more RAM and CPU in its settings, then set `TS_MEMORY_LIMIT_MB` / `TS_CPU_LIMIT` so the tuning follows. Raise `DEFAULT_POOL_SIZE` on PgBouncer for more concurrent queries. Volumes start at 5 GB on Hobby and 50 GB on Pro; compression typically saves 90% or more on time-series data.

**Versions and upgrades**: the image is pinned (TimescaleDB 2.32.1, PostgreSQL 18.7). To upgrade TimescaleDB, change the tag in `services/timescaledb/Dockerfile`, redeploy, then run `ALTER EXTENSION timescaledb UPDATE;` as the first command of a new `psql -X` session in each database. A PostgreSQL major upgrade needs a dump and restore into a new service.

**Plans and cost**: idle use measured on Railway is about 170 MB for TimescaleDB and 15 MB for PgBouncer, so it runs on every plan; expect roughly $2 per month idle and $10–25 per month for a few GB of data with daily backups at Railway's usage prices.

### Why Deploy TimescaleDB on Railway?

Railway runs the database, the pooler and the backup job together on a private network with a persistent volume and a managed bucket, so a production-ready time-series Postgres is running in minutes. Your apps connect with ordinary PostgreSQL drivers, Grafana and BI tools connect through the TLS-protected TCP proxy, and you grow by raising the service limits and the volume size.
