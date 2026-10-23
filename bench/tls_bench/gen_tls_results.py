#!/usr/bin/env python3
# bench/tls_bench/gen_tls_results.py — turns run_tls.sh's raw results
# (stdin) into bench/tls_bench/TLS_RESULTS.md (stdout).
#
# Input lines (tab-separated):
#   ENV  <key> <value>
#   P    <impl> <primitive name> <ns_per_op>          one per run; median taken
#   M    <section> <case> <impl> <key=value ...>      one per measured cell
#
# The report leads with the focus list: every headline metric as NURL's
# share of Rust's, worst first, each with what the measurement says the
# gap is made of. Everything below it is the evidence for that table.
import statistics
import sys

env, prims, cells = {}, {}, {}
for line in sys.stdin:
    f = line.rstrip("\n").split("\t")
    if f[0] == "ENV" and len(f) >= 3:
        env[f[1]] = f[2]
    elif f[0] == "P" and len(f) >= 4:
        prims.setdefault((f[1], f[2]), []).append(int(f[3]))
    elif f[0] == "M" and len(f) >= 5:
        kv = {}
        for tok in f[4].split():
            k, _, v = tok.partition("=")
            try:
                kv[k] = float(v)
            except ValueError:
                pass
        cells[(f[1], f[2], f[3])] = kv

IMPLS = ("NURL", "RUST")


def prim_us(impl, name):
    v = prims.get((impl, name))
    return statistics.median(v) / 1000.0 if v else None


def cell(sec, case, impl):
    c = cells.get((sec, case, impl))
    return c if c and c.get("ok", 0) > 0 and c.get("elapsed_ns", 0) > 0 else None


def rate(c):
    return c["ok"] * 1e9 / c["elapsed_ns"] if c else None


def mbps(c):
    return c["bytes"] * 1e3 / c["elapsed_ns"] if c else None  # bytes/ns·1e3 = MB/s


MIN_OPS = 50  # below this, work still in flight at the window's end skews CPU per operation


def cpu_us_per_op(c):
    if not c or not c.get("srv_cpu_ns") or c["ok"] < MIN_OPS:
        return None
    return c["srv_cpu_ns"] / c["ok"] / 1000.0


def util(c):
    if not c or not c.get("srv_cores"):
        return None
    return c["srv_cpu_ns"] / (c["elapsed_ns"] * c["srv_cores"])


def fnum(x, unit="", nd=None):
    if x is None:
        return "n/a"
    if nd is None:
        nd = 0 if abs(x) >= 100 else 1 if abs(x) >= 10 else 2
    s = f"{x:,.{nd}f}"
    return s + unit


def ratio_cell(n, r, higher_better=True):
    """NURL as a share of Rust — 100 % is parity, above is ahead."""
    if not n or not r:
        return None
    return n / r if higher_better else r / n


def verdict(s):
    if s is None:
        return "—"
    if s >= 1.05:
        return "ahead"
    if s >= 0.95:
        return "parity"
    if s >= 0.75:
        return "behind"
    if s >= 0.4:
        return "**gap**"
    return "**major gap**"


def pct(s):
    return "n/a" if s is None else f"{s * 100:.0f} %"


# ── handshake model: what the server's primitives cost per handshake ──
HKDF_PER_HS = 16  # Expand-Label calls in a TLS 1.3 server key schedule, roughly
CASES = {
    "ec:x25519:0": ("Full · ECDSA P-256 · X25519", "x25519", "ec", False),
    "ec:x25519:1": ("Resumed · X25519 (psk_dhe_ke)", "x25519", "ec", True),
    "ec:p256:0": ("Full · ECDSA P-256 · P-256", "p256", "ec", False),
    "ec:mlkem:0": ("Full · ECDSA P-256 · X25519MLKEM768", "mlkem", "ec", False),
    "rsa:x25519:0": ("Full · RSA-2048 · X25519", "x25519", "rsa", False),
}


def budget_parts(impl, group, cert, resumed):
    parts = []
    if group in ("x25519", "mlkem"):
        parts += ["X25519 keygen", "X25519 shared"]
    if group == "p256":
        parts += ["P-256 ECDH keygen", "P-256 ECDH shared"]
    if group == "mlkem":
        parts += ["ML-KEM-768 encaps"]
    if not resumed:
        parts += ["ECDSA P-256 sign" if cert == "ec" else "RSA-2048 PSS sign"]
    out = {p: prim_us(impl, p) for p in parts}
    h = prim_us(impl, "HKDF-Expand-Label")
    out[f"{HKDF_PER_HS}× HKDF-Expand-Label"] = h * HKDF_PER_HS if h is not None else None
    return out


def budget(impl, group, cert, resumed):
    parts = budget_parts(impl, group, cert, resumed)
    return None if any(v is None for v in parts.values()) else sum(parts.values())


def explain_hs(case):
    _, group, cert, resumed = CASES[case]
    n, r = cell("handshake", case, "NURL"), cell("handshake", case, "RUST")
    nc, rc = cpu_us_per_op(n), cpu_us_per_op(r)
    nb, rb = budget("NURL", group, cert, resumed), budget("RUST", group, cert, resumed)
    if None in (nc, rc, nb, rb):
        if n and n["ok"] < MIN_OPS and None not in (nb, rb):
            return (f"under {MIN_OPS} handshakes completed in the window; the server's primitives alone cost "
                    f"{fnum(nb)} vs {fnum(rb)} µs per handshake")
        return ""
    gap = nc - rc
    if gap <= 0:
        return f"server CPU/handshake {fnum(nc)} vs {fnum(rc)} µs"
    crypto = nb - rb
    rest = gap - crypto
    rest_s = (f"{fnum(rest)} µs is protocol / runtime / I/O" if rest >= 0 else
              f"NURL's protocol / runtime / I/O is {fnum(-rest)} µs CHEAPER than Rust's")
    pn, pr = budget_parts("NURL", group, cert, resumed), budget_parts("RUST", group, cert, resumed)
    worst = max(pn, key=lambda k: (pn[k] or 0) - (pr[k] or 0))
    return (f"server CPU {fnum(nc)} vs {fnum(rc)} µs/handshake: of the {fnum(gap)} µs gap, "
            f"{fnum(crypto)} µs is primitive crypto (largest: {worst}, +{fnum((pn[worst] or 0) - (pr[worst] or 0))} µs), "
            f"{rest_s}")


# ── the focus list ───────────────────────────────────────────────────
focus = []  # (score, area, metric, nurl_str, rust_str, why)


def add_focus(area, metric, n, r, unit, higher_better=True, why=""):
    s = ratio_cell(n, r, higher_better)
    focus.append((s, area, metric, fnum(n, unit), fnum(r, unit), why))


def ran_empty(sec, case, impl):
    """The cell ran its whole window and completed nothing: a rate of 0,
    not a missing measurement."""
    c = cells.get((sec, case, impl))
    return bool(c) and c.get("elapsed_ns", 0) > 0 and c.get("ok", 0) == 0 and c.get("err", 0) == 0


for case, (label, *_rest) in CASES.items():
    n, r = cell("handshake", case, "NURL"), cell("handshake", case, "RUST")
    nr = 0.0 if ran_empty("handshake", case, "NURL") else rate(n)
    s = ratio_cell(nr, rate(r)) if nr != 0.0 else (0.0 if rate(r) else None)
    why = explain_hs(case)
    if nr == 0.0:
        _, group, cert, resumed = CASES[case]
        nb, rb = budget("NURL", group, cert, resumed), budget("RUST", group, cert, resumed)
        why = (f"not one handshake completed in the window; the server's primitives alone cost "
               f"{fnum(nb)} vs {fnum(rb)} µs per handshake")
    focus.append((s, "server handshake", label + " — handshakes/s", fnum(nr, "/s"), fnum(rate(r), "/s"), why))
for case, (label, *_rest) in CASES.items():
    n, r = cell("latency", case, "NURL"), cell("latency", case, "RUST")
    add_focus("server handshake", label + " — unloaded latency p50",
              n and n.get("hs_p50_us"), r and r.get("hs_p50_us"), " µs", False)


def overhead_per_req(impl):
    t, p = cell("records", "tls:/1k", impl), cell("records", "plain:/1k", impl)
    a, b = cpu_us_per_op(t), cpu_us_per_op(p)
    return None if None in (a, b) else a - b


n, r = cell("records", "tls:/1k", "NURL"), cell("records", "tls:/1k", "RUST")
on, orr = overhead_per_req("NURL"), overhead_per_req("RUST")
add_focus("record layer", "Keep-alive 1 KB over TLS — req/s", rate(n), rate(r), "/s", True,
          f"TLS adds {fnum(on)} µs CPU per request on NURL, {fnum(orr)} µs on Rust (TLS minus plaintext)" if None not in (on, orr) else "")
n, r = cell("records", "plain:/1k", "NURL"), cell("records", "plain:/1k", "RUST")
add_focus("record layer", "Keep-alive 1 KB plaintext — req/s (baseline)", rate(n), rate(r), "/s", True,
          "not TLS: the HTTP/1.1 server itself")

AEAD = {"aes128": "AES-128-GCM seal 16 KB", "chacha": "ChaCha20-Poly1305 seal 16 KB"}


def ns_per_kb(c):
    return c["srv_cpu_ns"] / (c["bytes"] / 1024.0) if c and c.get("bytes") else None


for suite, prim in AEAD.items():
    n, r = cell("bulk", suite, "NURL"), cell("bulk", suite, "RUST")
    why = ""
    if n and r:
        an, ar = prim_us("NURL", prim), prim_us("RUST", prim)
        why = (f"server CPU {fnum(ns_per_kb(n))} vs {fnum(ns_per_kb(r))} ns/KB; the AEAD alone is "
               f"{fnum(an * 1000 / 16 if an else None)} vs {fnum(ar * 1000 / 16 if ar else None)} ns/KB")
    add_focus("bulk", f"1 MB bodies, one connection, {prim.split(' seal')[0]} — MB/s", mbps(n), mbps(r), " MB/s", True, why)

CLIENT = {
    "full:/": "New connection per request, full handshake — req/s",
    "resume:/": "New connection per request, resumed — req/s",
    "ka:/1k": "Keep-alive 1 KB — req/s",
    "ka:/1m": "Keep-alive 1 MB bodies — MB/s",
}
for case, label in CLIENT.items():
    n, r = cell("client", case, "NURL"), cell("client", case, "RUST")
    if case == "ka:/1m":
        add_focus("client (http-client vs reqwest)", label, mbps(n), mbps(r), " MB/s")
    else:
        why = ""
        if n and r and case != "ka:/1k":
            why = f"p50 {fnum(n.get('p50_us'))} vs {fnum(r.get('p50_us'))} µs per request"
        add_focus("client (http-client vs reqwest)", label, rate(n), rate(r), "/s", True, why)

# ── render ───────────────────────────────────────────────────────────
o = []
w = o.append
w("# NURL TLS benchmark — NURL vs Rust (rustls / aws-lc-rs)")
w("")
w(f"Generated `{env.get('now', '?')}` by `bench/tls_bench/run_tls.sh` (MODE=**{env.get('mode', '?')}**). "
  "**Do not edit by hand** — the next run overwrites it.")
w("")
w("Every cost a TLS 1.3 HTTP stack pays — handshakes (full, resumed, per group and certificate), "
  "the record layer on small and large responses, and the client side — measured against the stack "
  "production Rust deploys: rustls on aws-lc-rs (assembly AES-GCM and X25519, the X25519MLKEM768 hybrid), "
  "hyper on tokio, reqwest. The NURL server is the `packages/http` HttpApp, the NURL client `packages/http-client`. "
  f"Servers pinned to cores `{env.get('srv_cores', '?')}`, the load generator to `{env.get('gen_cores', '?')}`.")
w("")
w("## Where to focus")
w("")
w("NURL's result as a share of Rust's (100 % = parity; for latencies the inverse, so higher is always better), "
  "worst first. The last column is what the measurements below say the gap is made of.")
w("")
w("| # | Area | Metric | NURL | Rust | NURL / Rust | Verdict | What the gap is |")
w("|--:|---|---|--:|--:|--:|---|---|")
ranked = sorted(focus, key=lambda t: (t[0] is None, t[0] if t[0] is not None else 0))
for i, (s, area, metric, ns, rs, why) in enumerate(ranked, 1):
    w(f"| {i} | {area} | {metric} | {ns} | {rs} | {pct(s)} | {verdict(s)} | {why} |")
w("")

# Handshakes
w("## Server handshakes")
w("")
w(f"Saturation: {env.get('secs', '')} — a fresh TCP + TLS connection per request (`Connection: close`, 14-byte body), "
  "closed loop, client pins one group and AES-128-GCM. *Server CPU / handshake* is the server process's "
  "utime + stime over the cell divided by the handshakes completed. *Crypto budget* is the sum of the server's "
  "primitives for that handshake from the primitive table (key share + shared secret [+ ML-KEM encaps] [+ signature] "
  f"+ {HKDF_PER_HS}× HKDF-Expand-Label); *rest* = CPU − budget: the protocol code, allocation, the runtime and the "
  "socket I/O. A server utilisation below 85 % means the generator, not the server, set the rate (†); "
  f"‡ marks a cell with fewer than {MIN_OPS} handshakes in the window, too few for a CPU-per-handshake figure.")
w("")
w("| Handshake | Server | handshakes/s | server util | CPU / hs (µs) | crypto budget (µs) | rest (µs) | latency p50 / p99 under load (µs) | unloaded p50 (µs) | resumed |")
w("|---|---|--:|--:|--:|--:|--:|--:|--:|--:|")
for case, (label, group, cert, resumed) in CASES.items():
    for impl in IMPLS:
        c = cell("handshake", case, impl)
        l = cell("latency", case, impl)
        if not c:
            what = "0 in the window" if ran_empty("handshake", case, impl) else "failed"
            w(f"| {label} | {impl} | {what} | | | | | | {fnum(l and l.get('hs_p50_us'))} | |")
            continue
        u = util(c)
        cpu = cpu_us_per_op(c)
        b = budget(impl, group, cert, resumed)
        rest = cpu - b if None not in (cpu, b) else None
        dag = "" if u is None or u >= 0.85 else " †"
        if c["ok"] < MIN_OPS:
            dag += " ‡"
        res = f"{c['resumed'] / c['ok'] * 100:.0f} %" if resumed else "—"
        w(f"| {label} | {impl} | {fnum(rate(c))}{dag} | {pct(u)} | {fnum(cpu)} | {fnum(b)} | {fnum(rest)} | "
          f"{fnum(c.get('hs_p50_us'))} / {fnum(c.get('hs_p99_us'))} | {fnum(l and l.get('hs_p50_us'))} | {res} |")
w("")

# Records
w("## Record layer — small keep-alive requests")
w("")
w("64 keep-alive connections, `GET /1k` back to back, over TLS (AES-128-GCM) and over plaintext HTTP. "
  "*TLS overhead* is the TLS row's server CPU per request minus the plaintext row's: what the record layer "
  "costs per request-response pair.")
w("")
w("| Server | transport | req/s | server util | CPU / req (µs) | p50 / p99 (µs) | TLS overhead / req (µs) |")
w("|---|---|--:|--:|--:|--:|--:|")
for impl in IMPLS:
    for case, name in (("tls:/1k", "TLS"), ("plain:/1k", "plaintext")):
        c = cell("records", case, impl)
        if not c:
            w(f"| {impl} | {name} | failed | | | | |")
            continue
        ov = fnum(overhead_per_req(impl)) if case == "tls:/1k" else ""
        w(f"| {impl} | {name} | {fnum(rate(c))} | {pct(util(c))} | {fnum(cpu_us_per_op(c))} | "
          f"{fnum(c.get('p50_us'))} / {fnum(c.get('p99_us'))} | {ov} |")
w("")

# Bulk
w("## Bulk — one connection, 1 MB bodies")
w("")
w("One keep-alive connection downloading `/1m` back to back. *ns / KB* is server CPU per KiB delivered; the "
  "AEAD row of the primitive table is the floor a userspace record layer can reach. The kTLS row runs the NURL "
  "server with `NURL_KTLS=1`; *kTLS engaged* is the kernel's `TlsTxSw` counter over the cell — 0 means the "
  "kernel refused (no `tls` module) and the row is userspace again.")
w("")
w("| Server | suite | MB/s | server util | server ns / KB | AEAD floor ns / KB | kTLS engaged |")
w("|---|---|--:|--:|--:|--:|--:|")
for impl in IMPLS:
    for case in ("aes128", "chacha", "plain", "aes128+ktls"):
        c = cell("bulk", case, impl)
        if c is None:
            if (("bulk", case, impl)) in cells:
                w(f"| {impl} | {case} | failed | | | | |")
            continue
        p = AEAD.get(case.split("+")[0])
        fl = prim_us(impl, p) * 1000 / 16 if p and prim_us(impl, p) else None
        k = int(c.get("ktls_tx", 0)) if case.endswith("ktls") else None
        w(f"| {impl} | {case} | {fnum(mbps(c))} | {pct(util(c))} | {fnum(ns_per_kb(c))} | {fnum(fl)} | "
          f"{'—' if k is None else ('yes' if k > 0 else '**no**')} |")
w("")

# Client
w("## Client — `packages/http-client` vs reqwest")
w("")
w("Both single-threaded and sequential, both against the same Rust server, both offering their defaults "
  "(X25519MLKEM768 first). *full*: a new connection per request with resumption off (`http_client_set_resume F` / "
  "rustls `Resumption::disabled`), *resume*: a new connection per request offering the cached ticket, "
  "*ka*: one pooled keep-alive connection.")
w("")
w("| Case | Client | req/s | MB/s | p50 / p99 (µs) | errors |")
w("|---|---|--:|--:|--:|--:|")
for case in CLIENT:
    for impl, name in (("NURL", "http-client"), ("RUST", "reqwest")):
        c = cells.get(("client", case, impl))
        if not c or not c.get("ok"):
            w(f"| {case} | {name} | failed | | | {int(c.get('err', 0)) if c else ''} |")
            continue
        c = cell("client", case, impl)
        w(f"| {case} | {name} | {fnum(rate(c))} | {fnum(mbps(c))} | {fnum(c.get('p50_us'))} / {fnum(c.get('p99_us'))} | {int(c.get('err', 0))} |")
w("")

# Primitives
w("## Primitives — single core")
w("")
w(f"Medians of {env.get('secs', '').split('prim_runs=')[-1] or '?'} run(s), `bench_auto` discipline on both sides "
  "(ramp until a pass clears 50 ms). NURL is the pure-NURL stdlib; Rust is aws-lc-rs.")
w("")
w("| Primitive | NURL µs/op | Rust µs/op | NURL / Rust speed |")
w("|---|--:|--:|--:|")
names = []
for (impl, name) in prims:
    if name not in names:
        names.append(name)
for name in names:
    n, r = prim_us("NURL", name), prim_us("RUST", name)
    s = ratio_cell(n, r, False)
    w(f"| {name} | {fnum(n, nd=2 if n and n < 10 else None)} | {fnum(r, nd=2 if r and r < 10 else None)} | {pct(s)} |")
w("")

# Environment
w("## Environment")
w("")
w("| Item | Value |")
w("|---|---|")
for k, label in (("host", "Host"), ("kernel", "Kernel"), ("cpu", "CPU"), ("cores", "Logical cores"),
                 ("srv_cores", "Server cores"), ("gen_cores", "Generator cores"), ("commit", "Commit"),
                 ("run_url", "CI run"), ("nurl", "NURL"), ("rust", "Rust"), ("secs", "Cell durations (s)"),
                 ("crate_rustls", "rustls"), ("crate_aws-lc-rs", "aws-lc-rs"), ("crate_hyper", "hyper"),
                 ("crate_tokio", "tokio"), ("crate_reqwest", "reqwest")):
    if env.get(k):
        v = env[k]
        w(f"| {label} | {v if k == 'run_url' else '`' + v + '`'} |")
w("")
w("### Reading these numbers")
w("")
w("- **Read pairs, not cells.** Both servers ran on the same cores in the same run; a shared CI VM moves "
  "absolute numbers between runs by more than it moves the ratio.")
w("- **CPU per operation is the absolute number.** Rates depend on how many cores the server had; "
  "server CPU per handshake / per request / per KB does not, and it is what the crypto budget is subtracted from.")
w("- **The crypto budget is a floor, not a model.** It counts each primitive once at its single-core, "
  "warm-cache cost. *Rest* therefore also holds cache misses the microbenchmark does not see — a large *rest* "
  "with a small primitive gap points at the protocol code, the allocator or the I/O path.")
w("- **The client rows include the library.** http-client and reqwest are measured as an application calls them "
  "(pooling, header handling, response assembly), not as bare TLS.")
sys.stdout.write("\n".join(o) + "\n")
