#!/usr/bin/env python3
# bench/gen_http_results.py — render bench/HTTP_RESULTS.md from the flat
# measurement rows bench/run_http.sh feeds on stdin. Not meant to be run
# by hand; run_http.sh drives it and overwrites HTTP_RESULTS.md with the
# result, the same way bench.sh generates bench/RESULTS.md.
#
# Input (on stdin):
#   ENV<TAB>key<TAB>value            one per environment field
#   ROW scheme name c rps p50 p99 mean us_req   one closed-loop cell
#   HS  scheme name conn_per_s       one connection-setup-rate cell/server
# scheme is http|https, name is nurl|rust|node; numeric fields are numbers
# or the literal "n/a" / "FAIL". Latencies are in ms, `mean` is the mean
# latency in ms used for the effective-concurrency (Little's-law) check,
# and `us_req` is server CPU microseconds per request (utime+stime from
# /proc/<pid>/stat over the measured window, divided by the exact
# response count) — the one column that is not a function of how hard
# the generator happened to push.

import sys

SERVERS = [("nurl", "NURL"), ("rust", "Rust"), ("node", "Node")]
SCHEMES = [("http", "1. Plaintext HTTP"), ("https", "2. TLS (HTTPS)")]
DAGGER = "‡"  # ‡ marks a closed-loop-starved latency cell


def num(v):
    try:
        return float(v)
    except (TypeError, ValueError):
        return None


def main():
    env = {}
    cells = {}   # (scheme, name, c) -> (rps, p50, p99, mean, us_req) strings
    conn = {}    # (scheme, name) -> conn_per_s string
    for line in sys.stdin:
        line = line.rstrip("\n")
        if line.startswith("ENV\t"):
            parts = line.split("\t")
            if len(parts) >= 3:
                env[parts[1]] = "\t".join(parts[2:])
        elif line.startswith("ROW "):
            f = line.split()[1:]
            if len(f) == 8:
                scheme, name, c, rps, p50, p99, mean, us_req = f
                cells[(scheme, name, c)] = (rps, p50, p99, mean, us_req)
        elif line.startswith("HS "):
            f = line.split()[1:]
            if len(f) == 3:
                conn[(f[0], f[1])] = f[2]

    concs = env.get("concurrencies", "1 10 50 200").split()

    def starved(scheme, name, c):
        # Little's law: the number of connections actually in flight is
        # rps * mean_latency. A closed-loop cell that offered C but kept
        # far fewer busy is measuring the latency of the served few, not
        # of the C that were offered.
        #
        # Two conditions so low-C cells are not false-flagged: the ratio
        # must be well under 1 AND at least ~2 offered connections must
        # have failed to reach the server. At C=1 the ratio dips below 0.9
        # from send-gap granularity alone (~0.8 in flight), but the
        # absolute gap is a fraction of a connection, not real starvation.
        cell = cells.get((scheme, name, c))
        if not cell:
            return False
        rps, mean = cell[0], cell[3]
        r, m = num(rps), num(mean)
        if r is None or m is None:
            return False
        n_eff = r * (m / 1000.0)
        try:
            offered = float(c)
        except ValueError:
            return False
        return n_eff < 0.9 * offered and (offered - n_eff) >= 2.0

    def n_eff_of(scheme, name, c):
        cell = cells.get((scheme, name, c))
        rps, mean = cell[0], cell[3]
        return num(rps) * (num(mean) / 1000.0)

    def fmt_rps(v):
        n = num(v)
        return v if n is None else f"{int(round(n)):,}".replace(",", " ")

    def fmt_cpu(v):
        n = num(v)
        return v if n is None else f"{n:.2f}"

    def fmt_lat(v):
        n = num(v)
        return v if n is None else f"{n:.2f}"

    def best(values, want_max):
        present = [num(v) for v in values]
        present = [x for x in present if x is not None]
        return (max(present) if want_max else min(present)) if present else None

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
        "certificate, which `oha` accepts with `--insecure`. The NURL "
        "server is the `packages/http` HttpApp facade (`http_app_listen` "
        "/ `http_app_listen_tls`) in `http_app_async` mode — fiber per "
        "connection on the M:N async runtime, one worker pthread per "
        "core, the surface a scaling NURL service deploys (and the same "
        "model as the Rust peer's tokio multi-thread runtime)."
    )
    w("")
    w(
        "**Read the throughput columns, not the latency columns, at high "
        "concurrency.** These are *closed-loop* measurements: `oha` holds "
        "C connections open and fires the next request the instant one "
        "returns. If a server's in-flight work saturates below C, the "
        "extra connections queue inside `oha` and never reach the server, "
        "so `req/s` is the server's true saturation throughput but the "
        "latency percentiles describe only the few connections in flight. "
        f"Such cells are marked {DAGGER} and left un-bold: their latency "
        "is not a service-level number (that needs an open-loop generator "
        "— see *Planned rigor*). The effective in-flight count is "
        "`req/s x mean-latency` (Little's law)."
    )
    w("")
    w(
        "**The `CPU us/req` row is the one to compare across peers.** It is "
        "server CPU time (`utime+stime` over every thread, read externally "
        "from `/proc/<pid>/stat` around the measured window) divided by the "
        "exact number of responses — so unlike `req/s` it does not move when "
        "the generator pushes harder or softer. Two warnings that cost real "
        "time to learn: it rises with worker count for **every** runtime "
        "(~30 % from 1 to 4 workers here), and an unpinned run inflates it "
        "because the generator is stealing the server's cores. Comparing a "
        "figure taken at one worker count against a figure taken at another "
        "manufactures a peer gap out of nothing but concurrency. The "
        "Environment block above states both, for exactly that reason."
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
        f"{env.get('duration','10')} s closed-loop runs, keep-alive |"
    )
    w(f"| Concurrencies | {' , '.join(concs)} |")
    w(
        f"| Connection-setup rate | {env.get('hs_reqs','20000')} "
        f"connections at c={env.get('hs_conc','20')}, `--disable-keepalive` |"
    )
    w("| TLS cert | self-signed EC P-256, `CN=localhost` |")
    if env.get("pinned") == "yes":
        w(
            f"| Core isolation | server on cores `{env.get('srv_cores','?')}`, "
            f"generator on cores `{env.get('gen_cores','?')}` (`taskset`) |"
        )
    else:
        w(
            "| Core isolation | **none** — server and generator share every "
            "core, so each cell measures the pair, not the server |"
        )
    w(
        f"| Worker threads | {env.get('workers','?')} per server "
        "(`NURL_WORKERS` / `TOKIO_WORKER_THREADS`); Node's server is "
        "single-threaded |"
    )
    _load = num(env.get("load"))
    _maxload = num(env.get("max_load"))
    if _load is not None and _maxload is not None and _load > _maxload:
        w(
            f"| Machine load | **{_load:.2f} at start, over the {_maxload:.2f} "
            "threshold** — something else was using the CPU, so every cell "
            "below is inflated; re-run on a quiet box before quoting these |"
        )
    elif _load is not None:
        w(f"| Machine load | {_load:.2f} at start (quiet) |")
    w("")

    # ── one throughput/latency table per scheme ──────────────────
    for scheme, title in SCHEMES:
        w(f"## {title}\n")
        header = "|              | Server  | " + " | ".join(
            f"C = {c}" for c in concs
        ) + " |"
        sep = "|--------------|---------|" + "|".join(["--------:"] * len(concs)) + "|"

        rows = []
        for metric_label, idx, want_max, fmt, is_lat in (
            ("**req/s**", 0, True, fmt_rps, False),
            ("**p50 (ms)**", 1, False, fmt_lat, True),
            ("**p99 (ms)**", 2, False, fmt_lat, True),
            ("**CPU us/req**", 4, False, fmt_cpu, False),
        ):
            # Best per concurrency column, ignoring starved latency cells
            # so a starved 0.06 ms never wins (or bolds) a latency row.
            col_best = {}
            for c in concs:
                vals = []
                for name, _ in SERVERS:
                    if is_lat and starved(scheme, name, c):
                        continue
                    cell = cells.get((scheme, name, c))
                    if cell:
                        vals.append(cell[idx])
                col_best[c] = best(vals, want_max)
            for si, (name, disp) in enumerate(SERVERS):
                left = metric_label if si == 0 else ""
                out_cells = []
                for c in concs:
                    cell = cells.get((scheme, name, c), ("n/a", "n/a", "n/a", "n/a", "n/a"))
                    raw = cell[idx]
                    txt = fmt(raw)
                    n = num(raw)
                    st = is_lat and starved(scheme, name, c)
                    if st:
                        txt = f"{txt}{DAGGER}"
                    elif n is not None and col_best[c] is not None and abs(n - col_best[c]) < 1e-9:
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

        # Per-scheme starvation footnote naming the effective in-flight
        # count for every marked cell, so the number is on the page.
        marks = []
        for c in concs:
            for name, disp in SERVERS:
                if starved(scheme, name, c):
                    marks.append(f"{disp} C={c}: ~{n_eff_of(scheme, name, c):.1f} in flight")
        if marks:
            w(f"{DAGGER} closed-loop starved ({'; '.join(marks)}).")
            w("")

    w(
        "(Best per row in **bold**; latency winners are chosen only among "
        f"non-starved cells. {DAGGER} = closed-loop starved. `n/a` = tool "
        "absent; `FAIL` = the server did not complete that cell.)"
    )
    w("")

    # ── connection-setup / TLS-handshake rate ────────────────────
    w("## 3. Connection-setup rate (new connection per request)\n")
    w(
        "`--disable-keepalive`, so each request pays a fresh connection. "
        "For `http` that is the accept/teardown rate; for `https` it is "
        "**TLS handshakes per second** — the pure-NURL P-256 ECDHE + "
        "ECDSA-verify path (no OpenSSL, no AES-NI-tier handshake assembly) "
        "against rustls and Node. This is the cost a short-lived-"
        "connection edge deployment actually pays, and the one the keep-"
        "alive tables above amortise to nothing."
    )
    w("")
    w("| Server | http conn/s | https handshakes/s |")
    w("|--------|------------:|-------------------:|")
    for name, disp in SERVERS:
        h = conn.get(("http", name), "n/a")
        s = conn.get(("https", name), "n/a")
        # bold the best of each column
        hvals = [conn.get(("http", n), "n/a") for n, _ in SERVERS]
        svals = [conn.get(("https", n), "n/a") for n, _ in SERVERS]
        hb, sb = best(hvals, True), best(svals, True)
        ht = fmt_rps(h); st = fmt_rps(s)
        if num(h) is not None and hb is not None and abs(num(h) - hb) < 1e-9:
            ht = f"**{ht}**"
        if num(s) is not None and sb is not None and abs(num(s) - sb) < 1e-9:
            st = f"**{st}**"
        w(f"| {disp:<6} | {ht} | {st} |")
    w("")

    # ── notes ────────────────────────────────────────────────────
    w("## Notes\n")
    w(
        "- **What the TLS tables measure.** With keep-alive, a connection "
        "handshakes once and then serves many requests, so the section-2 "
        "gap to plaintext is the per-record AEAD, *not* the handshake. The "
        "handshake cost lives in section 3, where every request is a new "
        "connection."
    )
    w(
        "- Rust serves TLS through `tokio-rustls`; Node through its "
        "built-in `https` module. Each uses its conventional stack, so the "
        "columns compare deployments, not just ciphers."
    )
    w(
        "- Loopback only, HTTP/1.1 only, 14-byte body. No HTTP/2. Absolute "
        "numbers depend heavily on the host; compare columns within one "
        "run, not across machines."
    )
    w("")
    w("### Planned rigor\n")
    w(
        "Known limits of this harness, in priority order — each is a "
        "measurement this run does **not** yet make, called out so a "
        "reader does not have to guess:"
    )
    w(
        "1. **Open-loop latency.** Replace the closed-loop latency columns "
        "with a fixed-rate generator (`oha -q`, or `wrk2`/`vegeta`) at "
        "50/80/95 % of each server's measured throughput, reporting "
        "p50/p99/p99.9/max. Closed loop cannot measure latency above "
        "capacity (coordinated omission), which is why saturated cells are "
        f"marked {DAGGER} rather than trusted."
    )
    w(
        "2. ~~**Core isolation.**~~ **Done** — the server and the generator "
        "run on disjoint core sets via `taskset` and every runtime that "
        "sizes a pool from `nproc` is given the same worker count. See the "
        "Environment block; a run on fewer than 4 cores, or without "
        "`taskset`, says so there instead."
    )
    w(
        "3. ~~**CPU-time per request.**~~ **Done**, and without the "
        "`getrusage` call the original plan wanted in each server: "
        "`utime+stime` read externally from `/proc/<pid>/stat` is the same "
        "figure and needs no code change in any peer, so NURL, Rust and "
        "Node are all measured the same way. Divided by the exact response "
        "count from oha's status-code histogram, never by `rps x duration`."
    )
    w(
        "4. **Record-layer throughput.** Re-run TLS with 16 KB and 1 MB "
        "bodies; a 14-byte body exercises the handshake and framing, not "
        "the AEAD stream."
    )

    sys.stdout.write("\n".join(out) + "\n")


if __name__ == "__main__":
    main()
