// webgpu_chrome.mjs — run a WebGPU test module in headless Chrome.
//
//   node tests/webgpu_chrome.mjs <root-dir> <module-path> [json-args]
//
// Serves <root-dir> over http://127.0.0.1 (a secure context, with the
// COOP/COEP headers SharedArrayBuffer needs), opens a page that imports
// /<module-path> and awaits its default export `(args, log) → exit code`,
// relays the page's log, and exits with that code. Chrome's own WebGPU
// (Dawn) compiles and runs the WGSL — on the machine's GPU when the
// browser exposes one, else on SwiftShader (headless Chrome's software
// Vulkan), which is slow but a real WebGPU implementation.
//
// Exit 0/1 = the module's verdict, 2 = no WebGPU adapter, 3 = no
// Chrome / puppeteer here (the caller treats 2 and 3 as SKIP).
// Env: CHROME (browser binary; default /usr/bin/google-chrome, else
// puppeteer's own), NURL_PUPPETEER (path of a puppeteer package when it
// is not resolvable from here), WEBGPU_TIMEOUT_S (default 600).

import { createServer } from "node:http";
import { readFile, stat } from "node:fs/promises";
import { createRequire } from "node:module";
import { existsSync } from "node:fs";
import { resolve, extname, join } from "node:path";

const [root, modPath, argsJson] = process.argv.slice(2);
if (!root || !modPath) { console.error("usage: webgpu_chrome.mjs <root-dir> <module-path> [json-args]"); process.exit(64); }

const require = createRequire(import.meta.url);
let puppeteer;
try { puppeteer = require(process.env.NURL_PUPPETEER || "puppeteer"); }
catch { console.log("SKIP: puppeteer not found (set NURL_PUPPETEER=<path to a puppeteer package>)"); process.exit(3); }
const chrome = process.env.CHROME || (existsSync("/usr/bin/google-chrome") ? "/usr/bin/google-chrome" : undefined);

const TYPES = { ".js": "text/javascript", ".mjs": "text/javascript", ".html": "text/html", ".wasm": "application/wasm", ".json": "application/json" };
const page_html = `<!doctype html><meta charset="utf-8"><script type="module">
const log = (s) => console.log(String(s));
try {
  const m = await import(${JSON.stringify("/" + modPath)});
  window.__exit = await m.default(${argsJson || "[]"}, log);
} catch (e) { console.log("ERROR " + (e && e.stack || e)); window.__exit = 1; }
</script>`;
const rootAbs = resolve(root);
const server = createServer(async (req, res) => {
  res.setHeader("Cross-Origin-Opener-Policy", "same-origin");
  res.setHeader("Cross-Origin-Embedder-Policy", "require-corp");
  const url = decodeURIComponent(new URL(req.url, "http://x").pathname);
  if (url === "/__run.html") { res.setHeader("content-type", "text/html"); res.end(page_html); return; }
  if (url === "/favicon.ico") { res.statusCode = 204; res.end(); return; }
  const file = resolve(join(rootAbs, url));
  if (!file.startsWith(rootAbs)) { res.statusCode = 403; res.end(); return; }
  try {
    if (!(await stat(file)).isFile()) throw 0;
    res.setHeader("content-type", TYPES[extname(file)] || "application/octet-stream");
    res.end(await readFile(file));
  } catch { res.statusCode = 404; res.end(); }
});
await new Promise((r) => server.listen(0, "127.0.0.1", r));

let browser;
try {
  browser = await puppeteer.launch({ executablePath: chrome, headless: true,
    args: ["--no-sandbox", "--enable-unsafe-webgpu", "--enable-features=Vulkan", "--ignore-gpu-blocklist"] });
} catch (e) { console.log("SKIP: cannot start Chrome: " + e.message); server.close(); process.exit(3); }
const page = await browser.newPage();
page.on("console", (m) => console.log(m.text()));
page.on("pageerror", (e) => console.log("pageerror: " + e.message));
await page.goto(`http://127.0.0.1:${server.address().port}/__run.html`);
const limit = Number(process.env.WEBGPU_TIMEOUT_S || 600);
let code;
try {
  await page.waitForFunction("window.__exit !== undefined", { timeout: limit * 1000, polling: 250 });
  code = await page.evaluate("window.__exit");
} catch { console.log(`TIMEOUT after ${limit}s`); code = 1; }
await browser.close();
server.close();
process.exit(code);
