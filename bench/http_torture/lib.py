#!/usr/bin/env python3
# bench/http_torture/lib.py — JSON extraction + report helpers for the
# torture harness. Kept tiny and dependency-free (stdlib only).
import json, sys

def oha_row(path):
    """Read an oha --json file, return the fields the harness reports."""
    with open(path) as f:
        d = json.load(f)
    s = d["summary"]; p = d["latencyPercentiles"]
    return {
        "rps": s["requestsPerSec"],
        "ok": s["successRate"],
        "p50": p["p50"] * 1000.0,
        "p99": p["p99"] * 1000.0,
        "p999": p["p99.9"] * 1000.0,
        "data": s.get("totalData", 0),
        "errs": d.get("errorDistribution", {}) or {},
    }

if __name__ == "__main__":
    cmd = sys.argv[1]
    if cmd == "row":  # print "rps ok p50 p99 p999" for one oha json
        r = oha_row(sys.argv[2])
        print("%.0f %.4f %.3f %.3f %.3f" % (r["rps"], r["ok"], r["p50"], r["p99"], r["p999"]))
    elif cmd == "rps":
        print("%.0f" % oha_row(sys.argv[2])["rps"])
