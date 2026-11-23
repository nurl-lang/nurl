// packages/map-anything/src/ui.nu — the page `map-anything serve` answers
// GET / with.
//
// One self-contained document, no build step and no CDN: the markup, the
// style and the script are a string in the binary, so an installed tool
// serves a working page with nothing next to it. It talks only to the
// service's own JSON endpoints (see serve.nu), so everything it does is
// reachable with curl too.
//
// The flow: pick photos or one video → POST /api/jobs makes a job → each
// file goes up as raw PUT bodies — whole up to 32 MiB, larger ones read as
// a stream and sent in 32 MiB pieces the server appends at ?offset= (no
// multipart, and the body cap stays small) — stored as
// "<position>_<name>" so two names that clean to the same text cannot
// collide and the name order is the selection order → POST
// /api/jobs/:id/start queues it →
// the list polls /api/jobs while anything is queued or running. A finished
// job opens in the ply viewer (/view?cloud=...) or downloads as a PLY.
//
// NURL strings are backtick-delimited and read `\n` `\t` `\r` `\\` as
// escapes, so the script below uses no template literals and no backslash.

@ mas_ui_html → s {
    ^ `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>map-anything</title>
<style>
:root { color-scheme: dark; --bg:#0b0d10; --panel:#12161b; --line:#232a33; --ink:#e8eef4;
        --dim:#8b98a6; --faint:#5d6875; --accent:#4f9cf9; --ok:#4fc38a; --bad:#ff7a7a; --warn:#f2c14e; }
* { box-sizing: border-box; }
[hidden] { display: none !important; }
html, body { margin: 0; background: var(--bg); color: var(--ink);
             font: 14px/1.5 ui-sans-serif, system-ui, -apple-system, "Segoe UI", sans-serif; }
main { max-width: 980px; margin: 0 auto; padding: 28px 18px 60px; }
header { display: flex; align-items: baseline; gap: 14px; margin-bottom: 18px; flex-wrap: wrap; }
h1 { font-size: 20px; margin: 0; letter-spacing: .01em; }
header .sub { color: var(--dim); font-size: 13px; }
h2 { font-size: 14px; margin: 0 0 12px; color: var(--dim); font-weight: 600; text-transform: uppercase; letter-spacing: .06em; }
.card { background: var(--panel); border: 1px solid var(--line); border-radius: 10px; padding: 16px; margin-bottom: 18px; }
#drop { border: 1.5px dashed #33404d; border-radius: 9px; padding: 26px 16px; text-align: center;
        color: var(--dim); cursor: pointer; transition: border-color .15s, background .15s; }
#drop.over, #drop:hover { border-color: var(--accent); background: rgba(79,156,249,.06); }
#drop b { color: var(--ink); }
#picked { margin-top: 10px; color: var(--dim); font-size: 13px; min-height: 1.5em; }
#thumbs { display: flex; flex-wrap: wrap; gap: 6px; margin-top: 8px; }
#thumbs img { width: 64px; height: 48px; object-fit: cover; border-radius: 4px; border: 1px solid var(--line); }
.opts { display: grid; grid-template-columns: repeat(auto-fill, minmax(170px, 1fr)); gap: 12px 16px; margin-top: 16px; }
.opts label { display: block; color: var(--dim); font-size: 12px; margin-bottom: 3px; }
.opts input[type=number], .opts input[type=text] { width: 100%; background: #0e1216; color: var(--ink);
        border: 1px solid #2c3540; border-radius: 6px; padding: 6px 8px; font: inherit; }
.opts .wide { grid-column: 1 / -1; }
.opts .pair { display: flex; gap: 10px; align-items: center; }
.opts .pair input[type=range] { flex: 1; accent-color: var(--accent); }
.opts .pair input[type=number] { width: 90px; flex: none; }
.opts .chk { display: flex; align-items: center; gap: 8px; padding-top: 20px; color: var(--ink); font-size: 13px; }
.hint { color: var(--faint); font-size: 11.5px; margin-top: 2px; }
.row { display: flex; gap: 10px; align-items: center; flex-wrap: wrap; margin-top: 16px; }
button, a.btn { background: #1a2029; color: var(--ink); border: 1px solid #2c3540; border-radius: 6px;
        padding: 6px 12px; font: inherit; font-size: 13px; cursor: pointer; text-decoration: none; display: inline-block; }
button:hover, a.btn:hover { background: #222a35; }
button.primary { background: var(--accent); border-color: var(--accent); color: #06121f; font-weight: 600; }
button.primary:hover { filter: brightness(1.08); }
button:disabled { opacity: .5; cursor: default; }
button.danger:hover { border-color: var(--bad); color: var(--bad); }
.bar { height: 4px; background: var(--line); border-radius: 2px; overflow: hidden; flex: 1; min-width: 120px; }
.bar i { display: block; height: 100%; width: 0; background: var(--accent); transition: width .2s; }
#upmsg { color: var(--dim); font-size: 13px; }
.job { border-top: 1px solid var(--line); padding: 12px 0; }
.job:first-of-type { border-top: 0; padding-top: 0; }
.jtop { display: flex; gap: 10px; align-items: center; flex-wrap: wrap; }
.jname { font-weight: 600; word-break: break-all; }
.badge { font-size: 11px; padding: 1px 8px; border-radius: 10px; border: 1px solid; text-transform: uppercase; letter-spacing: .05em; }
.st-done { color: var(--ok); } .st-failed { color: var(--bad); } .st-running { color: var(--accent); }
.st-queued { color: var(--warn); } .st-uploading { color: var(--dim); }
.jmeta { color: var(--faint); font-size: 12px; margin-top: 2px; }
.jprog { color: var(--dim); font-family: ui-monospace, Menlo, Consolas, monospace; font-size: 12px; margin-top: 4px; white-space: pre-wrap; word-break: break-all; }
.jact { display: flex; gap: 6px; flex-wrap: wrap; margin-top: 8px; }
pre.log { background: #0e1216; border: 1px solid var(--line); border-radius: 6px; padding: 8px 10px; font-size: 11.5px;
          max-height: 280px; overflow: auto; color: var(--dim); white-space: pre-wrap; margin: 8px 0 0; }
.empty { color: var(--faint); }
footer { color: var(--faint); font-size: 12px; margin-top: 24px; }
footer a { color: var(--dim); }
</style>
</head>
<body>
<main>
<header>
  <h1>map-anything</h1>
  <span class="sub">photos or a video in &rarr; a metric 3-D point cloud out</span>
</header>

<section class="card">
  <h2>New reconstruction</h2>
  <div id="drop" tabindex="0" role="button" aria-controls="file">
    <b>Drop photos or one video here</b>, or click to choose.<br>
    <span class="hint">JPG / PNG photos of one scene, or one video (mp4, mov, mkv, webm, avi) &mdash; up to 2 GB a file</span>
  </div>
  <input id="file" type="file" multiple accept="image/jpeg,image/png,video/*" hidden>
  <div id="picked"></div>
  <div id="thumbs"></div>

  <div class="opts">
    <div><label for="o-name">name</label><input id="o-name" type="text" placeholder="from the first file"></div>
    <div class="wide"><label for="o-max" id="o-max-label">views to use</label>
      <div class="pair"><input id="o-max-r" type="range" min="4" max="120" step="1" value="24" aria-label="views to use">
      <input id="o-max" type="number" min="0" max="2000" value="24"></div>
      <div class="hint" id="o-max-hint">spread over the whole capture, the sharpest of each run; 0 = every frame</div></div>
    <div><label for="o-stride">take every Nth input</label><input id="o-stride" type="number" min="1" max="100" value="1"></div>
    <div><label for="o-px">pixel stride</label><input id="o-px" type="number" min="1" max="16" value="1">
      <div class="hint">2 = &frac14; of the points, a lighter cloud</div></div>
    <div><label for="o-conf">drop least confident %</label><input id="o-conf" type="number" min="0" max="95" value="0"></div>
    <div><label for="o-win">attention window</label><input id="o-win" type="number" min="4" max="64" value="24">
      <div class="hint">views per window; lower if the GPU runs out</div></div>
    <div><label for="o-align">align views (sweeps)</label><input id="o-align" type="number" min="0" max="10" value="3">
      <div class="hint">merges the double copies of walls; 0 = off</div></div>
    <div><label for="o-mv">views that must agree</label><input id="o-mv" type="number" min="0" max="4" value="1">
      <div class="hint">drops floaters only one view sees; 0 = off</div></div>
    <div><label for="o-vox">voxel size (mm)</label><input id="o-vox" type="text" value="auto">
      <div class="hint">auto, off, or millimetres: one averaged point per cell</div></div>
    <div class="chk"><input id="o-sky" type="checkbox"><label for="o-sky" style="margin:0;color:inherit;font-size:13px">mask sky (outdoor)</label></div>
  </div>

  <div class="row">
    <button id="go" class="primary" disabled>Reconstruct</button>
    <div class="bar" id="upbar" hidden><i></i></div>
    <span id="upmsg"></span>
  </div>
</section>

<section class="card">
  <h2>Jobs</h2>
  <div id="jobs"><div class="empty">loading&hellip;</div></div>
</section>

<footer>
  A NURL port of Meta's <a href="https://github.com/facebookresearch/map-anything">MapAnything</a>
  (facebook/map-anything-apache). One job runs on the GPU at a time; the rest wait in the queue.
</footer>
</main>

<script>
"use strict";
var $ = function (id) { return document.getElementById(id); };
var picked = [];
var videoSecs = 0;  // the picked video's length, once the browser has read it
var uploading = false;  // one upload at a time; picking waits for it
var CHUNK = 32 * 1048576;
var openLogs = {};
var CR = String.fromCharCode(13), LF = String.fromCharCode(10);

function isVideo(f) { return /^video[/]/.test(f.type) || /[.](mp4|mov|mkv|m4v|webm|avi)$/i.test(f.name); }
function isImage(f) { return /[.](jpe?g|png)$/i.test(f.name) || f.type === "image/jpeg" || f.type === "image/png"; }
function mb(n) { return n >= 1048576 ? (n / 1048576).toFixed(1) + " MB" : Math.max(1, Math.round(n / 1024)) + " kB"; }
function safe(name) { return name.replace(/[^A-Za-z0-9._-]/g, "_").replace(/^[.]/, "_"); }
function dur(ms) {
  var s = Math.round(ms / 1000);
  if (s < 60) return s + " s";
  return Math.floor(s / 60) + " min " + (s % 60) + " s";
}
function when(ms) {
  var d = new Date(ms);
  return d.toLocaleDateString() + " " + d.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" });
}

function pick(files) {
  if (uploading) { $("picked").textContent = "wait for the current upload to finish"; return; }
  var vids = [], imgs = [], skipped = 0;
  for (var i = 0; i < files.length; i++) {
    var f = files[i];
    if (isVideo(f)) vids.push(f); else if (isImage(f)) imgs.push(f); else skipped++;
  }
  var msg = "";
  if (vids.length > 1 || (vids.length && imgs.length)) {
    picked = [];
    msg = "Choose either one video or a set of photos, not both.";
  } else {
    picked = vids.length ? vids : imgs.sort(function (a, b) { return a.name < b.name ? -1 : a.name > b.name ? 1 : 0; });
    var total = 0;
    picked.forEach(function (f) { total += f.size; });
    if (picked.length) msg = (vids.length ? "1 video" : picked.length + " photo" + (picked.length > 1 ? "s" : "")) + ", " + mb(total);
    if (skipped) msg += (msg ? " — " : "") + skipped + " unsupported file" + (skipped > 1 ? "s" : "") + " skipped";
  }
  $("picked").textContent = msg;
  $("go").disabled = picked.length === 0;
  var th = $("thumbs");
  th.textContent = "";
  picked.slice(0, 24).forEach(function (f) {
    if (!isImage(f)) return;
    var im = document.createElement("img");
    im.src = URL.createObjectURL(f);
    im.onload = function () { URL.revokeObjectURL(im.src); };
    th.appendChild(im);
  });
  if (!$("o-name").value && picked.length) $("o-name").placeholder = picked[0].name.replace(/[.][^.]*$/, "");
  videoSecs = 0;
  if (vids.length === 1) {
    /* the length, read by the browser itself, so the hint can say how
       densely the frames will sample it */
    /* a later pick may finish reading first: only this pick's answer counts */
    var mine = vids[0];
    var v = document.createElement("video");
    v.preload = "metadata";
    v.onloadedmetadata = function () {
      URL.revokeObjectURL(v.src);
      if (picked.length !== 1 || picked[0] !== mine) return;
      if (isFinite(v.duration)) videoSecs = v.duration;
      viewsHint();
    };
    v.onerror = function () { URL.revokeObjectURL(v.src); };
    v.src = URL.createObjectURL(vids[0]);
  }
  viewsHint();
}

function secs(t) {
  if (t < 60) return (t < 10 ? t.toFixed(1) : Math.round(t)) + " s";
  return Math.floor(t / 60) + " min " + Math.round(t % 60) + " s";
}
/* What the views control will do with what is picked, in words. */
function viewsHint() {
  var n = num("o-max", 0, 2000, 24), isVid = picked.length === 1 && isVideo(picked[0]);
  $("o-max-label").textContent = isVid ? "frames across the video" : "views to use";
  var h;
  if (n === 0) h = isVid ? "every frame at 2 frames/s — long videos are stitched from windows" : "every photo";
  else if (isVid) {
    h = n + " frames spread over the whole video, each the sharpest of 3 candidates";
    if (videoSecs > 0) h += " — one every " + secs(videoSecs / n) + " of " + secs(videoSecs);
  } else if (picked.length > n) h = n + " of " + picked.length + " photos, spread evenly, the sharpest of each run";
  else if (picked.length) h = "all " + picked.length + " photos";
  else h = "spread over the whole capture, the sharpest of each run; 0 = every frame";
  if (n > num("o-win", 4, 64, 24)) h += " · more than one window: stitched";
  $("o-max-hint").textContent = h;
}

var drop = $("drop");
drop.onclick = function () { $("file").click(); };
drop.onkeydown = function (e) { if (e.key === "Enter" || e.key === " ") { e.preventDefault(); $("file").click(); } };
$("file").onchange = function () { pick(this.files); };
["dragenter", "dragover"].forEach(function (ev) {
  drop.addEventListener(ev, function (e) { e.preventDefault(); drop.classList.add("over"); });
});
["dragleave", "drop"].forEach(function (ev) {
  drop.addEventListener(ev, function (e) { e.preventDefault(); drop.classList.remove("over"); });
});
drop.addEventListener("drop", function (e) { pick(e.dataTransfer.files); });
$("o-max-r").oninput = function () { $("o-max").value = this.value; viewsHint(); };
$("o-max").oninput = function () {
  var v = parseInt(this.value, 10);
  if (!isNaN(v) && v >= 4 && v <= 120) $("o-max-r").value = v;
  viewsHint();
};
$("o-win").addEventListener("input", viewsHint);

function api(method, url, body) {
  return fetch(url, {
    method: method,
    headers: body === undefined ? {} : { "Content-Type": "application/json" },
    body: body === undefined ? undefined : JSON.stringify(body),
    credentials: "same-origin"
  }).then(function (r) {
    return r.json().catch(function () { return {}; }).then(function (j) {
      if (!r.ok) throw new Error(j.error || ("HTTP " + r.status));
      return j;
    });
  });
}

/* the position, zero-padded to the width of the largest one (at least
   four digits) and never cut, so every prefix in a selection differs */
function padTo(n, total) {
  var w = Math.max(4, String(total).length), t = String(n);
  while (t.length < w) t = "0" + t;
  return t;
}

/* one piece of a file: bytes [off, off + piece.size) */
/* One PUT. A network failure is retried twice after a pause: the body is
   either the File itself or bytes already in memory, so it can be sent
   again. Only a status 0 (no response at all) counts as a network failure. */
function putPiece(url, body, onprog) {
  var tries = 0;
  function once() {
    return new Promise(function (ok, bad) {
      var x = new XMLHttpRequest();
      x.open("PUT", url);
      x.setRequestHeader("Content-Type", "application/octet-stream");
      x.upload.onprogress = function (e) { if (e.lengthComputable) onprog(e.loaded); };
      x.onload = function () {
        if (x.status >= 200 && x.status < 300) ok();
        else {
          var m = "HTTP " + x.status;
          try { m = JSON.parse(x.responseText).error || m; } catch (e) {}
          if (x.status === 413) m = "the file is too large for the server";
          var err = new Error(m); err.status = x.status;
          bad(err);
        }
      };
      x.onerror = function () { var err = new Error("network error during the upload"); err.status = 0; bad(err); };
      x.send(body);
    }).catch(function (e) {
      if (e.status !== 0 || tries >= 2) throw e;
      tries++;
      return new Promise(function (r) { setTimeout(r, 1500 * tries); }).then(once);
    });
  }
  return once();
}

/* The whole file. Up to CHUNK it goes as the File itself, in one PUT — the
   way a phone's browser reads a picked file most reliably. A larger file
   is READ FROM START TO END as a stream and sent in pieces of exactly CHUNK
   bytes from memory (the last shorter), never through file.slice(): on
   Android, a file picked from the gallery is a content:// document, and
   reading a slice of one can fail, which XHR reports as nothing more than
   a network error. A read that fails says so. Only a browser without
   file.stream falls back to slices. Every body stays within the server's
   40 MiB cap. */
function put(url, file, onprog) {
  if (file.size <= CHUNK) return putPiece(url + "?offset=0", file, onprog);
  var off = 0;
  /* one piece of exactly n bytes (the last may be shorter), from memory */
  function sendPiece(body, n) {
    var here = off;
    off += n;
    return putPiece(url + "?offset=" + here, body, function (k) { onprog(here + k); });
  }
  if (!file.stream) {
    /* no stream API: bounded slices, the only way left to stay under the
       server's body cap */
    var next = function () {
      if (off >= file.size) return Promise.resolve();
      var end = Math.min(file.size, off + CHUNK);
      return sendPiece(file.slice(off, end), end - off).then(next);
    };
    return next();
  }
  var reader = file.stream().getReader();
  var parts = [], have = 0;
  /* take exactly n buffered bytes, splitting a stream chunk if it straddles
     the boundary and keeping its remainder for the next piece */
  function take(n) {
    var out = [], need = n;
    while (need > 0) {
      var p = parts[0];
      if (p.byteLength <= need) { out.push(p); parts.shift(); need -= p.byteLength; }
      else { out.push(p.subarray(0, need)); parts[0] = p.subarray(need); need = 0; }
    }
    have -= n;
    return new Blob(out);
  }
  function drain() {
    if (have < CHUNK) return Promise.resolve();
    return sendPiece(take(CHUNK), CHUNK).then(drain);
  }
  function pump() {
    return reader.read().then(function (r) {
      if (r.done) { var n = have; return n > 0 ? sendPiece(take(n), n) : null; }
      parts.push(r.value); have += r.value.byteLength;
      return drain().then(pump);
    }, function (e) {
      throw new Error("this device could not read " + file.name + " (" + (e && e.name || e) + ")");
    });
  }
  return pump();
}

function voxelMm() {
  var t = $("o-vox").value.trim().toLowerCase();
  if (t === "" || t === "auto") return -1;
  if (t === "off" || t === "0") return 0;
  var v = parseInt(t, 10);
  return isNaN(v) ? -1 : Math.min(999, Math.max(1, v));
}
function options() {
  return {
    max_views: num("o-max", 0, 2000, 24), stride: num("o-stride", 1, 100, 1),
    pixel_stride: num("o-px", 1, 16, 1), conf_pct: num("o-conf", 0, 95, 0), window: num("o-win", 4, 64, 24),
    mask_sky: $("o-sky").checked, align: num("o-align", 0, 10, 3), mv_check: num("o-mv", 0, 4, 1),
    voxel_mm: voxelMm()
  };
}
function num(id, lo, hi, dflt) {
  var v = parseInt($(id).value, 10);
  if (isNaN(v)) v = dflt;
  return Math.min(hi, Math.max(lo, v));
}

$("go").onclick = function () {
  if (!picked.length) return;
  var files = picked.slice();
  var total = 0, done = 0;
  files.forEach(function (f) { total += f.size; });
  var opts = options();
  var name = $("o-name").value.trim() || $("o-name").placeholder || files[0].name;
  uploading = true;
  $("go").disabled = true;
  $("upbar").hidden = false;
  var bar = $("upbar").firstChild;
  var msg = $("upmsg");
  msg.textContent = "creating the job…";
  var id;
  api("POST", "/api/jobs", { name: name }).then(function (j) {
    id = j.id;
    var chain = Promise.resolve();
    files.forEach(function (f, k) {
      chain = chain.then(function () {
        msg.textContent = "uploading " + (k + 1) + "/" + files.length + " — " + f.name;
        return put("/api/jobs/" + id + "/files/" + encodeURIComponent(padTo(k + 1, files.length) + "_" + safe(f.name)), f, function (n) {
          bar.style.width = (100 * (done + n) / Math.max(1, total)).toFixed(1) + "%";
        }).then(function () { done += f.size; });
      });
    });
    return chain;
  }).then(function () {
    msg.textContent = "queueing…";
    return api("POST", "/api/jobs/" + id + "/start", opts);
  }).then(function () {
    msg.textContent = "queued — the job list below follows it";
    bar.style.width = "100%";
    uploading = false;
    picked = [];
    $("file").value = "";
    $("thumbs").textContent = "";
    $("picked").textContent = "";
    $("o-name").value = "";
    setTimeout(function () { $("upbar").hidden = true; bar.style.width = "0"; }, 1500);
    refresh();
  }).catch(function (e) {
    msg.textContent = "failed: " + e.message;
    uploading = false;
    $("go").disabled = picked.length === 0;
    if (id) refresh();
  });
};

function lastLine(log) {
  var lines = (log || "").split(LF);
  for (var i = lines.length - 1; i >= 0; i--) {
    var segs = lines[i].split(CR);
    for (var k = segs.length - 1; k >= 0; k--) if (segs[k].trim()) return segs[k].trim();
  }
  return "";
}
function cleanLog(log) {
  return (log || "").split(LF).map(function (l) {
    var segs = l.split(CR).filter(function (s) { return s.trim(); });
    return segs.length ? segs[segs.length - 1] : "";
  }).filter(function (l) { return l.trim(); }).join(LF);
}

function el(tag, cls, text) {
  var e = document.createElement(tag);
  if (cls) e.className = cls;
  if (text !== undefined) e.textContent = text;
  return e;
}

function showLog(id, box) {
  var pre = box.querySelector("pre.log");
  if (pre) { pre.remove(); delete openLogs[id]; return; }
  openLogs[id] = true;
  pre = el("pre", "log", "…");
  box.appendChild(pre);
  fillLog(id, pre);
}
function fillLog(id, pre) {
  api("GET", "/api/jobs/" + id).then(function (j) {
    pre.textContent = cleanLog(j.log) || "(no output yet)";
    pre.scrollTop = pre.scrollHeight;
  }).catch(function (e) { pre.textContent = e.message; });
}

function render(jobs) {
  var box = $("jobs");
  /* the list is rebuilt on every poll: put the keyboard focus back on the
     same job's same control, when it is still there */
  var fa = document.activeElement;
  var focusKey = fa && fa.getAttribute && box.contains(fa) ? fa.getAttribute("data-key") : null;
  box.textContent = "";
  if (!jobs.length) { box.appendChild(el("div", "empty", "No jobs yet.")); return; }
  var now = Date.now();
  var queued = jobs.filter(function (j) { return j.state === "queued"; })
                   .sort(function (a, b) { return a.id < b.id ? -1 : 1; })
                   .map(function (j) { return j.id; });
  jobs.forEach(function (j) {
    var d = el("div", "job");
    var top = el("div", "jtop");
    top.appendChild(el("span", "jname", j.name || j.id));
    top.appendChild(el("span", "badge st-" + j.state, j.state));
    d.appendChild(top);
    var meta = [when(j.created), j.files + " file" + (j.files === 1 ? "" : "s") + ", " + mb(j.input_bytes)];
    if (j.started && j.finished) meta.push("took " + dur(j.finished - j.started));
    else if (j.started && j.state === "running") meta.push("running " + dur(now - j.started));
    if (j.points) meta.push(j.points.toLocaleString() + " points");
    if (j.cloud_bytes) meta.push("cloud " + mb(j.cloud_bytes));
    d.appendChild(el("div", "jmeta", meta.join(" · ")));
    var prog = "";
    if (j.state === "queued") {
      var pos = queued.indexOf(j.id);
      prog = pos > 0 ? "waiting — " + pos + " ahead" : "next in line";
    } else if (j.state === "running" || j.state === "failed") prog = j.progress || "";
    if (prog) d.appendChild(el("div", "jprog", prog));
    var act = el("div", "jact");
    if (j.cloud_bytes) {
      var v = el("a", "btn", "View in 3-D");
      v.setAttribute("data-key", j.id + ":view");
      /* with the views kept, the viewer can also cut a region into a 3-D object */
      v.href = "/view?cloud=" + encodeURIComponent("/jobs/" + j.id + "/cloud.ply") +
        (j.scene ? "&crop=" + encodeURIComponent("/api/jobs/" + j.id + "/mesh") : "");
      v.target = "_blank";
      act.appendChild(v);
      var dl = el("a", "btn", "Download .ply");
      dl.setAttribute("data-key", j.id + ":dl");
      dl.href = "/jobs/" + j.id + "/cloud.ply";
      dl.setAttribute("download", safe(j.name || j.id) + ".ply");
      act.appendChild(dl);
    }
    if (j.object_bytes) {
      var ov = el("a", "btn", "View 3-D object");
      ov.setAttribute("data-key", j.id + ":obj");
      ov.href = "/view?glb=" + encodeURIComponent("/jobs/" + j.id + "/object.glb");
      ov.target = "_blank";
      act.appendChild(ov);
      var od = el("a", "btn", "Download .glb");
      od.setAttribute("data-key", j.id + ":objdl");
      od.href = "/jobs/" + j.id + "/object.glb";
      od.setAttribute("download", safe(j.name || j.id) + ".glb");
      act.appendChild(od);
    }
    var lb = el("button", "", "Log");
    lb.setAttribute("data-key", j.id + ":log");
    lb.onclick = function () { showLog(j.id, d); };
    act.appendChild(lb);
    if (j.state === "done" || j.state === "failed") {
      var rb = el("button", "", "Run again with the options above");
      rb.setAttribute("data-key", j.id + ":rerun");
      rb.onclick = function () {
        rb.disabled = true;
        api("POST", "/api/jobs/" + j.id + "/start", options()).then(refresh).catch(function (e) { alert(e.message); rb.disabled = false; });
      };
      act.appendChild(rb);
    }
    if (j.state !== "running") {
      var del = el("button", "danger", "Delete");
      del.setAttribute("data-key", j.id + ":del");
      del.onclick = function () {
        if (!confirm("Delete " + (j.name || j.id) + " and its files?")) return;
        api("DELETE", "/api/jobs/" + j.id).then(refresh).catch(function (e) { alert(e.message); });
      };
      act.appendChild(del);
    }
    d.appendChild(act);
    if (j.mesh_state === "queued" || j.mesh_state === "running")
      d.appendChild(el("div", "jprog", "making a 3-D object" + (j.mesh_state === "queued" ? " (queued)" : "…")));
    else if (j.mesh_state === "failed") d.appendChild(el("div", "jprog", "the 3-D object failed — try a box around the object"));
    if (j.state === "done" && !j.scene)
      d.appendChild(el("div", "jmeta", "made before 3-D objects: run it again to cut objects from it"));
    else if (j.state === "done" && j.scene && !j.object_bytes && !j.mesh_state)
      d.appendChild(el("div", "jmeta", "3-D object: open View in 3-D, box the region, make 3-D object"));
    if (j.opts) d.appendChild(el("div", "jmeta", "options: " + j.opts));
    if (openLogs[j.id]) {
      var pre = el("pre", "log", "…");
      d.appendChild(pre);
      fillLog(j.id, pre);
    }
    box.appendChild(d);
  });
  if (focusKey) {
    var back = box.querySelector('[data-key="' + focusKey + '"]');
    if (back) back.focus();
  }
}

var timer = null;
function refresh() {
  clearTimeout(timer);
  api("GET", "/api/jobs").then(function (r) {
    render(r.jobs || []);
    var busy = (r.jobs || []).some(function (j) {
      return j.state === "queued" || j.state === "running" || j.mesh_state === "queued" || j.mesh_state === "running";
    });
    timer = setTimeout(refresh, busy ? 2000 : 15000);
  }).catch(function (e) {
    $("jobs").textContent = "cannot list the jobs: " + e.message;
    timer = setTimeout(refresh, 5000);
  });
}
refresh();
</script>
</body>
</html>
`
}
