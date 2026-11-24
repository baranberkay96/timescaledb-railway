#!/usr/bin/env python3
"""Healthcheck for Railway: GET /healthz on $PORT answers 200 once PostgreSQL accepts
TCP connections and pg_isready reports it ready, 503 before (initdb, recovery).

PostgreSQL speaks its own protocol on 5432, so Railway's HTTP healthcheck needs
this small endpoint (STANDARD 8.34). It drops to the postgres user and serves
nothing else. Private network only: the service has no public HTTP domain.
"""
import http.server
import os
import pwd
import socket
import subprocess

DEFAULT_PORT = 8080


def port() -> int:
    value = os.environ.get("PORT", "")
    if value.isdigit() and 1 <= int(value) <= 65535:
        return int(value)
    return DEFAULT_PORT


def ready() -> bool:
    try:
        result = subprocess.run(["pg_isready", "-q", "-h", "127.0.0.1", "-p", "5432", "-t", "3"],
                                timeout=10, check=False)
    except (OSError, subprocess.TimeoutExpired):
        return False
    return result.returncode == 0


class Handler(http.server.BaseHTTPRequestHandler):
    server_version = "railway-timescaledb-healthz"
    sys_version = ""

    def do_GET(self) -> None:  # noqa: N802 (http.server naming)
        if self.path.split("?", 1)[0] not in ("/healthz", "/"):
            self.send_error(404)
            return
        ok = ready()
        body = b"ok\n" if ok else b"starting: PostgreSQL is not accepting connections yet\n"
        self.send_response(200 if ok else 503)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(body)

    do_HEAD = do_GET

    def log_message(self, *args) -> None:  # healthchecks would flood the deploy log
        return


class DualStackServer(http.server.ThreadingHTTPServer):
    address_family = socket.AF_INET6
    daemon_threads = True

    def server_bind(self) -> None:
        self.socket.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_V6ONLY, 0)
        super().server_bind()


def drop_privileges() -> None:
    if os.getuid() != 0:
        return
    user = pwd.getpwnam("postgres")
    os.setgroups([])
    os.setgid(user.pw_gid)
    os.setuid(user.pw_uid)


def main() -> None:
    try:
        server = DualStackServer(("::", port()), Handler)
    except OSError:  # no IPv6 in this container
        server = http.server.ThreadingHTTPServer(("0.0.0.0", port()), Handler)
        server.daemon_threads = True
    drop_privileges()
    server.serve_forever()


if __name__ == "__main__":
    main()
