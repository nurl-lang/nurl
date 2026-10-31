#!/usr/bin/env python3
# bench/tls_bench/gen_tls_results.py — turns run_tls.sh's raw results into
# the TLS reports, one per CPU family.
#
#   gen_tls_results.py < raw > report.md   this run's report
#   gen_tls_results.py --store DIR < raw   record the run as its CPU family's
#                                          latest (DIR/runs/<family>.tsv) and
#                                          re-render DIR's reports
#   gen_tls_results.py --render DIR        re-render DIR's reports from
#                                          DIR/runs/*.tsv
#   gen_tls_results.py --family < raw      print the run's family id
#
# DIR's reports are TLS_RESULTS.<family>.md for every recorded family and
# TLS_RESULTS.md, the index: the families side by side, worst metric first.
#
# Why per family: the GitHub runner pool hands out AMD Zen 3, AMD Zen 5 and
# Intel Ice Lake machines, and NURL's ratio to aws-lc flips with the
# family, not with the code — AES-128-GCM 179 % on Zen 3 and 83 % on Zen 5,
# RSA-2048 sign against aws-lc's IFMA path on one and its ADX path on the
# other. A single report overwritten by whichever runner a run got cannot
# close a "≤ 1.25× on the runner" task honestly (Agora #112).
#
# The family is decided by the CPU's flags, never by its model string:
# the vendor, the widest vector ISA (avx2 / avx512 / avx512ifma), then the
# extensions a crypto dispatch picks a kernel by (vaes, sha, adx). A run
# without its vendor, flags, NURL's CPU probes or a kernel line for every
# primitive it measured is refused — a report that cannot say which code
# its numbers are from is not one.
#
# Input lines (tab-separated):
#   ENV   <key> <value>
#   PROBE <name> <0|1>                             NURL's CPU answers (prims --tiers)
#   TIER  <primitive name> <kernel>                the kernel NURL engaged per row
#   P     <impl> <primitive name> <ns_per_op>      one per run; median taken
#   M     <section> <case> <impl> <key=value ...>  one per measured cell
#
# Each report leads with the focus list: every headline metric as NURL's
# share of Rust's, worst first, each with what the measurement says the
# gap is made of. Everything below it is the evidence for that table.
import os
import re
import statistics
import sys

# The CPU family, shared with every runner-measured report (bench/cpu_env.py).
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from cpu_env import family_of  # noqa: E402

IMPLS = ("NURL", "RUST")
PROBES = ("v3", "aes", "vaes", "vaes512", "sha", "adx", "ifma")
MIN_OPS = 50  # below this, work still in flight at the window's end skews CPU per operation
HKDF_PER_HS = 16  # Expand-Label calls in a TLS 1.3 server key schedule, roughly


class RunError(Exception):
    pass


# ── parsing and the family ───────────────────────────────────────────
class Run:
    def __init__(self, text):
        self.text = text
        self.env, self.prims, self.cells, self.tiers, self.probes = {}, {}, {}, {}, {}
        for line in text.splitlines():
            f = line.split("\t")
            if f[0] == "ENV" and len(f) >= 3:
                self.env[f[1]] = f[2]
            elif f[0] == "PROBE" and len(f) >= 3:
                self.probes[f[1]] = f[2]
            elif f[0] == "TIER" and len(f) >= 3:
                self.tiers[f[1]] = f[2]
            elif f[0] == "P" and len(f) >= 4:
                self.prims.setdefault((f[1], f[2]), []).append(int(f[3]))
            elif f[0] == "M" and len(f) >= 5:
                kv = {}
                for tok in f[4].split():
                    k, _, v = tok.partition("=")
                    try:
                        kv[k] = float(v)
                    except ValueError:
                        pass
                self.cells[(f[1], f[2], f[3])] = kv
        self.validate()
        self.family = family_of(self.env)

    def validate(self):
        missing = [k for k in ("cpu_vendor", "cpu_flags") if not self.env.get(k, "").strip()]
        missing += [f"PROBE {p}" for p in PROBES if self.probes.get(p) not in ("0", "1")]
        for (impl, name) in self.prims:
            if impl == "NURL" and not self.tiers.get(name):
                missing.append(f"TIER {name}")
        if missing:
            raise RunError("the raw results do not say which CPU and which NURL kernels produced them; missing: "
                           + ", ".join(missing)
                           + " (run_tls.sh writes cpu_vendor / cpu_flags into the ENV block and "
                             "`prims --tiers` the PROBE and TIER lines)")

    # measurements
    def prim_us(self, impl, name):
        v = self.prims.get((impl, name))
        return statistics.median(v) / 1000.0 if v else None

    def cell(self, sec, case, impl):
        c = self.cells.get((sec, case, impl))
        return c if c and c.get("ok", 0) > 0 and c.get("elapsed_ns", 0) > 0 else None

    def ran_empty(self, sec, case, impl):
        """The cell ran its whole window and completed nothing: a rate of 0,
        not a missing measurement."""
        c = self.cells.get((sec, case, impl))
        return bool(c) and c.get("elapsed_ns", 0) > 0 and c.get("ok", 0) == 0 and c.get("err", 0) == 0


# ── numbers ──────────────────────────────────────────────────────────
def rate(c):
    return c["ok"] * 1e9 / c["elapsed_ns"] if c else None


def mbps(c):
    return c["bytes"] * 1e3 / c["elapsed_ns"] if c else None  # bytes/ns·1e3 = MB/s


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
CASES = {
    "ec:x25519:0": ("Full · ECDSA P-256 · X25519", "x25519", "ec", False),
    "ec:x25519:1": ("Resumed · X25519 (psk_dhe_ke)", "x25519", "ec", True),
    "ec:p256:0": ("Full · ECDSA P-256 · P-256", "p256", "ec", False),
    "ec:mlkem:0": ("Full · ECDSA P-256 · X25519MLKEM768", "mlkem", "ec", False),
    "rsa:x25519:0": ("Full · RSA-2048 · X25519", "x25519", "rsa", False),
}
AEAD = {"aes128": "AES-128-GCM seal 16 KB", "chacha": "ChaCha20-Poly1305 seal 16 KB"}
CLIENT = {
    "full:/": "New connection per request, full handshake — req/s",
    "resume:/": "New connection per request, resumed — req/s",
    "ka:/1k": "Keep-alive 1 KB — req/s",
    "ka:/1m": "Keep-alive 1 MB bodies — MB/s",
}


def budget_parts(run, impl, group, cert, resumed):
    parts = []
    if group in ("x25519", "mlkem"):
        parts += ["X25519 keygen", "X25519 shared"]
    if group == "p256":
        parts += ["P-256 ECDH keygen", "P-256 ECDH shared"]
    if group == "mlkem":
        parts += ["ML-KEM-768 encaps"]
    if not resumed:
        parts += ["ECDSA P-256 sign" if cert == "ec" else "RSA-2048 PSS sign"]
    out = {p: run.prim_us(impl, p) for p in parts}
    h = run.prim_us(impl, "HKDF-Expand-Label")
    out[f"{HKDF_PER_HS}× HKDF-Expand-Label"] = h * HKDF_PER_HS if h is not None else None
    return out


def budget(run, impl, group, cert, resumed):
    parts = budget_parts(run, impl, group, cert, resumed)
    return None if any(v is None for v in parts.values()) else sum(parts.values())


def explain_hs(run, case):
    _, group, cert, resumed = CASES[case]
    n, r = run.cell("handshake", case, "NURL"), run.cell("handshake", case, "RUST")
    nc, rc = cpu_us_per_op(n), cpu_us_per_op(r)
    nb, rb = budget(run, "NURL", group, cert, resumed), budget(run, "RUST", group, cert, resumed)
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
    pn, pr = budget_parts(run, "NURL", group, cert, resumed), budget_parts(run, "RUST", group, cert, resumed)
    worst = max(pn, key=lambda k: (pn[k] or 0) - (pr[k] or 0))
    return (f"server CPU {fnum(nc)} vs {fnum(rc)} µs/handshake: of the {fnum(gap)} µs gap, "
            f"{fnum(crypto)} µs is primitive crypto (largest: {worst}, +{fnum((pn[worst] or 0) - (pr[worst] or 0))} µs), "
            f"{rest_s}")


def overhead_per_req(run, impl):
    t, p = run.cell("records", "tls:/1k", impl), run.cell("records", "plain:/1k", impl)
    a, b = cpu_us_per_op(t), cpu_us_per_op(p)
    return None if None in (a, b) else a - b


def ns_per_kb(c):
    return c["srv_cpu_ns"] / (c["bytes"] / 1024.0) if c and c.get("bytes") else None


# ── the focus list ───────────────────────────────────────────────────
def focus_rows(run):
    """[(score, area, metric, nurl_str, rust_str, why)] — every headline metric."""
    focus = []

    def add(area, metric, n, r, unit, higher_better=True, why=""):
        focus.append((ratio_cell(n, r, higher_better), area, metric, fnum(n, unit), fnum(r, unit), why))

    for case, (label, group, cert, resumed) in CASES.items():
        n, r = run.cell("handshake", case, "NURL"), run.cell("handshake", case, "RUST")
        nr = 0.0 if run.ran_empty("handshake", case, "NURL") else rate(n)
        s = ratio_cell(nr, rate(r)) if nr != 0.0 else (0.0 if rate(r) else None)
        why = explain_hs(run, case)
        if nr == 0.0:
            nb, rb = budget(run, "NURL", group, cert, resumed), budget(run, "RUST", group, cert, resumed)
            why = (f"not one handshake completed in the window; the server's primitives alone cost "
                   f"{fnum(nb)} vs {fnum(rb)} µs per handshake")
        focus.append((s, "server handshake", label + " — handshakes/s", fnum(nr, "/s"), fnum(rate(r), "/s"), why))
    for case, (label, *_rest) in CASES.items():
        n, r = run.cell("latency", case, "NURL"), run.cell("latency", case, "RUST")
        add("server handshake", label + " — unloaded latency p50",
            n and n.get("hs_p50_us"), r and r.get("hs_p50_us"), " µs", False)

    n, r = run.cell("records", "tls:/1k", "NURL"), run.cell("records", "tls:/1k", "RUST")
    on, orr = overhead_per_req(run, "NURL"), overhead_per_req(run, "RUST")
    add("record layer", "Keep-alive 1 KB over TLS — req/s", rate(n), rate(r), "/s", True,
        f"TLS adds {fnum(on)} µs CPU per request on NURL, {fnum(orr)} µs on Rust (TLS minus plaintext)" if None not in (on, orr) else "")
    n, r = run.cell("records", "plain:/1k", "NURL"), run.cell("records", "plain:/1k", "RUST")
    add("record layer", "Keep-alive 1 KB plaintext — req/s (baseline)", rate(n), rate(r), "/s", True,
        "not TLS: the HTTP/1.1 server itself")

    for suite, prim in AEAD.items():
        n, r = run.cell("bulk", suite, "NURL"), run.cell("bulk", suite, "RUST")
        why = ""
        if n and r:
            an, ar = run.prim_us("NURL", prim), run.prim_us("RUST", prim)
            why = (f"server CPU {fnum(ns_per_kb(n))} vs {fnum(ns_per_kb(r))} ns/KB; the AEAD alone is "
                   f"{fnum(an * 1000 / 16 if an else None)} vs {fnum(ar * 1000 / 16 if ar else None)} ns/KB")
        add("bulk", f"1 MB bodies, one connection, {prim.split(' seal')[0]} — MB/s", mbps(n), mbps(r), " MB/s", True, why)

    for case, label in CLIENT.items():
        n, r = run.cell("client", case, "NURL"), run.cell("client", case, "RUST")
        if case == "ka:/1m":
            add("client (http-client vs reqwest)", label, mbps(n), mbps(r), " MB/s")
        else:
            why = ""
            if n and r and case != "ka:/1k":
                why = f"p50 {fnum(n.get('p50_us'))} vs {fnum(r.get('p50_us'))} µs per request"
            add("client (http-client vs reqwest)", label, rate(n), rate(r), "/s", True, why)

    # The primitives, so a cross-family view sees a kernel's ratio move.
    for name in prim_names(run):
        n, r = run.prim_us("NURL", name), run.prim_us("RUST", name)
        if n is not None and r is not None:
            add("primitive", f"{name} — µs/op", n, r, " µs", False, f"NURL kernel: {run.tiers.get(name, '?')}")
    return focus


def prim_names(run):
    names = []
    for (impl, name) in run.prims:
        if name not in names:
            names.append(name)
    return names


def ranked(focus):
    return sorted(focus, key=lambda t: (t[0] is None, t[0] if t[0] is not None else 0))


# ── one run's report ─────────────────────────────────────────────────
def render_run(run):
    env = run.env
    o = []
    w = o.append
    w(f"# NURL TLS benchmark — NURL vs Rust (rustls / aws-lc-rs) — CPU family `{run.family}`")
    w("")
    w(f"Generated `{env.get('now', '?')}` by `bench/tls_bench/run_tls.sh` (MODE=**{env.get('mode', '?')}**) on "
      f"`{env.get('cpu', '?')}`, commit `{env.get('commit', '?')[:12]}`"
      + (f", [CI run]({env['run_url']})" if env.get("run_url") else "")
      + ". **Do not edit by hand** — the next run on this CPU family overwrites it; the index of every "
      "family is [`TLS_RESULTS.md`](TLS_RESULTS.md).")
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
      f"worst first, on CPU family `{run.family}`. The last column is what the measurements below say the gap is made of.")
    w("")
    w("| # | Area | Metric | NURL | Rust | NURL / Rust | Verdict | What the gap is |")
    w("|--:|---|---|--:|--:|--:|---|---|")
    rows = [f for f in focus_rows(run) if f[1] != "primitive"]
    for i, (s, area, metric, ns, rs, why) in enumerate(ranked(rows), 1):
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
            c = run.cell("handshake", case, impl)
            l = run.cell("latency", case, impl)
            if not c:
                what = "0 in the window" if run.ran_empty("handshake", case, impl) else "failed"
                w(f"| {label} | {impl} | {what} | | | | | | {fnum(l and l.get('hs_p50_us'))} | |")
                continue
            u = util(c)
            cpu = cpu_us_per_op(c)
            b = budget(run, impl, group, cert, resumed)
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
            c = run.cell("records", case, impl)
            if not c:
                w(f"| {impl} | {name} | failed | | | | |")
                continue
            ov = fnum(overhead_per_req(run, impl)) if case == "tls:/1k" else ""
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
            c = run.cell("bulk", case, impl)
            if c is None:
                if ("bulk", case, impl) in run.cells:
                    w(f"| {impl} | {case} | failed | | | | |")
                continue
            p = AEAD.get(case.split("+")[0])
            fl = run.prim_us(impl, p) * 1000 / 16 if p and run.prim_us(impl, p) else None
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
            c = run.cells.get(("client", case, impl))
            if not c or not c.get("ok"):
                w(f"| {case} | {name} | failed | | | {int(c.get('err', 0)) if c else ''} |")
                continue
            c = run.cell("client", case, impl)
            w(f"| {case} | {name} | {fnum(rate(c))} | {fnum(mbps(c))} | {fnum(c.get('p50_us'))} / {fnum(c.get('p99_us'))} | {int(c.get('err', 0))} |")
    w("")

    # Primitives
    w("## Primitives — single core")
    w("")
    w(f"Medians of {env.get('secs', '').split('prim_runs=')[-1] or '?'} run(s), `bench_auto` discipline on both sides "
      "(ramp until a pass clears 50 ms). NURL is the pure-NURL stdlib; Rust is aws-lc-rs. *NURL kernel* is the "
      "implementation the module says it engages on this CPU (`prims --tiers`: `aes_gcm_cpu_tier`, `rsa_cpu_tier`, …).")
    w("")
    w("| Primitive | NURL kernel | NURL µs/op | Rust µs/op | NURL / Rust speed |")
    w("|---|---|--:|--:|--:|")
    for name in prim_names(run):
        n, r = run.prim_us("NURL", name), run.prim_us("RUST", name)
        s = ratio_cell(n, r, False)
        w(f"| {name} | `{run.tiers.get(name, '?')}` | {fnum(n, nd=2 if n and n < 10 else None)} | "
          f"{fnum(r, nd=2 if r and r < 10 else None)} | {pct(s)} |")
    w("")

    # Environment
    w("## Environment")
    w("")
    w("| Item | Value |")
    w("|---|---|")
    w(f"| CPU family | `{run.family}` (vendor and flags; see bench/tls_bench/README.md) |")
    for k, label in (("host", "Host"), ("kernel", "Kernel"), ("cpu", "CPU"), ("cpu_vendor", "CPU vendor"),
                     ("cpu_flags", "CPU flags (the crypto-relevant ones present)"), ("cores", "Logical cores"),
                     ("srv_cores", "Server cores"), ("gen_cores", "Generator cores"), ("commit", "Commit"),
                     ("run_url", "CI run"), ("nurl", "NURL"), ("nurl_cpu_mask", "NURL_CPU_* masking"),
                     ("openssl_ia32cap", "OPENSSL_ia32cap (aws-lc's CPUID mask)"), ("rust", "Rust"),
                     ("secs", "Cell durations (s)"), ("crate_rustls", "rustls"), ("crate_aws-lc-rs", "aws-lc-rs"),
                     ("crate_hyper", "hyper"), ("crate_tokio", "tokio"), ("crate_reqwest", "reqwest")):
        if env.get(k):
            v = env[k]
            w(f"| {label} | {v if k == 'run_url' else '`' + v + '`'} |")
    w(f"| NURL CPU probes | `{' '.join(f'{p}={run.probes[p]}' for p in PROBES)}` |")
    w("")
    w("### Reading these numbers")
    w("")
    w("- **Read pairs, not cells.** Both servers ran on the same cores in the same run; a shared CI VM moves "
      "absolute numbers between runs by more than it moves the ratio.")
    w("- **A ratio belongs to its CPU family.** aws-lc and NURL each pick kernels by CPUID, so the same code "
      "can lead on one family and trail on another. Compare this report only with an earlier one of the same "
      "family; the index sets the families side by side.")
    w("- **CPU per operation is the absolute number.** Rates depend on how many cores the server had; "
      "server CPU per handshake / per request / per KB does not, and it is what the crypto budget is subtracted from.")
    w("- **The crypto budget is a floor, not a model.** It counts each primitive once at its single-core, "
      "warm-cache cost. *Rest* therefore also holds cache misses the microbenchmark does not see — a large *rest* "
      "with a small primitive gap points at the protocol code, the allocator or the I/O path.")
    w("- **The client rows include the library.** http-client and reqwest are measured as an application calls them "
      "(pooling, header handling, response assembly), not as bare TLS.")
    return "\n".join(o) + "\n"


# ── the index: every recorded family side by side ────────────────────
def render_index(runs):
    """runs: {family: Run}, at least one."""
    fams = sorted(runs)
    o = []
    w = o.append
    w("# NURL TLS benchmark — NURL vs Rust (rustls / aws-lc-rs), per CPU family")
    w("")
    w("Generated by `bench/tls_bench/gen_tls_results.py` from the latest `tls-bench` run of each CPU family "
      "(`bench/tls_bench/runs/<family>.tsv`). **Do not edit by hand.** The GitHub runner pool hands out several "
      "CPU families, and NURL's share of aws-lc's speed changes with the family — the kernels both sides "
      "pick by CPUID differ — so every family keeps its own latest run instead of the last run overwriting the "
      "rest. A family is named by its vendor and flags (`bench/tls_bench/README.md`), never by its model string.")
    w("")
    w("A perf task whose DONE WHEN says *on the runner* is done when it holds on **every family below**; the PR "
      "that closes it quotes each family's rows. A family whose run is older than the change being judged "
      "is stale: re-run `tls-bench` until the pool lands on it, or say the family is unmeasured.")
    w("")
    w("## Families")
    w("")
    w("| Family | CPU | Run | Commit | NURL kernels (RSA · P-256 · X25519 · AES-GCM · ChaCha20-Poly1305 · SHA-256 · ML-KEM) | Report |")
    w("|---|---|---|---|---|---|")
    for f in fams:
        r = runs[f]
        t = r.tiers
        kern = " · ".join(t.get(k, "—") for k in ("RSA-2048 PSS sign", "P-256 ECDH keygen", "X25519 shared",
                                                     "AES-128-GCM seal 16 KB", "ChaCha20-Poly1305 seal 16 KB",
                                                     "SHA-256 16 KB", "ML-KEM-768 encaps"))
        when = r.env.get("now", "?")
        if r.env.get("run_url"):
            when = f"[{when}]({r.env['run_url']})"
        w(f"| `{f}` | {r.env.get('cpu', '?')} | {when} ({r.env.get('mode', '?')}) | `{r.env.get('commit', '?')[:12]}` | "
          f"{kern} | [TLS_RESULTS.{f}.md](TLS_RESULTS.{f}.md) |")
    w("")
    w("## Where to focus — every family")
    w("")
    w("NURL's result as a share of Rust's per family (100 % = parity; for latencies and primitive times the "
      "inverse, so higher is always better), ordered by the worst family. **differs** marks a metric whose "
      "verdict is not the same on every family — read those per family, never as one number.")
    w("")
    w("| # | Area | Metric | " + " | ".join(f"`{f}`" for f in fams) + " | Across families |")
    w("|--:|---|---|" + "--:|" * len(fams) + "---|")
    table = {}
    order = []
    for f in fams:
        for (s, area, metric, _ns, _rs, _why) in focus_rows(runs[f]):
            key = (area, metric)
            if key not in table:
                table[key] = {}
                order.append(key)
            table[key][f] = s

    def worst(key):
        vals = [v for v in table[key].values() if v is not None]
        return (not vals, min(vals) if vals else 0)

    for i, key in enumerate(sorted(order, key=worst), 1):
        vals = table[key]
        verdicts = {verdict(vals.get(f)) for f in fams if vals.get(f) is not None}
        across = "**differs**" if len(verdicts) > 1 else (next(iter(verdicts)) if verdicts else "—")
        cells_ = " | ".join(pct(vals.get(f)) for f in fams)
        w(f"| {i} | {key[0]} | {key[1]} | {cells_} | {across} |")
    w("")
    return "\n".join(o) + "\n"


# ── storage ──────────────────────────────────────────────────────────
def runs_dir(d):
    return os.path.join(d, "runs")


def load_runs(d):
    runs = {}
    rd = runs_dir(d)
    if os.path.isdir(rd):
        for name in sorted(os.listdir(rd)):
            if name.endswith(".tsv"):
                with open(os.path.join(rd, name), encoding="utf-8") as fh:
                    r = Run(fh.read())
                if name != r.family + ".tsv":
                    raise RunError(f"{rd}/{name} holds a run of family {r.family}")
                runs[r.family] = r
    return runs


def render_dir(d):
    runs = load_runs(d)
    if not runs:
        raise RunError(f"no recorded runs in {runs_dir(d)}")
    for f, r in runs.items():
        with open(os.path.join(d, f"TLS_RESULTS.{f}.md"), "w", encoding="utf-8") as fh:
            fh.write(render_run(r))
    # A report whose family has no recorded run any more is stale.
    for name in os.listdir(d):
        m = re.fullmatch(r"TLS_RESULTS\.(.+)\.md", name)
        if m and m.group(1) not in runs:
            os.remove(os.path.join(d, name))
    with open(os.path.join(d, "TLS_RESULTS.md"), "w", encoding="utf-8") as fh:
        fh.write(render_index(runs))
    return runs


def store(d, run):
    os.makedirs(runs_dir(d), exist_ok=True)
    with open(os.path.join(runs_dir(d), run.family + ".tsv"), "w", encoding="utf-8") as fh:
        fh.write(run.text if run.text.endswith("\n") else run.text + "\n")
    render_dir(d)


def main(argv):
    try:
        if len(argv) == 3 and argv[1] == "--render":
            render_dir(argv[2])
            return 0
        run = Run(sys.stdin.read())
        if len(argv) == 1:
            sys.stdout.write(render_run(run))
        elif len(argv) == 2 and argv[1] == "--family":
            print(run.family)
        elif len(argv) == 3 and argv[1] == "--store":
            store(argv[2], run)
            print(os.path.join(argv[2], f"TLS_RESULTS.{run.family}.md"))
        else:
            sys.stderr.write("usage: gen_tls_results.py [--family | --store DIR] < raw  |  --render DIR\n")
            return 2
    except RunError as e:
        sys.stderr.write(f"gen_tls_results: {e}\n")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
