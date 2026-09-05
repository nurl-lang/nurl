"use strict";
// auth.js — sign-in for the anomaly dashboard.
//
// The service verifies OIDC bearer tokens (packages/oauth); it has no
// session cookie and no server-side login form. So the browser does the
// authorization-code flow with PKCE itself, keeps the access token, and
// attaches it to every API call.
//
// The pages that use this stay ordinary: `fetch` is wrapped once here, so a
// page's own code calls the API exactly as it did before authentication
// existed. What each page must do is wait for `Auth.ready()` before its
// first request — a call made while the token is still being restored
// would be a 401 the page has no way to interpret.
//
// When the server reports authentication disabled, every function here
// becomes a no-op and the dashboard behaves exactly as it always has.

(function () {
  const LS_KEY = "anomaly.auth.v1";      // tokens; survives a reload
  const SS_FLOW = "anomaly.flow.v1";     // one sign-in's PKCE state
  const SKEW = 60;                       // refresh this many seconds early

  const Auth = {
    cfg: null,        // /api/auth/config
    meta: null,       // the provider's discovery document
    tokens: null,     // { access_token, refresh_token, expires_at, id_token }
    me: null,         // /api/me
    _ready: null,
  };
  window.Auth = Auth;

  // ── small helpers ───────────────────────────────────────────────────

  const b64url = (buf) => btoa(String.fromCharCode(...new Uint8Array(buf)))
    .replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");

  function randomString(nbytes) {
    const a = new Uint8Array(nbytes);
    crypto.getRandomValues(a);
    return b64url(a.buffer);
  }

  async function challengeFor(verifier) {
    const d = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(verifier));
    return b64url(d);
  }

  function load(store, key) {
    try { const v = store.getItem(key); return v ? JSON.parse(v) : null; } catch (e) { return null; }
  }
  function save(store, key, val) {
    try { val === null ? store.removeItem(key) : store.setItem(key, JSON.stringify(val)); } catch (e) {}
  }

  // The wrapped fetch must not attach a token to the provider's own token
  // endpoint, and must not recurse through itself.
  const rawFetch = window.fetch.bind(window);

  // ── configuration and discovery ─────────────────────────────────────

  async function loadConfig() {
    const r = await rawFetch("/api/auth/config");
    if (!r.ok) throw new Error("cannot read /api/auth/config");
    return await r.json();
  }

  async function loadMeta(issuer) {
    const url = issuer.replace(/\/+$/, "") + "/.well-known/openid-configuration";
    const r = await rawFetch(url);
    if (!r.ok) throw new Error("cannot reach the identity provider");
    return await r.json();
  }

  // ── the flow ────────────────────────────────────────────────────────

  Auth.login = async function (returnTo) {
    if (!Auth.cfg || !Auth.cfg.enabled) return;
    if (!Auth.meta) Auth.meta = await loadMeta(Auth.cfg.issuer);
    const verifier = randomString(32);
    const flow = {
      verifier,
      state: randomString(16),
      nonce: randomString(16),
      // Where to land afterwards. Captured now, because the callback page
      // has no idea which page sent the user away.
      returnTo: returnTo || (location.pathname + location.search),
    };
    save(sessionStorage, SS_FLOW, flow);
    const p = new URLSearchParams({
      client_id: Auth.cfg.client_id,
      response_type: "code",
      redirect_uri: location.origin + Auth.cfg.redirect_path,
      // offline_access buys a refresh token, which is the difference
      // between a silent renewal and bouncing the user through the
      // provider every hour.
      scope: Auth.cfg.scope + " offline_access",
      state: flow.state,
      nonce: flow.nonce,
      code_challenge: await challengeFor(verifier),
      code_challenge_method: "S256",
    });
    location.assign(Auth.meta.authorization_endpoint + "?" + p.toString());
  };

  // Runs on the callback page only.
  Auth.completeLogin = async function (search) {
    const q = new URLSearchParams(search || location.search);
    if (q.get("error")) {
      throw new Error(q.get("error_description") || q.get("error"));
    }
    const code = q.get("code");
    const flow = load(sessionStorage, SS_FLOW);
    if (!code || !flow) throw new Error("no sign-in is in progress");
    // The state is what ties this redirect to the request we made; a
    // mismatch is someone else's redirect and must not be exchanged.
    if (q.get("state") !== flow.state) throw new Error("state mismatch — sign-in aborted");

    Auth.cfg = Auth.cfg || await loadConfig();
    Auth.meta = Auth.meta || await loadMeta(Auth.cfg.issuer);
    const body = new URLSearchParams({
      client_id: Auth.cfg.client_id,
      grant_type: "authorization_code",
      code,
      redirect_uri: location.origin + Auth.cfg.redirect_path,
      code_verifier: flow.verifier,
    });
    const r = await rawFetch(Auth.meta.token_endpoint, {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: body.toString(),
    });
    const d = await r.json();
    if (!r.ok) throw new Error(d.error_description || d.error || "token exchange failed");
    storeTokens(d);
    save(sessionStorage, SS_FLOW, null);
    return flow.returnTo || "/";
  };

  function storeTokens(d) {
    Auth.tokens = {
      access_token: d.access_token,
      id_token: d.id_token || "",
      refresh_token: d.refresh_token || (Auth.tokens && Auth.tokens.refresh_token) || "",
      expires_at: Math.floor(Date.now() / 1000) + (parseInt(d.expires_in, 10) || 3600),
    };
    save(localStorage, LS_KEY, Auth.tokens);
  }

  Auth.logout = function () {
    Auth.tokens = null;
    Auth.me = null;
    save(localStorage, LS_KEY, null);
    save(sessionStorage, SS_FLOW, null);
    render();
  };

  async function refresh() {
    if (!Auth.tokens || !Auth.tokens.refresh_token) return false;
    if (!Auth.meta) Auth.meta = await loadMeta(Auth.cfg.issuer);
    const body = new URLSearchParams({
      client_id: Auth.cfg.client_id,
      grant_type: "refresh_token",
      refresh_token: Auth.tokens.refresh_token,
      scope: Auth.cfg.scope + " offline_access",
    });
    const r = await rawFetch(Auth.meta.token_endpoint, {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: body.toString(),
    });
    if (!r.ok) { Auth.tokens = null; save(localStorage, LS_KEY, null); return false; }
    storeTokens(await r.json());
    return true;
  }

  // The token to send, renewed first if it is about to expire. Returns ""
  // when there is none, which is how the caller knows to offer a sign-in.
  Auth.token = async function () {
    if (!Auth.tokens) return "";
    if (Auth.tokens.expires_at - SKEW > Math.floor(Date.now() / 1000)) return Auth.tokens.access_token;
    return (await refresh()) ? Auth.tokens.access_token : "";
  };

  // ── the wrapped fetch ───────────────────────────────────────────────

  window.fetch = async function (input, init) {
    const url = typeof input === "string" ? input : (input && input.url) || "";
    const sameOrigin = url.startsWith("/") || url.startsWith(location.origin);
    if (!Auth.cfg || !Auth.cfg.enabled || !sameOrigin) return rawFetch(input, init);
    const tok = await Auth.token();
    if (!tok) return rawFetch(input, init);
    const opt = Object.assign({}, init || {});
    opt.headers = new Headers((init && init.headers) || (typeof input === "object" && input.headers) || {});
    opt.headers.set("Authorization", "Bearer " + tok);
    const r = await rawFetch(url, opt);
    // A 401 with a token in hand means the token is no longer good; one
    // silent renewal, then the sign-in card. Retrying forever would just
    // hammer the provider.
    if (r.status === 401 && await refresh()) {
      opt.headers.set("Authorization", "Bearer " + Auth.tokens.access_token);
      return rawFetch(url, opt);
    }
    if (r.status === 401) { Auth.logout(); requireSignIn(); }
    return r;
  };

  // ── the header chip and the sign-in card ────────────────────────────

  const CSS = `
  .auth-chip { display:flex; align-items:center; gap:8px; margin-left:16px; font-size:12px; }
  .auth-chip .who { color:var(--fg,#e6edf3); font-weight:500; }
  .auth-chip .role { font-family:var(--mono,monospace); font-size:10px; padding:1px 6px; border-radius:999px;
    border:1px solid var(--border,#2a3242); color:var(--muted,#8b98a9); }
  .auth-chip .role.admin { border-color:var(--accent2,#6ee7b7); color:var(--accent2,#6ee7b7); }
  .auth-chip button { font-size:12px; padding:4px 10px; }
  #auth-card { position:fixed; inset:0; background:var(--bg,#0e1116); z-index:999;
    display:flex; align-items:center; justify-content:center; }
  #auth-card .box { background:var(--panel,#161b22); border:1px solid var(--border,#2a3242);
    border-radius:12px; padding:32px 36px; max-width:420px; text-align:center; }
  #auth-card h2 { margin:0 0 8px; font-size:18px; color:var(--fg,#e6edf3); }
  #auth-card p { color:var(--muted,#8b98a9); font-size:13px; line-height:1.5; margin:0 0 20px; }
  #auth-card button { font-size:14px; padding:9px 18px; background:var(--accent,#4c9aff);
    border:1px solid var(--accent,#4c9aff); color:#06122b; border-radius:8px; cursor:pointer; font-weight:600; }
  #auth-card .err { color:var(--danger,#ff6b6b); font-size:12px; margin-top:14px; }
  `;

  function injectCss() {
    if (document.getElementById("auth-css")) return;
    const st = document.createElement("style");
    st.id = "auth-css";
    st.textContent = CSS;
    document.head.appendChild(st);
  }

  function render() {
    injectCss();
    const nav = document.querySelector("header nav") || document.querySelector("header");
    if (!nav) return;
    let chip = document.getElementById("auth-chip");
    if (!chip) {
      chip = document.createElement("span");
      chip.id = "auth-chip";
      chip.className = "auth-chip";
      nav.appendChild(chip);
    }
    // The Organization page only exists when there is an organization, so
    // its nav link is injected here rather than pasted into every page.
    if (Auth.cfg && Auth.cfg.enabled && Auth.me && !document.getElementById("auth-org-link")
        && location.pathname !== "/admin.html") {
      const a = document.createElement("a");
      a.id = "auth-org-link";
      a.href = "/admin.html";
      a.textContent = "Organization";
      nav.appendChild(a);
    }
    if (!Auth.cfg || !Auth.cfg.enabled) { chip.innerHTML = ""; return; }
    if (!Auth.me) {
      chip.innerHTML = '<button onclick="Auth.login()">Sign in</button>';
      return;
    }
    const label = Auth.me.name || Auth.me.email || Auth.me.subject;
    chip.innerHTML = '<span class="who"></span>' +
      '<span class="role ' + (Auth.me.is_admin ? "admin" : "") + '"></span>' +
      '<button onclick="Auth.logout()">Sign out</button>';
    chip.querySelector(".who").textContent = label;
    chip.querySelector(".role").textContent = Auth.me.role;
  }

  function requireSignIn(message) {
    injectCss();
    if (document.getElementById("auth-card")) return;
    const d = document.createElement("div");
    d.id = "auth-card";
    d.innerHTML = '<div class="box"><h2>Sign in</h2>' +
      "<p>This dashboard shows the models that belong to you. " +
      "Sign in with your work account to continue.</p>" +
      '<button id="auth-go">Sign in</button>' +
      (message ? '<div class="err"></div>' : "") + "</div>";
    document.body.appendChild(d);
    if (message) d.querySelector(".err").textContent = "Rejected: " + message;
    d.querySelector("#auth-go").onclick = () => Auth.login();
  }
  Auth.requireSignIn = requireSignIn;

  // ── boot ────────────────────────────────────────────────────────────
  //
  // Resolves once the page may safely call the API: either authentication
  // is off, or a token is in hand and /api/me has answered. When a sign-in
  // is needed the promise never resolves — the card is up and the page's
  // own boot code should not run behind it.

  async function boot() {
    try { Auth.cfg = await loadConfig(); } catch (e) { Auth.cfg = { enabled: false }; }
    if (!Auth.cfg.enabled) { render(); return; }
    Auth.tokens = load(localStorage, LS_KEY);
    const tok = await Auth.token();
    if (!tok) { render(); requireSignIn(); return new Promise(() => {}); }
    const r = await rawFetch("/api/me", { headers: { Authorization: "Bearer " + tok } });
    if (!r.ok) {
      // A token in hand and a 401 back is a real mismatch — the audience,
      // the issuer, the clock. Say which: the same card with no explanation
      // is what turns a one-line configuration error into a mystery.
      let why = "";
      try { why = (await r.json()).message || ""; } catch (e) {}
      Auth.logout();
      requireSignIn(why);
      return new Promise(() => {});
    }
    Auth.me = await r.json();
    render();
  }

  // May this caller change anything? In simple mode there is nobody to
  // distinguish, so everything is open. Signed in, a viewer reads the
  // organization's data and its visualizations and nothing else: a retrain
  // rewrites forests, a margin edit changes every verdict, and a reset
  // destroys history. None of that is viewing.
  Auth.canWrite = function () {
    if (!Auth.cfg || !Auth.cfg.enabled) return true;
    return !!(Auth.me && Auth.me.role === "admin");
  };

  // Put a one-line explanation at the top of a page whose controls are
  // hidden, so a viewer is told rather than left wondering.
  Auth.viewerNotice = function (what) {
    if (Auth.canWrite()) return;
    injectCss();
    if (document.getElementById("auth-viewer-note")) return;
    const d = document.createElement("div");
    d.id = "auth-viewer-note";
    d.style.cssText = "max-width:1200px;margin:16px auto -4px;padding:10px 14px;border-radius:8px;" +
      "border:1px solid var(--border,#2a3242);background:var(--panel,#161b22);" +
      "color:var(--muted,#8b98a9);font-size:13px";
    d.textContent = "You have view access to this organization. " + what;
    const main = document.querySelector("main");
    if (main) main.parentNode.insertBefore(d, main);
  };

  Auth.ready = function () {
    if (!Auth._ready) Auth._ready = boot();
    return Auth._ready;
  };

  // The callback page must NOT boot: it has no token yet — that is the
  // whole reason it exists — so boot() would put the sign-in card up over
  // an exchange already in flight, and clicking it starts a second sign-in
  // that races the first. Round and round. The page sets this flag before
  // loading us and drives completeLogin() itself.
  if (!window.__AUTH_CALLBACK__) {
    // Pages that forget to await ready() still get a chip, and the wrapped
    // fetch still works — it just may fire its first request unauthenticated.
    if (document.readyState === "loading") {
      document.addEventListener("DOMContentLoaded", () => Auth.ready());
    } else {
      Auth.ready();
    }
  }
})();
