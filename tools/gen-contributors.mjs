// Copyright (c) 2026 The NURL Project Developers
// SPDX-License-Identifier: MIT OR Apache-2.0
// ============================================================
//  gen-contributors.mjs — render the landing page's "Built by" strip
//  from GitHub's contributor list at publish time.
//
//  The strip used to be three hand-typed <a> tags, which meant a fourth
//  contributor was invisible until someone remembered to edit HTML. The
//  list now comes from the repo's contributor API and is written into
//  index.html between the CONTRIBUTORS markers, so the page stays 100%
//  static at serve time (no JS, no fetch from the browser) and still
//  names whoever actually shipped the release it was built from.
//
//  Display names and role lines cannot come from an API — they are
//  editorial. nurlweb/contributors.json supplies them per login;
//  a contributor with no entry there gets their commit count instead.
//
//  Run it by hand any time:  node tools/gen-contributors.mjs
//  It is also part of nurlweb's `predeploy` hook.
//
//  Best-effort, like the registry figures in gen-site-facts.sh: a rate
//  limit or an offline build leaves the previous strip in place rather
//  than failing the deploy or publishing an empty one.
// ============================================================
import { readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const CONFIG = join(ROOT, "nurlweb", "contributors.json");
const HTML = join(ROOT, "nurlweb", "public", "index.html");
const BEGIN = "<!-- CONTRIBUTORS:BEGIN -->";
const END = "<!-- CONTRIBUTORS:END -->";

const REPO = process.env.NURL_REPO ?? "nurl-lang/nurl";
const API = `https://api.github.com/repos/${REPO}/contributors?per_page=100`;

// Leave the page as it stands and exit green: a publish must not fail, or
// publish a blank strip, because GitHub was unreachable for eight seconds.
function keepExisting(reason) {
    console.warn(`gen-contributors: ${reason} — leaving the existing strip in place`);
    process.exit(0);
}

function escapeHtml(text) {
    return String(text)
        .replace(/&/g, "&amp;")
        .replace(/</g, "&lt;")
        .replace(/>/g, "&gt;")
        .replace(/"/g, "&quot;");
}

let config;
try {
    config = JSON.parse(readFileSync(CONFIG, "utf8"));
} catch (err) {
    console.error(`gen-contributors: cannot read ${CONFIG}: ${err.message}`);
    process.exit(1);
}

// GitHub logins are case-insensitive and the API returns whatever casing the
// account was registered with, which is not necessarily how it is spelled in
// the config. Key the lookup on lowercase so `hindurable` still matches
// `Hindurable` instead of silently falling back to a commit count.
const people = new Map(Object.entries(config.people ?? {}).map(([login, v]) => [login.toLowerCase(), v]));
// Insertion order of `people` is the editorial order of the strip.
const curatedOrder = new Map([...people.keys()].map((login, i) => [login, i]));
const limit = Number.isInteger(config.limit) && config.limit > 0 ? config.limit : 6;
// Match on the bare login so an entry covers both `dependabot` and the
// `dependabot[bot]` form the API actually returns.
const excluded = new Set((config.exclude ?? []).map((name) => name.toLowerCase().replace(/\[bot\]$/, "")));

// A token lifts the API's 60-requests-per-hour-per-IP anonymous limit,
// which shared CI runner addresses reach on their own. Optional: without
// one this still works, it just fails more often on a busy runner.
const token = process.env.GITHUB_TOKEN || process.env.GH_TOKEN || "";
const headers = {
    accept: "application/vnd.github+json",
    "user-agent": `nurl-gen-contributors (${REPO})`,
};
if (token) headers.authorization = `Bearer ${token}`;

let payload;
try {
    const response = await fetch(API, { headers, signal: AbortSignal.timeout(8000) });
    if (!response.ok) keepExisting(`GitHub returned ${response.status} ${response.statusText}`);
    payload = await response.json();
} catch (err) {
    keepExisting(`contributor fetch failed: ${err.message}`);
}

if (!Array.isArray(payload)) keepExisting("unexpected API response shape");

// Order: the logins named in contributors.json first, in the order they are
// written there, then everyone else by commit count. Straight commit-count
// order reads as a leaderboard and buries whoever authored the thing under
// whoever touched it most; the curated prefix is the editorial answer to that,
// and the tail still means a new contributor shows up without an edit here.
const humans = payload
    .filter((c) => c && c.type === "User" && typeof c.login === "string")
    .filter((c) => !excluded.has(c.login.toLowerCase().replace(/\[bot\]$/, "")));

const contributors = humans
    .sort((a, b) => {
        const ra = curatedOrder.get(a.login.toLowerCase()) ?? Infinity;
        const rb = curatedOrder.get(b.login.toLowerCase()) ?? Infinity;
        if (ra !== rb) return ra - rb;
        return (b.contributions ?? 0) - (a.contributions ?? 0);
    })
    .slice(0, limit);

if (contributors.length === 0) keepExisting("no human contributors in the API response");

// Never let `limit` quietly hide people: say who did not make the strip.
const dropped = humans.length - contributors.length;

// GitHub serves whatever the account uploaded; ask for the size the page
// actually renders so a 460px avatar is not shipped into a 40px slot.
function avatar(contributor) {
    const url = contributor.avatar_url || `https://github.com/${contributor.login}.png`;
    return `${url}${url.includes("?") ? "&" : "?"}s=80`;
}

const entries = contributors
    .map((contributor) => {
        const entry = people.get(contributor.login.toLowerCase()) ?? {};
        const name = entry.name ?? contributor.login;
        const commits = contributor.contributions ?? 0;
        const role = entry.role ?? `${commits.toLocaleString("en-US")} commits`;
        return (
            `    <a href="${escapeHtml(contributor.html_url)}" target="_blank" rel="noopener">` +
            `<img src="${escapeHtml(avatar(contributor))}" alt="${escapeHtml(name)}" width="40" height="40" loading="lazy" />` +
            `<span>${escapeHtml(name)} <small>${escapeHtml(role)}</small></span></a>`
        );
    })
    .join("\n");

const strip = `${BEGIN}
  <!-- Generated by tools/gen-contributors.mjs from the GitHub contributor API. -->
  <!-- Do not edit by hand: the next publish overwrites it. Names and roles -->
  <!-- come from nurlweb/contributors.json. -->
  <p class="hero-contributors">
    <span>Built by</span>
${entries}
  </p>
  ${END}`;

const html = readFileSync(HTML, "utf8");
const start = html.indexOf(BEGIN);
const stop = html.indexOf(END);
if (start === -1 || stop === -1 || stop < start) {
    console.error(`gen-contributors: markers ${BEGIN} / ${END} not found in ${HTML}`);
    process.exit(1);
}

writeFileSync(HTML, html.slice(0, start) + strip + html.slice(stop + END.length));
console.log(
    `contributors → ${HTML}\n  ${contributors.length} shown: ${contributors.map((c) => c.login).join(", ")}` +
        (dropped > 0 ? `\n  ${dropped} contributor(s) over the limit of ${limit} are not on the page` : ""),
);
