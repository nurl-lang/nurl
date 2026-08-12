#!/usr/bin/env python3
# bench/gen_http_results.py — render bench/HTTP_RESULTS.md from the flat
# measurement rows bench/run_http.sh feeds on stdin. Not meant to be run
# by hand; run_http.sh drives it and overwrites HTTP_RESULTS.md with the
# result, the same way bench.sh generates bench/RESULTS.md.
#
# Input (tab-separated) on stdin:
#   ENV<TAB>key<TAB>value        one per environment field
#   ROW<TAB>scheme name c rps p50 p99   one per measured cell
# where scheme is http|https, name is nurl|rust|node, and rps/p50/p99 are
# numbers or the literal "n/a" / "FAIL".

import sys

SERVERS = [("nurl", "NURL"), ("rust", "Rust"), ("node", "Node")]
SCHEMES = [("http", "1. Plaintext HTTP"), ("https", "2. TLS (HTTPS)")]


def main():
    env = {}
    # cells[(scheme, name, c)] = (rps, p50, p99) as strings
    cells = {}
    for line in sys.stdin:
        parts = line.rstrip("\n").split("\t")
        if not parts:
            continue
        if parts[0] == "ENV" and len(parts) >= 3:
            env[parts[1]] = "\t".join(parts[2:])
        elif parts[0] == "ROW" and len(parts) >= 2:
            f = parts[1].split()
            if len(f) == 6:
                scheme, name, c, rps, p50, p99 = f
                cells[(scheme, name, c)] = (rps, p50, p99)

    concs = env.get("concurrencies", "1 10 50 200").split()

    def num(v):
        try:
            return float(v)
        except (TypeError, ValueError):
            return None

    def fmt_rps(v):
        n = num(v)
        if n is None:
            return v  # "n/a" / "FAIL"
        # thousands separator with a thin space, matching the prior table
        return f"{int(round(n)):,}".replace(",", " ")

    def fmt_lat(v):
        n = num(v)
        return v if n is None else f"{n:.2f}"

    def best(values, want_max):
        nums = [num(v) for v in values]
        present = [x for x in nums if x is not None]
        if not present:
            return None
        return max(present) if want_max else min(present)

    out = []
    w = out.append

    w("# NURL HTTP-server peer-comparison\n")
    w(
        f"Generated `{env.get('now','')}` by `bench/run_http.sh`. "
        "**Do not edit by hand** — the next run overwrites it."
    )
    w("")
    w(
        "Each implementation accepts a TCP connection, parses one "
        "HTTP/1.1 request and writes a 14-byte `Hello, World!\\n` body "
        "(`text/plain`), keep-alive. The TLS section runs the *same* "
        "servers and the same load over a self-signed EC (P-256) "
        "certificate; the load generator (`oha`) accepts it with "
        "`--insecure`. The NURL server is the `packages/http` HttpApp "
        "facade (`http_app_listen` / `http_app_listen_tls`) with a "
        "10-thread worker pool — the surface a real NURL service "
        "deploys."
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
        f"| Measurement | median of {env.get('iters','3')} × "
        f"{env.get('duration','10')} s runs per cell, HTTP/1.1 keep-alive |"
    )
    w(f"| Concurrencies | {' , '.join(concs)} |")
    w("| TLS cert | self-signed EC P-256, `CN=localhost` |")
    w("")

    # ── one table per scheme ─────────────────────────────────────
    for scheme, title in SCHEMES:
        w(f"## {title}\n")
        header = "|              | Server  | " + " | ".join(
            f"C = {c}" for c in concs
        ) + " |"
        sep = "|--------------|---------|" + "|".join(["--------:"] * len(concs)) + "|"

        rows = []
        # For each metric block, compute best per column across servers.
        for metric_label, idx, want_max, fmt in (
            ("**req/s**", 0, True, fmt_rps),
            ("**p50 (ms)**", 1, False, fmt_lat),
            ("**p99 (ms)**", 2, False, fmt_lat),
        ):
            # best value per concurrency column
            col_best = {}
            for c in concs:
                vals = [
                    cells.get((scheme, name, c), ("n/a", "n/a", "n/a"))[idx]
                    for name, _ in SERVERS
                ]
                col_best[c] = best(vals, want_max)
            for si, (name, disp) in enumerate(SERVERS):
                left = metric_label if si == 0 else ""
                out_cells = []
                for c in concs:
                    raw = cells.get((scheme, name, c), ("n/a", "n/a", "n/a"))[idx]
                    txt = fmt(raw)
                    n = num(raw)
                    if n is not None and col_best[c] is not None and abs(n - col_best[c]) < 1e-9:
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

    w("(Best per row in **bold**. Higher is better for req/s, lower for "
      "latency. `n/a` = tool absent at measurement time; `FAIL` = the "
      "server did not complete that cell.)")
    w("")

    # ── reading notes (generated, factual) ───────────────────────
    w("## Notes\n")
    w(
        "- The TLS rows carry the full handshake + record-layer cost of "
        "NURL's pure-NURL TLS 1.3 stack (no OpenSSL); with keep-alive "
        "the handshake is amortised across a connection's requests, so "
        "the gap to plaintext is the per-record AEAD, not a per-request "
        "handshake."
    )
    w(
        "- Rust serves TLS through `tokio-rustls`; Node through its "
        "built-in `https` module. Each implementation uses its "
        "conventional stack, so the columns compare deployments, not "
        "just ciphers."
    )
    w(
        "- Loopback only, HTTP/1.1 only. No HTTP/2. Absolute numbers "
        "depend heavily on the host; compare columns within one run, "
        "not across machines."
    )

    sys.stdout.write("\n".join(out) + "\n")


if __name__ == "__main__":
    main()
