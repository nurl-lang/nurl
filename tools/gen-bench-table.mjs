// Copyright (c) 2026 The NURL Project Developers
// SPDX-License-Identifier: MIT OR Apache-2.0
// ============================================================
//  gen-bench-table.mjs — render bench/results/latest.json into the
//  landing page's "Measured, not promised" table.
//
//  The table used to be three hand-typed rows that could only be wrong.
//  Now `.github/workflows/bench.yml` runs the whole suite on a fixed
//  runner, commits `bench/results/latest.json`, and this script turns
//  that file into static HTML at publish time — so the page stays 100%
//  static at serve time (no JS, no fetch from the browser) and still
//  cannot fall behind the measurements.
//
//  Run it by hand any time:  node tools/gen-bench-table.mjs
//  It is also the second step of nurlweb's `predeploy` hook.
//
//  Only run times reach the page: compile times, the correctness gate
//  and the process-start-up floor live in bench/RESULTS.md, for readers
//  who want them.
// ============================================================
import { readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const RESULTS = join(ROOT, "bench", "results", "latest.json");
const HTML = join(ROOT, "nurlweb", "public", "index.html");
const BEGIN = "<!-- BENCH-TABLE:BEGIN -->";
const END = "<!-- BENCH-TABLE:END -->";

// Languages in column order. NURL first: it is the one the reader came for.
const COLUMNS = [
    { key: "nurl", label: "NURL", nurl: true },
    { key: "c", label: "C" },
    { key: "rust", label: "Rust" },
    { key: "node", label: "Node" },
    { key: "python", label: "Python" },
];

function die(message) {
    console.error(`gen-bench-table: ${message}`);
    process.exit(1);
}

function escapeHtml(text) {
    return String(text)
        .replace(/&/g, "&amp;")
        .replace(/</g, "&lt;")
        .replace(/>/g, "&gt;")
        .replace(/"/g, "&quot;");
}

// One unit for the whole table — milliseconds, thousands-separated — so a
// reader can compare two cells by looking at them. Switching the slow
// cells to seconds would read better in isolation and worse in a row.
function formatMs(value) {
    if (value === null || value === undefined || Number.isNaN(value)) return "n/a";
    if (value < 10) return `${value.toFixed(1)} ms`;
    return `${Math.round(value).toLocaleString("en-US")} ms`;
}

// Trim a toolchain banner ("Ubuntu clang version 18.1.3 (1ubuntu1)") down
// to something that fits in a footnote.
function shortVersion(text) {
    if (!text) return "unknown";
    const m = String(text).match(/\d+\.\d+(\.\d+)?/);
    return m ? m[0] : String(text).trim();
}

let results;
try {
    results = JSON.parse(readFileSync(RESULTS, "utf8"));
} catch (err) {
    die(
        `cannot read ${RESULTS}: ${err.message}\n` +
            "  The benchmark results are committed by .github/workflows/bench.yml.\n" +
            "  Run ./bench/bench.sh locally to regenerate them.",
    );
}

const rows = (results.benchmarks ?? []).filter((b) => b.verified !== false);
if (rows.length === 0) die("no verified benchmarks in the results file");

const skipped = (results.benchmarks ?? []).length - rows.length;
if (skipped > 0) {
    console.warn(`gen-bench-table: skipping ${skipped} row(s) that failed the correctness gate`);
}

const ageDays = (Date.now() - Date.parse(results.generated_utc)) / 86_400_000;
if (Number.isFinite(ageDays) && ageDays > 90) {
    console.warn(
        `gen-bench-table: results are ${Math.round(ageDays)} days old — ` +
            "re-run the bench workflow (Actions ▸ bench ▸ Run workflow).",
    );
}

const head = COLUMNS.map(
    (c) => `            <th class="num${c.nurl ? " nurl-col" : ""}">${c.label}</th>`,
).join("\n");

const body = rows
    .map((bench) => {
        // The fastest cell in the row glows. The comparison is on the
        // *rendered* value, so two cells that print the same number both
        // glow: highlighting 35 ms and not the 35 ms next to it would
        // read as a mistake, and at this resolution it would be one.
        const values = COLUMNS.map((c) => bench.run_ms?.[c.key] ?? null);
        const finite = values.filter((v) => typeof v === "number" && Number.isFinite(v));
        const bestLabel = finite.length > 0 ? formatMs(Math.min(...finite)) : null;

        const cells = COLUMNS.map((column, i) => {
            const label = formatMs(values[i]);
            const classes = ["num"];
            if (column.nurl) classes.push("nurl-col");
            if (bestLabel !== null && label === bestLabel) classes.push("fastest");
            return `            <td class="${classes.join(" ")}">${label}</td>`;
        }).join("\n");

        return [
            "          <tr>",
            `            <td class="lang"><code>${escapeHtml(bench.name)}</code>` +
                `<span class="bench-blurb">${escapeHtml(bench.blurb ?? "")}</span></td>`,
            cells,
            "          </tr>",
        ].join("\n");
    })
    .join("\n");

const host = results.host ?? {};
const tools = results.toolchains ?? {};
const generated = (results.generated_utc ?? "").slice(0, 10);
const commit = (results.commit ?? "").slice(0, 7);
const repo = "https://github.com/nurl-lang/nurl";
const commitLink = commit
    ? ` from commit <a href="${repo}/commit/${escapeHtml(results.commit)}" target="_blank" rel="noopener"><code>${escapeHtml(commit)}</code></a>`
    : "";

const table = `${BEGIN}
    <!-- Generated by tools/gen-bench-table.mjs from bench/results/latest.json. -->
    <!-- Do not edit by hand: the next publish overwrites it. -->
    <div class="table-scroll">
      <table class="compare-table bench-table">
        <thead>
          <tr>
            <th>Benchmark</th>
${head}
          </tr>
        </thead>
        <tbody>
${body}
        </tbody>
      </table>
    </div>

    <p class="bench-note">
      Median wall-clock milliseconds, whole process, lower is better; the fastest
      cell in each row is highlighted. Same algorithm in every language — each row is
      timed only after all five implementations print the same result, so a cell can
      never be fast by computing something else.
      Measured on ${escapeHtml(host.label ?? "unknown host")}${host.cores ? ` (${host.cores} logical cores)` : ""}
      with NURL ${escapeHtml(shortVersion(tools.nurl))} ·
      clang ${escapeHtml(shortVersion(tools.c))} ·
      rustc ${escapeHtml(shortVersion(tools.rust))} ·
      Node ${escapeHtml(shortVersion(tools.node))} ·
      Python ${escapeHtml(shortVersion(tools.python))},
      generated ${escapeHtml(generated)}${commitLink}.
      Reproduce it with <code>./bench/bench.sh</code>; sources, compile times, the
      correctness gate and the process-start-up floor are in
      <a href="${repo}/tree/main/bench" target="_blank" rel="noopener">bench/</a>.
    </p>
    ${END}`;

const html = readFileSync(HTML, "utf8");
const start = html.indexOf(BEGIN);
const stop = html.indexOf(END);
if (start === -1 || stop === -1 || stop < start) {
    die(`markers ${BEGIN} / ${END} not found in ${HTML}`);
}

writeFileSync(HTML, html.slice(0, start) + table + html.slice(stop + END.length));
console.log(
    `bench table → ${HTML}\n  ${rows.length} benchmarks × ${COLUMNS.length} languages, measured ${generated}`,
);
