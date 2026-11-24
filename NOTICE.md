# NOTICE

This Railway template is a community package. It is not affiliated with or endorsed by Timescale, Inc., the PostgreSQL Global Development Group, the PgBouncer project or Railway.

## What this template runs

| Component | Source | License |
|---|---|---|
| TimescaleDB 2.32.1 (Apache-2.0 core and Timescale License (TSL) community features) | inside `timescale/timescaledb:2.32.1-pg18` (digest `sha256:70e6526a…`), pulled from Docker Hub at build time, not redistributed by this repository | Apache-2.0 (`LICENSE-APACHE`) and Timescale License (`tsl/LICENSE-TIMESCALE`), https://github.com/timescale/timescaledb |
| PostgreSQL 18.7, pgvector, timescaledb-tune, timescaledb-parallel-copy | same image (built `FROM postgres:18-alpine`) | PostgreSQL License; pgvector PostgreSQL License; tools Apache-2.0 |
| Timescale Docker image and its init scripts (`000_install_timescaledb.sh`, `001_timescaledb_tune.sh`) | https://github.com/timescale/timescaledb-docker, used unmodified as the base image | Apache-2.0 |
| PgBouncer 1.26.1 and its container image | `edoburu/pgbouncer:v1.26.1-p0` (https://github.com/edoburu/docker-pgbouncer), used unmodified | ISC (PgBouncer), MIT (image) |
| Alpine packages added at build time | `openssl`, `python3` (TimescaleDB service); `bash`, `coreutils`, `ca-certificates`, `postgresql18-client` (backup) | per package (Apache-2.0, PSF, GPL-3.0-or-later, PostgreSQL License) |
| rclone 1.76.0 | binary copied from `rclone/rclone:1.76.0` | MIT |

**Timescale License.** The TSL permits using TimescaleDB's community features for your own applications, including commercial ones, but not providing TimescaleDB to third parties as a database service (DBaaS). Deploying this template into your own Railway project is self-hosting by you. If you plan to resell database access, set `TIMESCALEDB_LICENSE=apache` or obtain a licence from Timescale. Read the licence text before relying on this summary; it is not legal advice.

## Files written for this template

- `services/timescaledb/Dockerfile`, `railway-timescaledb-start.sh` (boot-time tuning, TLS certificate, healthcheck start), `railway-healthz.py` (pg_isready-based `/healthz`, adapted from our own `153-github-runner` helper) and `zz-railway.sh` (first-boot init hook).
- `services/backup/Dockerfile` and `timescaledb-backup.sh`: adapted from our own `56-pgvector` backup job (written for that template), extended with TimescaleDB versions in the manifest and a pre/post-restore restore command.
- `TEMPLATE.md`, `README.md`, `template.json`, this file.

## Reused or not reused

- The marketplace templates in `../_market/` (`VSbF5V`, `timescaledb-postgis`, `timescaledb-time-series-db`) carry no licence; they were read for settings only (volume layout, `PGDATA` subfolder, `unset PGHOST` before the entrypoint, `NO_TS_TUNE`). No text or files were copied.
- Railway's `timescale-postgis-ssl` image (TimescaleDB 2.13 on PostgreSQL 16) was not used: it is two PostgreSQL majors and nineteen TimescaleDB minors behind.

## Upstream material checked (2026-11-24)

- `timescale/timescaledb-docker` `Dockerfile` (Alpine build, old-version `.so` files copied for in-place upgrades, `shared_preload_libraries` in the sample config) and `docker-entrypoint-initdb.d/000_install_timescaledb.sh` (extension in `postgres`, `template1` and `POSTGRES_DB`; telemetry setting).
- Docker Hub tags for `timescale/timescaledb` (`2.32.1-pg18` built 2026-11-19, newest release tag for PostgreSQL 18).
- TimescaleDB docs: backup and restore with `pg_dump` / `timescaledb_pre_restore()` / `timescaledb_post_restore()`, upgrading with `ALTER EXTENSION timescaledb UPDATE`.
