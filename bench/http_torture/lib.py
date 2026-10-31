#!/usr/bin/env python3
# bench/http_torture/lib.py — JSON extraction + report helpers for the
# torture harness. Kept tiny and dependency-free (stdlib only); the
# controls are tools/tests/test_http_torture_lib.py.
#
# Every cell oha measures leaves two files: CELL.json (oha -j) and
# CELL.json.env (run_torture.sh's oha_run: /proc/stat before and after,
# the wall time, the generator's CPU time and core count). From them a cell
# reports, besides its latencies:
#   errors  split into harness artefacts and server-attributable errors
#           (HARNESS below), so a nonzero server count is a finding;
#   †       steal above STEAL_MAX % of the window: the VM lost CPU to its
#           host, and coordinated-omission correction charges the stall to
#           whichever server was being measured;
#   ‡       the generator used ≥ GEN_BOUND % of its cores: the rate is
#           oha's ceiling, not the server's.
import json
import re
import statistics
import sys

STEAL_MAX = 2.0   # % of a window's CPU time stolen before a cell is marked †
GEN_BOUND = 90.0  # % of the generator cores' time oha used before a cell is marked ‡

# Errors that come from the measurement, not from the server (oha 1.8.0):
#   - "aborted due to deadline": a request still in flight when `-z` ends.
#     oha aborts it and itself leaves it out of successRate (result_data.rs);
#     an open-loop run at rate q with latency L has about q·L of them.
#   - EMFILE / EADDRNOTAVAIL: the generator's own file descriptors or
#     ephemeral ports ran out (a client-side limit; the server never saw
#     the request).
# Anything else — a reset, a connection closed mid-response, a parse
# error, a TLS alert — counts against the server, so an error type nobody
# has seen before shows up as a finding instead of being filed away.
HARNESS = (
    ("aborted due to deadline", "deadline"),
    ("(os error 24)", "EMFILE"),
    ("(os error 99)", "EADDRNOTAVAIL"),
)


def oha_json(path):
    with open(path) as f:
        return json.load(f)


def oha_row(path):
    """Read an oha --json file, return the fields the harness reports."""
    d = oha_json(path)
    s = d["summary"]
    p = d["latencyPercentiles"]
    return {
        "rps": s["requestsPerSec"],
        "ok": s["successRate"],
        "p50": p["p50"] * 1000.0,
        "p99": p["p99"] * 1000.0,
        "p999": p["p99.9"] * 1000.0,
        "data": s.get("totalData", 0),
        "errs": d.get("errorDistribution", {}) or {},
        # Exact response count from the status-code histogram. CPU per
        # request must divide by this, not by rps*duration: the latter
        # is several percent off, which is the size of the differences
        # the CPU table exists to resolve.
        "reqs": sum((d.get("statusCodeDistribution", {}) or {}).values()),
    }


# ── errors ───────────────────────────────────────────────────────────
def kind_of(msg):
    """("harness", short name) or ("server", the message, shortened)."""
    for needle, short in HARNESS:
        if needle in msg:
            return "harness", short
    m = " ".join(msg.split())
    return "server", (m if len(m) <= 48 else m[:47] + "…")


def split_errors(dist):
    """errorDistribution {message: count} → (server {msg: n}, harness {msg: n})."""
    server, harness = {}, {}
    for msg, n in (dist or {}).items():
        (harness if kind_of(msg)[0] == "harness" else server)[msg] = n
    return server, harness


def _dominant(d):
    msg = max(d, key=lambda k: (d[k], k))
    return kind_of(msg)[1]


def err_cell(paths):
    """The errors cell for one or more oha runs: server-attributable count
    and its dominant type, then the harness count and its type."""
    server, harness = {}, {}
    for p in paths:
        s, h = split_errors(oha_json(p).get("errorDistribution"))
        for k, v in s.items():
            server[k] = server.get(k, 0) + v
        for k, v in h.items():
            harness[k] = harness.get(k, 0) + v
    ns, nh = sum(server.values()), sum(harness.values())
    txt = str(ns) + (" " + _dominant(server) if ns else "")
    if nh:
        txt += " (+%d harness: %s)" % (nh, _dominant(harness))
    return txt


def err_section(cells_tsv):
    """Every distinct error message, per cell and server, with its count and
    kind. cells_tsv: one `cell<TAB>server<TAB>json` line per oha run."""
    counts, order = {}, []
    with open(cells_tsv) as f:
        for line in f:
            parts = line.rstrip("\n").split("\t")
            if len(parts) != 3:
                continue
            cell, server, path = parts
            try:
                dist = oha_json(path).get("errorDistribution") or {}
            except (OSError, ValueError):
                continue
            # Runs that share a cell (the capacity search's ramps, the
            # repeated 80 % tail) are summed into it.
            for msg, n in sorted(dist.items()):
                key = (cell, server, kind_of(msg)[0], " ".join(msg.split()).replace("|", "\\|"))
                if key not in counts:
                    order.append(key)
                counts[key] = counts.get(key, 0) + n
    rows = [k + (counts[k],) for k in order]
    out = ["### Errors by type", ""]
    if not rows:
        out.append("No errors in any cell.")
        return "\n".join(out) + "\n"
    srv = sum(r[4] for r in rows if r[2] == "server")
    out.append("Harness artefacts are errors the measurement makes (`%s`); every other "
               "message counts against the server. Server-attributable errors in this run: **%d**."
               % ("`, `".join(s for _, s in HARNESS), srv))
    out.append("")
    out.append("| Cell | Server | Kind | Error | Count |")
    out.append("|---|---|---|---|--:|")
    for cell, server, kind, msg, n in rows:
        out.append("| %s | %s | %s | %s | %d |" % (cell, server, kind, msg, n))
    return "\n".join(out) + "\n"


# ── environment per cell ─────────────────────────────────────────────
def _stat_fields(line):
    """/proc/stat's aggregate `cpu` line → (busy+idle total, iowait, steal)."""
    v = [int(x) for x in line.split()[1:]]
    v += [0] * (8 - len(v))
    # user nice system idle iowait irq softirq steal [guest guest_nice]:
    # guest time is already counted in user, so the total stops at steal.
    return sum(v[:8]), v[4], v[7]


def _secs(tok):
    """bash `times` token, e.g. 1m2.345s → 62.345."""
    m = re.fullmatch(r"(?:(\d+)m)?([\d.]+)s", tok.strip())
    return (int(m.group(1) or 0) * 60 + float(m.group(2))) if m else 0.0


def ncores(spec):
    """How many CPUs a taskset list names: "2-3" → 2, "0,4-6" → 4."""
    n = 0
    for part in spec.split(","):
        a, _, b = part.partition("-")
        n += (int(b) - int(a) + 1) if b else 1
    return n


def read_env(path):
    env = {}
    with open(path) as f:
        for line in f:
            k, _, v = line.rstrip("\n").partition("=")
            env[k] = v
    return env


def env_of(env_path):
    """{steal, iowait, gen_cpu} in % of the cell's window."""
    e = read_env(env_path)
    t0, io0, st0 = _stat_fields(e["stat0"])
    t1, io1, st1 = _stat_fields(e["stat1"])
    dt = max(t1 - t0, 1)
    user, _, sys_ = e.get("gen_times", "").partition(" ")
    wall = int(e["wall_ns"]) / 1e9
    cores = int(e.get("gen_cores", "1"))
    gen = (_secs(user) + _secs(sys_)) / (wall * cores) * 100.0 if wall > 0 else 0.0
    return {"steal": 100.0 * (st1 - st0) / dt, "iowait": 100.0 * (io1 - io0) / dt, "gen_cpu": gen}


def marks(env_paths):
    """† when any run's steal passed STEAL_MAX, ‡ when any run's generator
    passed GEN_BOUND."""
    out = ""
    envs = [env_of(p) for p in env_paths]
    if any(e["steal"] > STEAL_MAX for e in envs):
        out += "†"
    if any(e["gen_cpu"] >= GEN_BOUND for e in envs):
        out += "‡"
    return out


def env_note(env_paths):
    """The window's numbers behind the marks, for the per-cell environment table."""
    envs = [env_of(p) for p in env_paths]
    return "%.1f | %.1f | %.0f" % (max(e["steal"] for e in envs), max(e["iowait"] for e in envs),
                                   max(e["gen_cpu"] for e in envs))


# ── CPU per request, tail spread ─────────────────────────────────────
def cpu_us(ticks0, ticks1, hz, paths):
    """µs of server CPU per response over one or more runs."""
    reqs = sum(oha_row(p)["reqs"] for p in paths)
    cpu = (ticks1 - ticks0) / hz
    return cpu / reqs * 1e6 if reqs else 0.0


def spread(paths):
    """p99 and p99.9 over repeated runs of one cell, as median [min–max]."""
    rows = [oha_row(p) for p in paths]

    def one(key):
        v = sorted(r[key] for r in rows)
        return "%.2f [%.2f–%.2f]" % (statistics.median(v), v[0], v[-1])
    return one("p99"), one("p999")


# ── soak drift ───────────────────────────────────────────────────────
def soak_drift(samples_tsv, hz):
    """Samples every few seconds through one soak: `t rss_kib cpu_ticks
    stat_total stat_steal fds`. → a dict of start/end/max RSS, the RSS
    slope per minute (least squares), the server's CPU use, fd counts and
    the windows whose steal passed STEAL_MAX."""
    s = []
    with open(samples_tsv) as f:
        for line in f:
            p = line.split()
            if len(p) == 6:
                s.append([float(x) for x in p])
    if len(s) < 2:
        return None
    t = [r[0] for r in s]
    rss = [r[1] for r in s]
    n = len(s)
    mt, mr = sum(t) / n, sum(rss) / n
    var = sum((x - mt) ** 2 for x in t)
    slope = (sum((x - mt) * (y - mr) for x, y in zip(t, rss)) / var * 60.0) if var else 0.0
    stolen = []
    for a, b in zip(s, s[1:]):
        dt = b[3] - a[3]
        if dt > 0 and 100.0 * (b[4] - a[4]) / dt > STEAL_MAX:
            stolen.append("%d–%d s" % (a[0], b[0]))
    span = t[-1] - t[0]
    return {
        "rss0": rss[0], "rss1": rss[-1], "rss_max": max(rss), "slope": slope,
        "cpu": (s[-1][2] - s[0][2]) / hz / span * 100.0 if span > 0 else 0.0,
        "fd0": int(s[0][5]), "fd1": int(s[-1][5]), "fd_max": int(max(r[5] for r in s)),
        "stolen": stolen,
    }


def main(argv):
    cmd = argv[1]
    if cmd == "row":  # print "rps ok p50 p99 p999" for one oha json
        r = oha_row(argv[2])
        print("%.0f %.4f %.3f %.3f %.3f" % (r["rps"], r["ok"], r["p50"], r["p99"], r["p999"]))
    elif cmd == "rps":
        print("%.0f" % oha_row(argv[2])["rps"])
    elif cmd == "reqs":  # exact responses served, for CPU per request
        print("%d" % oha_row(argv[2])["reqs"])
    elif cmd == "errcell":  # errcell JSON... → the errors cell
        print(err_cell(argv[2:]))
    elif cmd == "errsection":  # errsection CELLS_TSV → the errors-by-type section
        sys.stdout.write(err_section(argv[2]))
    elif cmd == "marks":  # marks JSON... → † / ‡ from each JSON's .env sidecar
        print(marks([p + ".env" for p in argv[2:]]))
    elif cmd == "envnote":  # envnote JSON... → "steal | iowait | generator CPU" (max %)
        print(env_note([p + ".env" for p in argv[2:]]))
    elif cmd == "thresholds":  # "STEAL_MAX GEN_BOUND", for the report's legend
        print("%g %g" % (STEAL_MAX, GEN_BOUND))
    elif cmd == "ncores":
        print(ncores(argv[2]))
    elif cmd == "cpu_us":  # cpu_us TICKS0 TICKS1 HZ JSON...
        print("%.2f" % cpu_us(int(argv[2]), int(argv[3]), float(argv[4]), argv[5:]))
    elif cmd == "spread":  # spread JSON... → "p99 med [min–max]<TAB>p99.9 med [min–max]"
        print("\t".join(spread(argv[2:])))
    elif cmd == "soak":  # soak SAMPLES HZ → the drift cells, tab-separated
        d = soak_drift(argv[2], float(argv[3]))
        if d is None:
            print("n/a\tn/a\tn/a\tn/a\tn/a")
        else:
            print("%d→%d (max %d)\t%+.1f\t%.0f\t%d→%d (max %d)\t%s" % (
                d["rss0"], d["rss1"], d["rss_max"], d["slope"], d["cpu"],
                d["fd0"], d["fd1"], d["fd_max"], ", ".join(d["stolen"]) or "none"))
    else:
        sys.stderr.write("lib.py: unknown command %s\n" % cmd)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
