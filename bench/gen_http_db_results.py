#!/usr/bin/env python3
# bench/gen_http_db_results.py — render bench/HTTP_DB_RESULTS.md from the
# flat measurement rows `bench/run_http.sh --suite db` feeds on stdin. Not
# meant to be run by hand; the harness drives it and overwrites the file,
# the same contract bench/HTTP_RESULTS.md has with gen_http_results.py.
#
# Input (on stdin):
#   ENV<TAB>key<TAB>value                      one per environment field
#   DBCHECK name verdict…                       the endpoint check per server
#   DBROW path name c rps p50 p99 mean us_req   one closed-loop cell
# name is nurl|rust; numeric fields are numbers or the literal "n/a" /
# "FAIL". Latencies are in ms, `mean` the mean latency in ms (Little's
# law: rps x mean = connections actually in flight), and `us_req` server
# CPU microseconds per request (utime+stime from /proc/<pid>/stat over the
# measured window, divided by the exact response count).

import sys

SERVERS = [("nurl", "NURL"), ("rust", "Rust")]
DAGGER = "‡"  # a closed-loop-starved latency cell

WHAT = {
    "/json": "a `{\"message\":\"Hello, World!\"}` object serialised per request — no database",
    "/db": "one random `world` row by primary key, as JSON",
    "/queries": "N random `world` rows, one query each — all N sent together — as a JSON array",
    "/fortunes": "every `fortune` row plus one added at request time, sorted by message, as an escaped HTML table",
    "/updates": "N random `world` rows read one query each, each given a new random number, written back by ONE `UPDATE … FROM unnest(…)`, as JSON",
    "/async-db": "up to `limit` `items` rows with `price BETWEEN min AND max` (no index: a scan), as `{\"items\":[…],\"count\":n}` with a nested `rating` and a JSONB `tags` array",
}


def num(v):
    try:
        return float(v)
    except (TypeError, ValueError):
        return None


def fmt_rps(v):
    n = num(v)
    return v if n is None else f"{int(round(n)):,}".replace(",", " ")


def fmt2(v):
    n = num(v)
    return v if n is None else f"{n:.2f}"


def main():
    env = {}
    checks = {}
    cells = {}  # (path, name, c) -> (rps, p50, p99, mean, us_req)
    for line in sys.stdin:
        line = line.rstrip("\n")
        if line.startswith("ENV\t"):
            parts = line.split("\t")
            if len(parts) >= 3:
                env[parts[1]] = "\t".join(parts[2:])
        elif line.startswith("DBCHECK "):
            f = line.split(" ", 2)
            if len(f) == 3:
                checks[f[1]] = f[2]
        elif line.startswith("DBROW "):
            f = line.split()[1:]
            if len(f) == 8:
                path, name, c, rps, p50, p99, mean, us_req = f
                cells[(path, name, c)] = (rps, p50, p99, mean, us_req)

    paths = env.get("paths", "").split()
    concs = env.get("concurrencies", "64").split()

    def starved(path, name, c):
        cell = cells.get((path, name, c))
        if not cell:
            return False
        r, m = num(cell[0]), num(cell[3])
        if r is None or m is None:
            return False
        n_eff = r * (m / 1000.0)
        offered = float(c)
        return n_eff < 0.9 * offered and (offered - n_eff) >= 2.0

    out = []
    w = out.append

    w("# NURL HTTP + database peer-comparison\n")
    w(
        f"Generated `{env.get('now', '')}` by `bench/run_http.sh --suite db`. "
        "**Do not edit by hand** — the next run overwrites it."
    )
    w("")
    w(
        "The endpoints a service puts in front of a database — TechEmpower's "
        "five tests and HttpArena's `async-db` profile — served by "
        "`bench/http_server.nu` (the `packages/http` HttpApp facade in "
        "`http_app_async` mode, the database through `packages/psql`: one "
        "connection that every fiber's queries are pipelined on, statements "
        "prepared once, and the N queries of one `/queries` or `/updates` "
        "request sent together with `pg_query_many`) and by the Rust peer "
        "`bench/rust_http_server` "
        "(hyper on tokio's multi-thread runtime, the database through "
        "`tokio-postgres`: one client every task's queries are pipelined on, "
        "statements prepared once, and the N queries of one `/queries` or "
        "`/updates` request sent together with `try_join_all`). Both serve "
        "the same bytes (`bench/http_db_schema.sql`: 10 000 `world` rows, "
        "TechEmpower's 12 fortunes, 100 000 `items`, deterministic), and "
        "every endpoint is checked on both before a request is timed. Node "
        "has no database peer here."
    )
    w("")
    w(
        "**`CPU us/req` is the column to compare.** Server CPU time "
        "(`utime+stime` over every thread, read from `/proc/<pid>/stat` "
        "around the measured window) divided by the exact number of "
        "responses: what one request costs the server, whoever is the "
        "bottleneck. `req/s` here is often the database's ceiling rather "
        "than the server's — the database has cores of its own, one backend "
        "per connection — so two servers can show the same `req/s` at very "
        "different costs. The latency columns are closed-loop, as in "
        f"`HTTP_RESULTS.md` ({DAGGER} = fewer connections in flight than "
        "offered, by Little's law)."
    )
    w("")

    # ── environment ──────────────────────────────────────────────
    w("## Environment\n")
    w("| Item | Value |")
    w("|---|---|")
    w(f"| Host | `{env.get('host', '')}` |")
    w(f"| Kernel | `{env.get('kernel', '')}` |")
    w(f"| CPU | {env.get('cpu', '')} ({env.get('cores', '?')} logical cores) |")
    w(f"| Memory | {env.get('mem_kb', '?')} KiB |")
    w(f"| Commit | `{env.get('commit', '')}` |")
    if env.get("run_url"):
        w(f"| CI run | {env['run_url']} |")
    w(f"| NURL | `{env.get('nurl', '')}` |")
    w(f"| Rust | {env.get('rust', '')} |")
    w(f"| Load generator | {env.get('oha', '')} |")
    w(f"| Database | {env.get('db', '')} |")
    w("")
    w("| Setting | Value |")
    w("|---|---|")
    w(
        f"| Each cell | median of {env.get('iters', '3')} x "
        f"{env.get('duration', '10')} s closed-loop runs, keep-alive |"
    )
    w(f"| Concurrencies | {' , '.join(concs)} |")
    if env.get("pinned") == "yes":
        w(
            f"| Core isolation | server on cores `{env.get('srv_cores', '?')}`, "
            f"generator on cores `{env.get('gen_cores', '?')}` (`taskset`); "
            "the database as above |"
        )
    else:
        w("| Core isolation | **none** — server, database and generator share every core |")
    w(
        f"| Worker threads | {env.get('workers', '?')} per server "
        "(`NURL_WORKERS` / `TOKIO_WORKER_THREADS`) |"
    )
    load, maxload = num(env.get("load")), num(env.get("max_load"))
    if load is not None and maxload is not None and load > maxload:
        w(
            f"| Machine load | **{load:.2f} at start, over the {maxload:.2f} "
            "threshold** — every cell below is inflated |"
        )
    elif load is not None:
        w(f"| Machine load | {load:.2f} at start (quiet) |")
    w("")

    # ── endpoint check ───────────────────────────────────────────
    w("## Endpoint check\n")
    w(
        "Before any timing: `/json`; `/db`; `/queries` with 20, 0, `foo` and "
        "501 (→ 20, 1, 1, 500 rows); `/fortunes` (13 rows, the `<script>` "
        "row escaped, the added row present, byte order); `/updates?queries=5`; "
        "`/async-db?min=10&max=50&limit=5` (5 items in range, `tags` a list, "
        "`rating` an object)."
    )
    w("")
    w("| Server | Check |")
    w("|---|---|")
    for name, disp in SERVERS:
        v = checks.get(name, "n/a")
        w(f"| {disp} | {'passed' if v == 'ok' else '**' + v + '**'} |")
    w("")

    # ── at a glance ──────────────────────────────────────────────
    w("## At a glance: server CPU per request\n")
    head = "| Endpoint | " + " | ".join(
        f"NURL C={c} | Rust C={c} | NURL/Rust" for c in concs
    ) + " |"
    w(head)
    w("|---|" + "|".join(["---:"] * (3 * len(concs))) + "|")
    for path in paths:
        row = []
        for c in concs:
            n = num(cells.get((path, "nurl", c), ("n/a",) * 5)[4])
            r = num(cells.get((path, "rust", c), ("n/a",) * 5)[4])
            row.append(fmt2(cells.get((path, "nurl", c), ("n/a",) * 5)[4]))
            row.append(fmt2(cells.get((path, "rust", c), ("n/a",) * 5)[4]))
            row.append(f"{n / r:.2f}" if n is not None and r not in (None, 0.0) else "n/a")
        w(f"| `{path}` | " + " | ".join(row) + " |")
    w("")
    w("(µs of server CPU per request; NURL/Rust below 1 means NURL spends less.)")
    w("")

    # ── one table per endpoint ───────────────────────────────────
    for i, path in enumerate(paths, 1):
        base = path.split("?")[0]
        w(f"## {i}. `{path}`\n")
        if base in WHAT:
            w(WHAT[base].capitalize() + ".")
            w("")
        w("|              | Server  | " + " | ".join(f"C = {c}" for c in concs) + " |")
        w("|--------------|---------|" + "|".join(["--------:"] * len(concs)) + "|")
        for label, idx, want_max, fmt, is_lat in (
            ("**req/s**", 0, True, fmt_rps, False),
            ("**p50 (ms)**", 1, False, fmt2, True),
            ("**p99 (ms)**", 2, False, fmt2, True),
            ("**CPU us/req**", 4, False, fmt2, False),
        ):
            best = {}
            for c in concs:
                vals = []
                for name, _ in SERVERS:
                    if is_lat and starved(path, name, c):
                        continue
                    v = num(cells.get((path, name, c), ("n/a",) * 5)[idx])
                    if v is not None:
                        vals.append(v)
                best[c] = (max(vals) if want_max else min(vals)) if vals else None
            for si, (name, disp) in enumerate(SERVERS):
                txts = []
                for c in concs:
                    raw = cells.get((path, name, c), ("n/a",) * 5)[idx]
                    t = fmt(raw)
                    v = num(raw)
                    if is_lat and starved(path, name, c):
                        t += DAGGER
                    elif v is not None and best[c] is not None and abs(v - best[c]) < 1e-9:
                        t = f"**{t}**"
                    txts.append(t)
                w(f"| {label if si == 0 else '':<12} | {disp:<7} | " + " | ".join(txts) + " |")
        w("")

    w(
        "(Best per row in **bold**; latency winners only among non-starved "
        f"cells. {DAGGER} = closed-loop starved. `n/a` = tool absent; `FAIL` "
        "= the server failed its check or did not complete the cell.)"
    )
    w("")

    # ── notes ────────────────────────────────────────────────────
    w("## Notes\n")
    w(
        "- **One database connection per server**, pipelined — the shape "
        "both drivers are built for, and one PostgreSQL backend (one core) "
        "behind each server. A server that is cheaper per request than the "
        "database can keep up with shows it in `CPU us/req`, not in `req/s`."
    )
    w(
        "- **`/updates`** reads its rows one query each (as TechEmpower "
        "requires) and writes them back in one statement, ids sorted so two "
        "requests touching the same rows lock them in the same order."
    )
    w(
        "- **Against HttpArena's profiles.** `async-db` here has HttpArena's "
        "query, parameters, clamping and response shape over synthetic data "
        "of the same schema; HttpArena's `fortunes` has 200 rows where "
        "TechEmpower's (used here) has 12, so its pages are 15–30x larger."
    )
    w(
        "- Loopback only, HTTP/1.1, plaintext to the database. Compare "
        "columns within one run, not across machines."
    )

    sys.stdout.write("\n".join(out) + "\n")


if __name__ == "__main__":
    main()
