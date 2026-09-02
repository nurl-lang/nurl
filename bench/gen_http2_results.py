#!/usr/bin/env python3
# bench/gen_http2_results.py — render bench/HTTP2_RESULTS.md from the flat
# measurement rows bench/run_http2.sh feeds on stdin. Not meant to be run
# by hand; run_http2.sh drives it and overwrites HTTP2_RESULTS.md with the
# result, the same way run_http.sh generates HTTP_RESULTS.md.
#
# Input (on stdin):
#   ENV<TAB>key<TAB>value                one per environment field
#   ROW scheme name c p rps p50 p99 mean one per HTTP/2 closed-loop cell
#   H1  scheme c rps p50 p99 mean        NURL HTTP/1.1 reference cell (P=1)
# scheme is http|https, name is nurl|rust|node; numeric fields are numbers
# or the literal "n/a" / "FAIL". Latencies are in ms, `mean` is the mean
# latency in ms used for the effective-concurrency (Little's-law) check.

import sys

SERVERS = [("nurl", "NURL"), ("rust", "Rust"), ("node", "Node")]
SCHEMES = [
    ("http", "1. Cleartext HTTP/2 (h2c, prior knowledge)"),
    ("https", "2. HTTP/2 over TLS (ALPN h2)"),
]
DAGGER = "‡"  # ‡ marks a closed-loop-starved latency cell


def num(v):
    try:
        return float(v)
    except (TypeError, ValueError):
        return None


def main():
    env = {}
    cells = {}   # (scheme, name, c, p) -> (rps, p50, p99, mean) strings
    h1 = {}      # (scheme, c) -> (rps, p50, p99, mean) — NURL HTTP/1.1 reference
    for line in sys.stdin:
        line = line.rstrip("\n")
        if line.startswith("ENV\t"):
            parts = line.split("\t")
            if len(parts) >= 3:
                env[parts[1]] = "\t".join(parts[2:])
        elif line.startswith("ROW "):
            f = line.split()[1:]
            if len(f) == 8:
                scheme, name, c, p, rps, p50, p99, mean = f
                cells[(scheme, name, c, p)] = (rps, p50, p99, mean)
        elif line.startswith("H1 "):
            f = line.split()[1:]
            if len(f) == 6:
                scheme, c, rps, p50, p99, mean = f
                h1[(scheme, c)] = (rps, p50, p99, mean)

    cell_specs = env.get("cells", "1x1 1x10 1x100 10x1 10x10 50x1 50x10").split()
    cell_keys = [tuple(s.split("x")) for s in cell_specs]   # (c, p)

    def starved(scheme, name, c, p):
        # Little's law: requests actually in flight = rps * mean latency.
        # HTTP/2 offers C connections x P streams; when the server keeps
        # far fewer busy, the extra requests queue inside oha and the
        # latency columns describe only the ones in flight.
        cell = cells.get((scheme, name, c, p))
        if not cell:
            return False
        rps, _, _, mean = cell
        r, m = num(rps), num(mean)
        if r is None or m is None:
            return False
        n_eff = r * (m / 1000.0)
        try:
            offered = float(c) * float(p)
        except ValueError:
            return False
        return n_eff < 0.9 * offered and (offered - n_eff) >= 2.0

    def n_eff_of(scheme, name, c, p):
        rps, _, _, mean = cells[(scheme, name, c, p)]
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

    w("# NURL HTTP/2-server peer-comparison\n")
    w(
        f"Generated `{env.get('now','')}` by `bench/run_http2.sh`. "
        "**Do not edit by hand** — the next run overwrites it."
    )
    w("")
    w(
        "The HTTP/2 companion of [`HTTP_RESULTS.md`](HTTP_RESULTS.md) (which "
        "stays HTTP/1.1-only). Each implementation accepts a connection, "
        "speaks HTTP/2 (RFC 9113 + HPACK, RFC 7541) and answers every "
        "request on every stream with the same 14-byte `Hello, World!\\n` "
        "body (`text/plain`). Section 1 is cleartext HTTP/2 with prior "
        "knowledge (§3.4 — the `PRI * HTTP/2.0` preface, what "
        "`curl --http2-prior-knowledge`, `h2load` and `oha --http2` send); "
        "section 2 negotiates `h2` over ALPN (§3.3) on a self-signed EC "
        "(P-256) certificate, which `oha` accepts with `--insecure`."
    )
    w("")
    w(
        "The NURL server is `bench/http_server.nu` **unchanged from the "
        "HTTP/1.1 benchmark**: the `packages/http` HttpApp facade in "
        "`http_app_async` mode serves both protocols on every listener — "
        "ALPN decides over TLS, the connection preface decides on "
        "cleartext. The Rust peer drives hyper's `http2` connection builder "
        "on tokio (rustls with ALPN `h2` for TLS); the Node peer is the "
        "built-in `node:http2` module (`allowHTTP1: false` for TLS)."
    )
    w("")
    w(
        "**Cells are `C x P`: C connections, each carrying P concurrent "
        "streams** (`oha --http2 -c C -p P`), so C x P requests are in "
        "flight. `1 x 100` is one connection multiplexing a hundred "
        "streams — HTTP/2's own axis, which HTTP/1.1 has no equivalent "
        "for; `50 x 1` is fifty connections with one stream each, the "
        "closest thing to the HTTP/1.1 `C = 50` cell."
    )
    w("")
    w(
        "**Read the throughput columns, not the latency columns, at high "
        "in-flight counts.** These are *closed-loop* measurements: `oha` "
        "fires the next request on a stream the instant the previous one "
        "returns. If a server's in-flight work saturates below C x P, the "
        "extra requests queue inside `oha` and never reach the server, so "
        "`req/s` is the server's true saturation throughput but the "
        "latency percentiles describe only the requests in flight. Such "
        f"cells are marked {DAGGER} and left un-bold. The effective in-flight "
        "count is `req/s x mean-latency` (Little's law)."
    )
    w("")

    # ── environment ──────────────────────────────────────────────
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
    w(f"| Node | {env.get('node','')} |")
    w(f"| Load generator | {env.get('oha','')} |")
    w("")
    w("| Setting | Value |")
    w("|---|---|")
    w(
        f"| Throughput/latency | median of {env.get('iters','3')} x "
        f"{env.get('duration','10')} s closed-loop runs |"
    )
    w(f"| Cells (C x P) | {' , '.join(cell_specs)} |")
    w("| TLS cert | self-signed EC P-256, `CN=localhost`, ALPN `h2` |")
    w("")

    # ── one table per scheme ─────────────────────────────────────
    for scheme, title in SCHEMES:
        w(f"## {title}\n")
        header = "|              | Server  | " + " | ".join(
            f"{c} x {p}" for c, p in cell_keys
        ) + " |"
        sep = "|--------------|---------|" + "|".join(["--------:"] * len(cell_keys)) + "|"

        rows = []
        for metric_label, idx, want_max, fmt, is_lat in (
            ("**req/s**", 0, True, fmt_rps, False),
            ("**p50 (ms)**", 1, False, fmt_lat, True),
            ("**p99 (ms)**", 2, False, fmt_lat, True),
        ):
            col_best = {}
            for c, p in cell_keys:
                vals = []
                for name, _ in SERVERS:
                    if is_lat and starved(scheme, name, c, p):
                        continue
                    cell = cells.get((scheme, name, c, p))
                    if cell:
                        vals.append(cell[idx])
                col_best[(c, p)] = best(vals, want_max)
            for si, (name, disp) in enumerate(SERVERS):
                left = metric_label if si == 0 else ""
                out_cells = []
                for c, p in cell_keys:
                    cell = cells.get((scheme, name, c, p), ("n/a", "n/a", "n/a", "n/a"))
                    raw = cell[idx]
                    txt = fmt(raw)
                    n = num(raw)
                    st = is_lat and starved(scheme, name, c, p)
                    if st:
                        txt = f"{txt}{DAGGER}"
                    elif n is not None and col_best[(c, p)] is not None and abs(n - col_best[(c, p)]) < 1e-9:
                        txt = f"**{txt}**"
                    out_cells.append(txt)
                rows.append(
                    f"| {left:<12} | {disp:<7} | " + " | ".join(out_cells) + " |"
                )

        w(header)
        w(sep)
        for r in rows:
            w(r)
        w("")

        marks = []
        for c, p in cell_keys:
            for name, disp in SERVERS:
                if starved(scheme, name, c, p):
                    marks.append(f"{disp} {c}x{p}: ~{n_eff_of(scheme, name, c, p):.1f} in flight")
        if marks:
            w(f"{DAGGER} closed-loop starved ({'; '.join(marks)}).")
            w("")

        # ── NURL: HTTP/2 vs HTTP/1.1 on the same listener ────────
        h1_cols = [(c, p) for c, p in cell_keys if p == "1" and (scheme, c) in h1]
        if h1_cols:
            w(f"### NURL, same server and listener: HTTP/2 (P = 1) vs HTTP/1.1\n")
            w(
                "The same binary, the same port, `oha` with and without "
                "`--http2`. The gap is the protocol's own cost — framing, "
                "HPACK, flow-control bookkeeping — with everything else held "
                "equal."
            )
            w("")
            w("| C | HTTP/2 req/s | HTTP/1.1 req/s | HTTP/2 / HTTP/1.1 | HTTP/2 p50 (ms) | HTTP/1.1 p50 (ms) |")
            w("|--:|------------:|--------------:|------------------:|----------------:|-----------------:|")
            for c, p in h1_cols:
                h2c = cells.get((scheme, "nurl", c, p), ("n/a", "n/a", "n/a", "n/a"))
                h1c = h1[(scheme, c)]
                r2, r1 = num(h2c[0]), num(h1c[0])
                ratio = f"{r2 / r1:.2f}x" if (r2 is not None and r1) else "n/a"
                w(
                    f"| {c} | {fmt_rps(h2c[0])} | {fmt_rps(h1c[0])} | {ratio} | "
                    f"{fmt_lat(h2c[1])} | {fmt_lat(h1c[1])} |"
                )
            w("")

    w(
        "(Best per column in **bold**; latency winners are chosen only among "
        f"non-starved cells. {DAGGER} = closed-loop starved. `n/a` = tool "
        "absent; `FAIL` = the server did not complete that cell.)"
    )
    w("")

    # ── notes ────────────────────────────────────────────────────
    w("## Notes\n")
    w(
        "- **No connection-setup-rate table here.** `oha --disable-keepalive` "
        "has no effect on its HTTP/2 client (it keeps the C connections and "
        "reuses them), so the per-connection cost cannot be measured with "
        "this generator. The TLS handshake is protocol-independent; its "
        "rate is in `HTTP_RESULTS.md` §3. What HTTP/2 adds on top of it is "
        "one SETTINGS exchange per connection."
    )
    w(
        "- Rust serves TLS through `tokio-rustls` (ALPN `h2`); Node through "
        "`http2.createSecureServer`. Each uses its conventional stack, so "
        "the columns compare deployments, not just ciphers."
    )
    w(
        "- HTTP/2 conformance is not this report's job: `tools/h2spec_gate.sh` "
        "runs h2spec (146/146, strict 147/147) against the same NURL HttpApp "
        "in CI. A fast server that fails h2spec would not be listed as a win."
    )
    w(
        "- Loopback only, 14-byte body. Absolute numbers depend heavily on "
        "the host; compare columns within one run, not across machines, and "
        "compare against `HTTP_RESULTS.md` only when both were produced on "
        "the same runner class."
    )
    w("")
    w("### Planned rigor\n")
    w(
        "1. **Open-loop latency.** A fixed-rate generator (`oha -q "
        "--latency-correction --http2`) at 50/80/95 % of each server's "
        "measured throughput, reporting p50/p99/p99.9 — the "
        "`bench/http_torture` treatment, for HTTP/2."
    )
    w(
        "2. **Realistic bodies.** 1 KB / 16 KB / 1 MB responses, where "
        "DATA framing, flow-control windows and the per-stream WINDOW_UPDATE "
        "traffic start to matter; a 14-byte body measures HEADERS + HPACK."
    )
    w(
        "3. **Core isolation** (server and generator on disjoint cores) and "
        "**CPU-time per request**, as in the torture harness."
    )

    sys.stdout.write("\n".join(out) + "\n")


if __name__ == "__main__":
    main()
