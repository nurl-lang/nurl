// packages/nurllama/src/webui.nu — the embedded web chat UI.
//
// A single self-contained page (no external requests — CSP-friendly)
// served at `/` to browsers. It talks to the /web/* JSON endpoints,
// carries the per-client GUID in the `nl_client` cookie the server
// sets, and (when the server was started with token auth) prompts for
// the token once and sends it as a Bearer header on every request.
//
// The markup avoids backtick and backslash characters so it embeds
// cleanly in a NURL backtick string.

@ webui_html → s {
    ^ `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>nurllama</title>
<style>
  :root { color-scheme: light dark; }
  * { box-sizing: border-box; }
  body { margin: 0; font: 15px/1.5 system-ui, -apple-system, Segoe UI, Roboto, sans-serif;
         display: flex; height: 100vh; background: #0e1116; color: #e6e6e6; }
  #side { width: 260px; flex: none; border-right: 1px solid #232833; display: flex;
          flex-direction: column; background: #12161d; }
  #side h1 { font-size: 15px; margin: 0; padding: 14px 16px; letter-spacing: .3px;
             border-bottom: 1px solid #232833; }
  #side h1 small { color: #7a8798; font-weight: normal; }
  #newbtn { margin: 12px; padding: 9px; border: 1px solid #2b3543; border-radius: 8px;
            background: #182030; color: #e6e6e6; cursor: pointer; }
  #newbtn:hover { background: #1e2838; }
  #convs { overflow-y: auto; flex: 1; }
  .conv { padding: 10px 16px; cursor: pointer; border-bottom: 1px solid #1a1f27;
          white-space: nowrap; overflow: hidden; text-overflow: ellipsis; color: #c3ccd8; }
  .conv:hover { background: #171d26; }
  .conv.active { background: #1e2836; color: #fff; }
  #main { flex: 1; display: flex; flex-direction: column; min-width: 0; }
  #log { flex: 1; overflow-y: auto; padding: 24px; }
  .msg { max-width: 760px; margin: 0 auto 18px; display: flex; gap: 12px; }
  .msg .who { flex: none; width: 30px; height: 30px; border-radius: 6px; font-size: 12px;
              display: flex; align-items: center; justify-content: center; font-weight: 600; }
  .msg.user .who { background: #2b4a6f; }
  .msg.assistant .who { background: #2f5d43; }
  .msg .body { white-space: pre-wrap; word-wrap: break-word; padding-top: 4px; }
  #composer { border-top: 1px solid #232833; padding: 14px; display: flex; gap: 10px;
              max-width: 784px; margin: 0 auto; width: 100%; }
  #inp { flex: 1; resize: none; padding: 10px 12px; border-radius: 8px; font: inherit;
         border: 1px solid #2b3543; background: #12161d; color: #e6e6e6; }
  #send { padding: 0 18px; border: none; border-radius: 8px; background: #2f6feb;
          color: #fff; font: inherit; cursor: pointer; }
  #send:disabled { opacity: .5; cursor: default; }
  #empty { color: #7a8798; text-align: center; margin-top: 20vh; }
</style>
</head>
<body>
  <div id="side">
    <h1>nurllama <small id="model"></small></h1>
    <button id="newbtn" onclick="newChat()">+ New chat</button>
    <div id="convs"></div>
  </div>
  <div id="main">
    <div id="log"><div id="empty">Start a conversation.</div></div>
    <div id="composer">
      <textarea id="inp" rows="1" placeholder="Message the model..." onkeydown="onKey(event)"></textarea>
      <button id="send" onclick="sendMsg()">Send</button>
    </div>
  </div>
<script>
  var cur = null;
  var busy = false;

  function tok() { return localStorage.getItem("nl_token") || ""; }
  function hdr() {
    var h = { "Content-Type": "application/json" };
    if (tok()) h["Authorization"] = "Bearer " + tok();
    return h;
  }
  async function api(method, url, body) {
    var opt = { method: method, headers: hdr() };
    if (body) opt.body = JSON.stringify(body);
    var r = await fetch(url, opt);
    if (r.status === 401) {
      var t = prompt("This server requires a token:");
      if (t) { localStorage.setItem("nl_token", t.trim()); return api(method, url, body); }
      throw new Error("unauthorized");
    }
    if (!r.ok) throw new Error("http " + r.status);
    return r.json();
  }

  function el(tag, cls, txt) {
    var e = document.createElement(tag);
    if (cls) e.className = cls;
    if (txt !== undefined) e.textContent = txt;
    return e;
  }
  function addMsg(role, content) {
    var empty = document.getElementById("empty");
    if (empty) empty.remove();
    var m = el("div", "msg " + role);
    m.appendChild(el("div", "who", role === "user" ? "You" : "AI"));
    m.appendChild(el("div", "body", content));
    var log = document.getElementById("log");
    log.appendChild(m);
    log.scrollTop = log.scrollHeight;
    return m;
  }

  async function loadConvs() {
    var list = await api("GET", "/web/conversations");
    var box = document.getElementById("convs");
    box.innerHTML = "";
    list.forEach(function (c) {
      var d = el("div", "conv" + (c.id === cur ? " active" : ""), c.title || "New chat");
      d.onclick = function () { openConv(c.id); };
      box.appendChild(d);
    });
  }
  async function openConv(id) {
    cur = id;
    var msgs = await api("GET", "/web/conversations/" + id + "/messages");
    var log = document.getElementById("log");
    log.innerHTML = "";
    msgs.forEach(function (m) { addMsg(m.role, m.content); });
    if (!msgs.length) log.appendChild(el("div", "", ""));
    loadConvs();
  }
  function newChat() {
    cur = null;
    document.getElementById("log").innerHTML = "";
    addMsg("assistant", "New chat. Say hello.");
    loadConvs();
  }

  function onKey(e) {
    if (e.key === "Enter" && !e.shiftKey) { e.preventDefault(); sendMsg(); }
  }
  async function sendMsg() {
    if (busy) return;
    var inp = document.getElementById("inp");
    var text = inp.value.trim();
    if (!text) return;
    inp.value = "";
    busy = true;
    document.getElementById("send").disabled = true;
    addMsg("user", text);
    var pending = addMsg("assistant", "...");
    try {
      var res = await api("POST", "/web/chat", { conversation_id: cur, content: text });
      cur = res.conversation_id;
      pending.querySelector(".body").textContent = res.reply;
      loadConvs();
    } catch (err) {
      pending.querySelector(".body").textContent = "[error: " + err.message + "]";
    }
    busy = false;
    document.getElementById("send").disabled = false;
    inp.focus();
  }

  async function init() {
    try {
      var s = await api("GET", "/web/session");
      document.getElementById("model").textContent = s.model ? ("· " + shortModel(s.model)) : "";
      await loadConvs();
    } catch (e) {
      document.getElementById("log").innerHTML = "";
      addMsg("assistant", "Could not reach the server: " + e.message);
    }
  }
  function shortModel(m) {
    var parts = m.split("/");
    return parts[parts.length - 1];
  }
  init();
</script>
</body>
</html>`
}
