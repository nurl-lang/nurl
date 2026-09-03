#!/usr/bin/env python3
# bench/gen_http3_results.py — render bench/HTTP3_RESULTS.md from the flat
# measurement rows bench/run_http3.sh feeds on stdin. Not meant to be run
# by hand; run_http3.sh drives it and overwrites HTTP3_RESULTS.md with the
# result, the same way run_http2.sh generates HTTP2_RESULTS.md.
#
# Input (on stdin):
#   ENV<TAB>key<TAB>value              one per environment field
#   ROW name c m rps p50 p99 mean      one per HTTP/3 closed-loop cell
#   REF proto c rps p50 p99 mean       NURL HTTP/2 (h2) reference cell (M=1)
#   CONN proto cps                     NURL connection setups per second, proto = h3|h2
#   CONNPEER name cps                  a peer's HTTP/3 connection setups per second
# name is nurl|rust; numeric fields are numbers or the literal "n/a" /
# "FAIL". Latencies are in ms; `mean` is the mean latency in ms used for
# the effective-concurrency (Little's-law) check.

import sys

SERVERS = [("nurl", "NURL"), ("rust", "Rust")]
DAGGER = "‡"


def num(v):
    try:
        return float(v)
    except (TypeError, ValueError):
        return None


def main():
    env = {}
    cells = {}
    ref = {}
    conn = {}
    connpeer = {}
    for line in sys.stdin:
        line = line.rstrip("\n")
        if line.startswith("ENV\t"):
            parts = line.split("\t")
            if len(parts) >= 3:
                env[parts[1]] = "\t".join(parts[2:])
        elif line.startswith("ROW "):
            f = line.split()[1:]
            if len(f) == 7:
                name, c, m, rps, p50, p99, mean = f
                cells[(name, c, m)] = (rps, p50, p99, mean)
        elif line.startswith("REF "):
            f = line.split()[1:]
            if len(f) == 6:
                proto, c, rps, p50, p99, mean = f
                ref[(proto, c)] = (rps, p50, p99, mean)
        elif line.startswith("CONN "):
            f = line.split()[1:]
            if len(f) == 2:
                conn[f[0]] = f[1]
        elif line.startswith("CONNPEER "):
            f = line.split()[1:]
            if len(f) == 2:
                connpeer[f[0]] = f[1]

    cell_specs = env.get("cells", "1x1 1x10 1x100 10x1 10x10 50x1 50x10").split()
    cell_keys = [tuple(s.split("x")) for s in cell_specs]

    def starved(name, c, m):
        cell = cells.get((name, c, m))
        if not cell:
            return False
        rps, _, _, mean = cell
        r, mm = num(rps), num(mean)
        if r is None or mm is None:
            return False
        n_eff = r * (mm / 1000.0)
        try:
            offered = float(c) * float(m)
        except ValueError:
            return False
        return n_eff < 0.9 * offered and (offered - n_eff) >= 2.0

    def n_eff_of(name, c, m):
        rps, _, _, mean = cells[(name, c, m)]
        return num(rps) * (num(mean) / 1000.0)

    def fmt_rps(v):
        n = num(v)
        return v if n is None else f"{int(round(n)):,}".replace(",", " ")

    def fmt_lat(v):
        n = num(v)
        return v if n is None else f"{n:.2f}"

    def best(values, want_max):
        present = [num(v) for v in values]
        present = [x for x in present if x is not None]
        return (max(present) if want_max else min(present)) if present else None

    out = []
    w = out.append

    w("# NURL HTTP/3-server peer-comparison\n")
    w(
        f"Generated `{env.get('now','')}` by `bench/run_http3.sh`. "
        "**Do not edit by hand** — the next run overwrites it."
    )
    w("")
    w(
        "The HTTP/3 companion of [`HTTP_RESULTS.md`](HTTP_RESULTS.md) (HTTP/1.1) "
        "and [`HTTP2_RESULTS.md`](HTTP2_RESULTS.md) (HTTP/2), which stay as they "
        "are. Each implementation terminates QUIC (RFC 9000/9001/9002) on a "
        "UDP socket, speaks HTTP/3 (RFC 9114 + QPACK, RFC 9204) and answers "
        "every request on every stream with the same 14-byte "
        "`Hello, World!\\n` body (`text/plain`), over a self-signed EC (P-256) "
        "certificate the generator accepts without verification."
    )
    w("")
    w(
        "The NURL server is `bench/http_server.nu` **unchanged from the "
        "HTTP/1.1 and HTTP/2 benchmarks**: the `packages/http` HttpApp "
        "facade's TLS listener also binds its port over UDP and serves "
        "HTTP/3 there through the same routes; the QUIC transport, the TLS "
        "1.3 handshake inside it, QPACK and the HTTP/3 framing are all pure "
        "NURL. The Rust peer is `quinn` + `h3` (`h3-quinn`) on tokio with "
        "rustls — the stack behind most Rust HTTP/3 servers."
    )
    w("")
    w(
        "**Cells are `C x M`: C client connections, each with M concurrent "
        "streams** (`h2load --h3 -c C -m M`), so C x M requests are in "
        "flight. The same closed-loop caveat as the HTTP/2 report applies: "
        "at high in-flight counts read `req/s`, not the latency columns; "
        f"cells whose effective concurrency (`req/s x mean-latency`) falls "
        f"well short of C x M are marked {DAGGER} and left un-bold."
    )
    w("")

    w("## Environment\n")
    w("| Item | Value |")
    w("|---|---|")
    w(f"| Host | `{env.get('host','')}` |")
    w(f"| Kernel | `{env.get('kernel','')}` |")
    w(f"| CPU | {env.get('cpu','')} ({env.get('cores','?')} logical cores) |")
    w(f"| Memory | {env.get('mem_kb','?')} KiB |")
    w(f"| Commit | `{env.get('commit','')}` |")
    if env.get("run_url"):
        w(f"| CI run | {env['run_url']} |")
    w(f"| NURL | `{env.get('nurl','')}` |")
    w(f"| Rust | {env.get('rust','')} |")
    w(f"| Load generator | {env.get('h2load','')} |")
    w("")
    w("| Setting | Value |")
    w("|---|---|")
    w(
        f"| Throughput/latency | median of {env.get('iters','3')} x "
        f"{env.get('duration','10')} s closed-loop runs |"
    )
    w(f"| Cells (C x M) | {' , '.join(cell_specs)} |")
    w(f"| Connection setup | {env.get('conn_burst','100')} fresh connections, one request each, median of {env.get('iters','3')} runs |")
    w("| TLS cert | self-signed EC P-256, `CN=localhost`, ALPN `h3` |")
    w("")

    w("## 1. HTTP/3 over QUIC\n")
    header = "|              | Server  | " + " | ".join(f"{c} x {m}" for c, m in cell_keys) + " |"
    sep = "|--------------|---------|" + "|".join(["--------:"] * len(cell_keys)) + "|"
    rows = []
    for metric_label, idx, want_max, fmt, is_lat in (
        ("**req/s**", 0, True, fmt_rps, False),
        ("**p50 (ms)**", 1, False, fmt_lat, True),
        ("**p99 (ms)**", 2, False, fmt_lat, True),
    ):
        col_best = {}
        for c, m in cell_keys:
            vals = []
            for name, _ in SERVERS:
                if is_lat and starved(name, c, m):
                    continue
                cell = cells.get((name, c, m))
                if cell:
                    vals.append(cell[idx])
            col_best[(c, m)] = best(vals, want_max)
        for si, (name, disp) in enumerate(SERVERS):
            left = metric_label if si == 0 else ""
            out_cells = []
            for c, m in cell_keys:
                cell = cells.get((name, c, m), ("n/a", "n/a", "n/a", "n/a"))
                raw = cell[idx]
                txt = fmt(raw)
                n = num(raw)
                st = is_lat and starved(name, c, m)
                if st:
                    txt = f"{txt}{DAGGER}"
                elif n is not None and col_best[(c, m)] is not None and abs(n - col_best[(c, m)]) < 1e-9:
                    txt = f"**{txt}**"
                out_cells.append(txt)
            rows.append(f"| {left:<12} | {disp:<7} | " + " | ".join(out_cells) + " |")
    w(header)
    w(sep)
    for r in rows:
        w(r)
    w("")
    marks = []
    for c, m in cell_keys:
        for name, disp in SERVERS:
            if starved(name, c, m):
                marks.append(f"{disp} {c}x{m}: ~{n_eff_of(name, c, m):.1f} in flight")
    if marks:
        w(f"{DAGGER} closed-loop starved ({'; '.join(marks)}).")
        w("")

    ref_cols = [c for c, m in cell_keys if m == "1" and ("h2", c) in ref]
    if ref_cols:
        w("## 2. NURL, same server and listener: HTTP/3 vs HTTP/2 (M = 1)\n")
        w(
            "The same binary and the same host:port — QUIC over UDP for HTTP/3, "
            "TLS over TCP with ALPN `h2` for HTTP/2 — driven by the same "
            "`h2load`. The gap is the transports' own cost (packet protection "
            "and per-packet framing for QUIC, records for TLS/TCP) with "
            "everything else held equal. HTTP/1.1 on this listener is in "
            "`HTTP_RESULTS.md` (oha): h2load's HTTP/1.1 mode paces itself and "
            "would misreport it."
        )
        w("")
        w("| C | HTTP/3 req/s | HTTP/2 req/s | HTTP/3 / HTTP/2 | HTTP/3 p50 (ms) | HTTP/2 p50 (ms) |")
        w("|--:|-----------:|-----------:|---------------:|----------------:|----------------:|")
        for c in ref_cols:
            h3c = cells.get(("nurl", c, "1"), ("n/a", "n/a", "n/a", "n/a"))
            h2c = ref.get(("h2", c), ("n/a", "n/a", "n/a", "n/a"))
            r3, r2 = num(h3c[0]), num(h2c[0])
            ratio = f"{r3 / r2:.2f}x" if (r3 is not None and r2) else "n/a"
            w(
                f"| {c} | {fmt_rps(h3c[0])} | {fmt_rps(h2c[0])} | {ratio} | "
                f"{fmt_lat(h3c[1])} | {fmt_lat(h2c[1])} |"
            )
        w("")

    if conn or connpeer:
        w("## 3. Connection setup rate\n")
        w(
            f"{env.get('conn_burst','100')} clients each open a fresh connection, make one "
            "request and close: a QUIC handshake (Initial + Handshake, one round "
            "trip, keys derived on both ends) for HTTP/3, a TLS 1.3 handshake over "
            "a new TCP connection for HTTP/2. Connections per second, median of "
            "the runs."
        )
        w("")
        w("| Server | Protocol | conn/s |")
        w("|---|---|------:|")
        for proto, label in (("h3", "HTTP/3 (QUIC)"), ("h2", "HTTP/2 (TLS+TCP)")):
            if proto in conn:
                w(f"| NURL | {label} | {fmt_rps(conn[proto])} |")
        for name, disp in SERVERS:
            if name in connpeer:
                w(f"| {disp} | HTTP/3 (QUIC) | {fmt_rps(connpeer[name])} |")
        w("")

    w(
        "(Best per column in **bold**; latency winners are chosen only among "
        f"non-starved cells. {DAGGER} = closed-loop starved. `n/a` = tool "
        "absent; `FAIL` = the server did not complete that cell.)"
    )
    w("")
    w("## Notes\n")
    w(
        "- The load generator is nghttp2's `h2load` built with ngtcp2 + nghttp3 "
        "(the distribution package is HTTP/2-only), run from a docker image "
        "built from nghttp2's own `docker/Dockerfile`. `oha`, the generator of "
        "the other two reports, has no HTTP/3 client."
    )
    w(
        "- No Node column: Node has no HTTP/3 server. The Rust peer is "
        "`bench/rust_http3_server/` (quinn + h3 + rustls), run with quinn's "
        "default transport settings."
    )
    w(
        "- **Read the Rust column as \"quinn's defaults under this generator\".** "
        "An h2load trace shows an ACK interlock at low concurrency: quinn "
        "does not piggyback a pending (delayed) ACK on the response packet "
        "and sends it alone up to `max_ack_delay` (25 ms) later, and ngtcp2's "
        "client does not open its next request stream until the packet that "
        "carried the previous one is acknowledged — so with few streams in "
        "flight every request costs ~25 ms regardless of the server's work. "
        "NURL bundles the pending ACK into any packet it sends "
        "(RFC 9000 §13.2.1), which is why its columns do not show it. The "
        "cells with many streams per connection are the ones where both "
        "servers are actually busy."
    )
    w(
        "- HTTP/3 conformance is not this report's job: `tools/h3spec_gate.sh` "
        "runs h3spec (49/49: 34 QUIC-transport + 15 HTTP/3 and QPACK error "
        "cases) against the same NURL HttpApp listener in CI. A fast server "
        "that fails h3spec would not be listed as a win."
    )
    w(
        "- Loopback only, 14-byte body, no packet loss: what is measured is "
        "per-packet CPU cost (AEAD, header protection, framing, ACK "
        "bookkeeping), not congestion control. Compare columns within one "
        "run, not across machines."
    )
    w("")
    w("### Planned rigor\n")
    w("1. **Realistic bodies** (1 KB / 16 KB / 1 MB) where flow control, pacing and datagram size matter.")
    w("2. **Lossy paths** (`tc netem` loss/delay) — the QUIC recovery machinery is not exercised on loopback.")
    w("3. **Batched UDP I/O** (`recvmmsg` / GSO) and core isolation, as in the torture harness.")

    sys.stdout.write("\n".join(out) + "\n")


if __name__ == "__main__":
    main()
