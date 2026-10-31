#!/usr/bin/env python3
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
"""Controls for bench/http_torture/lib.py: why a torture cell looks the way
it does (Agora #120).

The soak's "errors" were the bare sum of oha's errorDistribution, 1 to 9 per
server on every run and never 0, so nobody could tell a server fault from
the measurement. lib.py now splits every cell's errors into harness
artefacts (a request still in flight when `-z` ends, the generator's own fd
or port limits) and server-attributable ones, and marks a cell whose window
lost CPU to the VM's host (†) or whose generator was saturated (‡).

The two oha JSON fixtures are real oha 1.8.0 output, captured with
`oha --no-tui -j -z 2s -q 400 -c 8 http://127.0.0.1:PORT/`:
  - errors.json against a keep-alive server that resets every 7th request's
    connection (SO_LINGER 0): oha reports those as `connection error`, a
    server-attributable error, beside its own deadline aborts;
  - clean.json against a well-behaved server, `-w` (wait for in-flight
    requests at the deadline): an empty errorDistribution.
"""
import os
import subprocess
import sys
import tempfile
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
HT = os.path.join(ROOT, "bench", "http_torture")
FIX = os.path.join(ROOT, "tools", "tests", "fixtures", "http_torture")
sys.path.insert(0, HT)
import lib  # noqa: E402

ERRORS = os.path.join(FIX, "errors.json")
CLEAN = os.path.join(FIX, "clean.json")


def stat_line(user, system, idle, iowait, steal):
    return "cpu  %d 0 %d %d %d 0 0 %d 0 0" % (user, system, idle, iowait, steal)


def write_env(path, steal, gen_secs, wall=10.0, cores=2, iowait=0):
    """A .env sidecar as oha_run writes it: steal and iowait in ticks out
    of 10000 over the window, the generator's CPU time in seconds."""
    with open(path, "w") as f:
        f.write("stat0=%s\n" % stat_line(1000, 1000, 1000, 0, 0))
        busy = 10000 - steal - iowait
        f.write("stat1=%s\n" % stat_line(1000 + busy // 2, 1000 + busy - busy // 2, 1000, iowait, steal))
        f.write("wall_ns=%d\n" % int(wall * 1e9))
        f.write("gen_times=0m%.3fs 0m%.3fs\n" % (gen_secs * 0.75, gen_secs * 0.25))
        f.write("gen_cores=%d\n" % cores)


class Errors(unittest.TestCase):
    def test_fixtures_are_what_they_claim(self):
        server, harness = lib.split_errors(lib.oha_json(ERRORS)["errorDistribution"])
        self.assertTrue(server, "errors.json has a server-attributable error")
        self.assertTrue(harness, "errors.json has a harness artefact")
        self.assertEqual(lib.oha_json(CLEAN).get("errorDistribution") or {}, {})

    def test_kinds(self):
        self.assertEqual(lib.kind_of("aborted due to deadline"), ("harness", "deadline"))
        self.assertEqual(lib.kind_of("Too many open files (os error 24)"), ("harness", "EMFILE"))
        self.assertEqual(lib.kind_of("Cannot assign requested address (os error 99)"), ("harness", "EADDRNOTAVAIL"))
        # Anything unrecognised is the server's: a new error type is a
        # finding, never filed away as noise.
        self.assertEqual(lib.kind_of("Connection reset by peer (os error 104)")[0], "server")
        self.assertEqual(lib.kind_of("some message oha 1.9 might invent")[0], "server")

    def test_cell_names_both_counts(self):
        server, harness = lib.split_errors(lib.oha_json(ERRORS)["errorDistribution"])
        cell = lib.err_cell([ERRORS])
        ns, nh = sum(server.values()), sum(harness.values())
        self.assertTrue(cell.startswith("%d " % ns), cell)
        self.assertIn("(+%d harness: deadline)" % nh, cell)
        self.assertEqual(lib.err_cell([CLEAN]), "0")
        # Runs of one cell add up.
        self.assertTrue(lib.err_cell([ERRORS, ERRORS, CLEAN]).startswith("%d " % (2 * ns)))

    def test_section_lists_every_message(self):
        with tempfile.TemporaryDirectory() as d:
            cells = os.path.join(d, "cells.tsv")
            with open(cells, "w") as f:
                f.write("16k load 80%%\tNURL\t%s\n" % ERRORS)
                f.write("16k load 80%%\tNURL\t%s\n" % ERRORS)
                f.write("16k load 80%%\tRUST\t%s\n" % CLEAN)
            sec = lib.err_section(cells)
            dist = lib.oha_json(ERRORS)["errorDistribution"]
            for msg, n in dist.items():
                kind = lib.kind_of(msg)[0]
                # Two runs of one cell are one row, their counts summed.
                self.assertIn("| 16k load 80%% | NURL | %s | %s | %d |" % (kind, " ".join(msg.split()), 2 * n), sec)
            self.assertNotIn("| RUST |", sec)
            server = sum(n for m, n in dist.items() if lib.kind_of(m)[0] == "server")
            self.assertIn("Server-attributable errors in this run: **%d**" % (2 * server), sec)
            with open(cells, "w") as f:
                f.write("1k churn\tNURL\t%s\n" % CLEAN)
            self.assertIn("No errors in any cell.", lib.err_section(cells))


class Environment(unittest.TestCase):
    def test_marks(self):
        with tempfile.TemporaryDirectory() as d:
            calm, stolen, busy = (os.path.join(d, n) for n in ("calm.env", "stolen.env", "busy.env"))
            write_env(calm, steal=100, gen_secs=10.0)       # 1 % steal, generator at 50 %
            write_env(stolen, steal=300, gen_secs=10.0)     # 3 % steal
            write_env(busy, steal=0, gen_secs=18.5)         # generator at 92.5 % of 2 cores
            self.assertEqual(lib.marks([calm]), "")
            self.assertEqual(lib.marks([stolen]), "†")
            self.assertEqual(lib.marks([busy]), "‡")
            self.assertEqual(lib.marks([calm, stolen, busy]), "†‡")
            e = lib.env_of(busy)
            self.assertAlmostEqual(e["gen_cpu"], 92.5, places=3)
            self.assertAlmostEqual(lib.env_of(stolen)["steal"], 3.0, places=3)

    def test_ncores(self):
        self.assertEqual(lib.ncores("2-3"), 2)
        self.assertEqual(lib.ncores("6-11"), 6)
        self.assertEqual(lib.ncores("0,4-6"), 4)

    def test_times_parse(self):
        self.assertAlmostEqual(lib._secs("1m2.345s"), 62.345)
        self.assertAlmostEqual(lib._secs("0m0.010s"), 0.01)


class Measures(unittest.TestCase):
    def test_cpu_per_request_divides_by_responses(self):
        reqs = lib.oha_row(CLEAN)["reqs"]
        self.assertGreater(reqs, 0)
        # 100 ticks at 100 Hz = 1 s of CPU over `reqs` responses.
        self.assertAlmostEqual(lib.cpu_us(0, 100, 100.0, [CLEAN]), 1e6 / reqs)
        self.assertAlmostEqual(lib.cpu_us(0, 100, 100.0, [CLEAN, CLEAN]), 1e6 / (2 * reqs))

    def test_spread(self):
        p99, p999 = lib.spread([CLEAN, ERRORS, CLEAN])
        self.assertRegex(p99, r"^\d+\.\d\d \[\d+\.\d\d–\d+\.\d\d\]$")
        self.assertRegex(p999, r"^\d+\.\d\d \[\d+\.\d\d–\d+\.\d\d\]$")

    def test_soak_drift(self):
        with tempfile.TemporaryDirectory() as d:
            smp = os.path.join(d, "s")
            with open(smp, "w") as f:
                # t rss ticks stat_total stat_steal fds: RSS grows 60 KiB a
                # minute, the 20–30 s window loses 5 % to steal.
                for i, t in enumerate(range(0, 70, 10)):
                    steal = 0 if t < 30 else 50
                    f.write("%d %d %d %d %d %d\n" % (t, 1000 + t, t * 100, t * 100, steal, 10 + i))
            dr = lib.soak_drift(smp, 100.0)
            self.assertEqual((dr["rss0"], dr["rss1"], dr["rss_max"]), (1000, 1060, 1060))
            self.assertAlmostEqual(dr["slope"], 60.0)
            self.assertEqual(dr["stolen"], ["20–30 s"])
            self.assertEqual((dr["fd0"], dr["fd1"], dr["fd_max"]), (10, 16, 16))
            self.assertAlmostEqual(dr["cpu"], 100.0)


class Cli(unittest.TestCase):
    def run_lib(self, *args):
        return subprocess.run([sys.executable, os.path.join(HT, "lib.py"), *args],
                              capture_output=True, text=True, check=True).stdout

    def test_cli(self):
        self.assertEqual(self.run_lib("errcell", CLEAN).strip(), "0")
        self.assertEqual(len(self.run_lib("row", ERRORS).split()), 5)
        self.assertEqual(self.run_lib("thresholds").split(), ["2", "90"])


if __name__ == "__main__":
    unittest.main(verbosity=1)
