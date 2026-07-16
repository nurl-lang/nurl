// registry/pages.nu — server-rendered HTML, via the template package.
//
// Every page is an EMBEDDED template (installed tools are binary-only —
// there is no views/ directory at runtime; the yoloe-demo lesson) rendered
// against a Json context built by the service layer. The README on a
// package page comes from md2html over the tarball's README.md, with its
// relative links rewritten onto the version-pinned /files/ asset route.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/ext/json.nu`
$ `deps/template/src/template.nu`
$ `deps/md2html/src/markdown.nu`
$ `src/store.nu`
$ `src/extract.nu`

// ── Chrome (shared head/foot partials) ────────────────────────────────

@ __reg_tpl_head → s {
    ^ `<!doctype html><meta charset=utf-8><title>{{ title }}</title><meta name=viewport content="width=device-width,initial-scale=1"><style>body{font-family:system-ui,-apple-system,Segoe UI,Roboto,sans-serif;max-width:48rem;margin:3rem auto;padding:0 1rem;line-height:1.6;color:#1a1a1a}a{color:#0b62d6}h1{margin-bottom:.2em}code{background:#f4f4f4;padding:.1em .35em;border-radius:4px;font-size:.92em}pre{background:#f4f4f4;padding:1rem;border-radius:6px;overflow:auto}pre code{background:transparent;padding:0}.readme{border-top:1px solid #e5e5e5;margin-top:2.5rem;padding-top:.5rem}.readme img{max-width:100%}.readme table{border-collapse:collapse;margin:1rem 0}.readme th,.readme td{border:1px solid #ddd;padding:.4rem .7rem;text-align:left}.readme th{background:#f4f4f4}.readme blockquote{border-left:3px solid #ddd;margin:1em 0;padding:.2rem 1rem;color:#555}.readme h1,.readme h2{border-bottom:1px solid #eee;padding-bottom:.2em}.readme hr{border:0;border-top:1px solid #e5e5e5;margin:2rem 0}.site-head{display:flex;align-items:center;gap:.6rem;margin:-1rem 0 1.8rem;padding-bottom:1rem;border-bottom:1px solid #e5e5e5}.site-head .brand{display:flex;align-items:center;gap:.6rem;text-decoration:none;color:#1a1a1a}.site-head .wm{font-size:1.1rem;font-weight:600;letter-spacing:.01em}.site-head .wm b{color:#0b62d6}.site-head .spacer{flex:1}.site-head .home{font-size:.85rem;color:#666;font-weight:400;text-decoration:none}.site-head .home:hover{color:#0b62d6}.muted{color:#666}.yanked{color:#b00}.pub{color:#999}.files{border-collapse:collapse;width:100%}.files td{border-bottom:1px solid #eee;padding:.25rem .5rem}.fsize{text-align:right;color:#666}</style><body><div class="site-head"><a class="brand" href="/"><span class="wm">NURL <b>registry</b></span></a><span class="spacer"></span><a class="home" href="https://nurl-lang.org/" target="_blank" rel="noopener">nurl-lang.org →</a></div>`
}

// ── Page templates ────────────────────────────────────────────────────

@ __reg_tpl_catalog → s {
    ^ `{% include 'head' %}<h1>Packages</h1>
<form method=get><input name=q value="{{ q }}" placeholder="search packages" style="padding:.4rem;width:60%"> <button>Search</button></form>
<p class=muted>{{ items | length }} package(s) · <a href="/login">get a publish token →</a></p>
{% if items %}<ul>{% for p in items %}<li><a href="/packages/{{ p.name }}">{{ p.name }}</a> {% if p.version %}<code>{{ p.version }}</code>{% else %}<em>(all versions yanked)</em>{% end %}</li>{% end %}</ul>{% else %}<p>No packages{% if q %} matching “{{ q }}”{% else %} published{% end %} yet.</p>{% end %}`
}

@ __reg_tpl_detail → s {
    ^ `{% include 'head' %}<p><a href="/">← all packages</a></p><h1>{{ name }}</h1>
{% if owner %}<p class=muted>owner <a href="https://github.com/{{ owner }}">@{{ owner }}</a></p>{% end %}
{% if repository %}<p class=muted>repository <a href="{{ repository }}">{{ repository }}</a></p>{% end %}
<h3>Install</h3><pre>[dependencies]
{{ name }} = "{{ req }}"</pre>
<h3>Versions</h3><ul>{% for v in versions %}<li><code>{{ v.version }}</code>{% if v.yanked %} <span class=yanked>(yanked)</span>{% end %}{% if v.date %} <span class=pub>· {{ v.date }}</span>{% end %} <span class=pub>· <a href="https://github.com/{{ v.login }}">@{{ v.login }}</a></span> <span class=pub>· <a href="/packages/{{ name }}/{{ v.version }}/files">files</a></span></li>{% end %}</ul>
<h3>Dependencies (latest)</h3>{% if deps %}<ul>{% for d in deps %}<li><a href="/packages/{{ d.name }}">{{ d.name }}</a> <code>{{ d.req }}</code></li>{% end %}</ul>{% else %}<p>None.</p>{% end %}
{% if readme %}<div class="readme">{{ readme | raw }}</div>{% end %}`
}

@ __reg_tpl_files → s {
    ^ `{% include 'head' %}<p><a href="/packages/{{ name }}">← {{ name }}</a></p><h1>{{ name }} <code>{{ version }}</code></h1>
<p class=muted>{{ files | length }} file(s) · {{ total }} unpacked</p>
<table class=files>{% for f in files %}<tr><td><code>{{ f.path }}</code></td><td class=fsize>{{ f.size }}</td></tr>{% end %}</table>`
}

@ __reg_tpl_notfound → s {
    ^ `{% include 'head' %}<p><a href="/">← all packages</a></p><h1>{{ name }}</h1><p>Not found.</p>`
}

@ __reg_tpl_token → s {
    ^ `{% include 'head' %}<h1>Signed in as {{ login }}</h1>
<p>Your publish token (shown once — store it now):</p>
<pre style="user-select:all">{{ token }}</pre>
<p>Use it with nurlpkg:</p>
<pre>export NURL_TOKEN={{ token }}
nurlpkg publish</pre>`
}

@ __reg_tpl_login_help → s {
    ^ `{% include 'head' %}<h1>Publish tokens</h1>
<p>This registry has no GitHub OAuth configured. Mint a token on the host instead:</p>
<pre>registry token new &lt;login&gt; --data {{ data }}</pre>
<p>The token is printed once; only its peppered hash is stored.</p>`
}

// Render one embedded template with the shared chrome partial in scope.
@ __reg_render s tsrc Json ctx → String {
    : *TplSet ts ( tset_new )
    ( tset_add ts `head` ( __reg_tpl_head ) )
    : ~ String out ( string_new )
    ?? ( tpl_render_with ts tsrc ctx ) {
        T html → {
            ( string_free out )
            = out html
        }
        F err → {
            // A malformed embedded template is a bug, not runtime input —
            // surface it loudly in the body so it can't ship unnoticed.
            ( string_push_str out `<h1>template error</h1><pre>` )
            ( string_push_str out ( string_data err ) )
            ( string_push_str out `</pre>` )
            ( string_free err )
        }
    }
    ( tset_free ts )
    ^ out
}

// ── Public page renderers (ctx built by the service layer) ────────────

// ctx: { "q": str, "items": [ { name, version|null } ], "title": str }
@ reg_page_catalog Json ctx → String {
    ^ ( __reg_render ( __reg_tpl_catalog ) ctx )
}

// ctx: { name, owner|null, repository?, req, versions:[{version,yanked,login}],
//        deps:[{name,req}], readme (pre-rendered HTML, ""=none), title }
@ reg_page_detail Json ctx → String {
    ^ ( __reg_render ( __reg_tpl_detail ) ctx )
}

// ctx: { name, version, files:[{path,size}] (size pre-formatted), total, title }
@ reg_page_files Json ctx → String {
    ^ ( __reg_render ( __reg_tpl_files ) ctx )
}

@ reg_page_notfound Json ctx → String {
    ^ ( __reg_render ( __reg_tpl_notfound ) ctx )
}

// ctx: { login, token, title }
@ reg_page_token Json ctx → String {
    ^ ( __reg_render ( __reg_tpl_token ) ctx )
}

// ctx: { data, title }
@ reg_page_login_help Json ctx → String {
    ^ ( __reg_render ( __reg_tpl_login_help ) ctx )
}

// ── README rendering ──────────────────────────────────────────────────

// True when `url` must be left untouched by relative-link rewriting:
// absolute path, fragment, or a scheme prefix ([a-z][a-z0-9+.-]*:).
@ __reg_url_is_absolute s url → b {
    : i n ( nurl_str_len url )
    ? == n 0 { ^ T } {}
    : i c0 ( nurl_str_get url 0 )
    ? | == c0 47 == c0 35 { ^ T } {}  // '/' or '#'
    : ~ b alpha F
    ? | & >= c0 97 <= c0 122 & >= c0 65 <= c0 90 { = alpha T } {}
    ? ! alpha { ^ F } {}
    : ~ i k 1
    ~ < k n {
        : i c ( nurl_str_get url k )
        ? == c 58 { ^ T } {}  // ':' before any non-scheme char → scheme
        : ~ b schemech F
        ? | & >= c 97 <= c 122 & >= c 65 <= c 90 { = schemech T } {}
        ? & >= c 48 <= c 57 { = schemech T } {}
        ? | | == c 43 == c 46 == c 45 { = schemech T } {}  // + . -
        ? ! schemech { ^ F } {}
        = k + k 1
    }
    ^ F
}

// "../<pkg>" or "../<pkg>/" (a monorepo sibling-package reference, common
// in these READMEs) → the package name; "" otherwise.
@ __reg_sibling_pkg s url → String {
    : String out ( string_new )
    : i n ( nurl_str_len url )
    ? < n 4 { ^ out } {}
    ? ! & & == ( nurl_str_get url 0 ) 46 == ( nurl_str_get url 1 ) 46 == ( nurl_str_get url 2 ) 47 { ^ out } {}
    : ~ i e n
    ? == ( nurl_str_get url - n 1 ) 47 { = e - n 1 } {}
    : ~ i k 3
    ~ < k e {
        ( string_push_char out ( nurl_str_get url k ) )
        = k + k 1
    }
    ? ! ( reg_name_valid ( string_data out ) ) {
        ( string_free out )
        ^ ( string_new )
    } {}
    ^ out
}

// Resolve one README-relative URL against the /files/ asset route (or a
// sibling package page). Returns the replacement, or "" to keep as-is.
@ __reg_resolve_url s url s name s version → String {
    ? ( __reg_url_is_absolute url ) { ^ ( string_new ) } {}
    : String sib ( __reg_sibling_pkg url )
    ? > ( string_len sib ) 0 {
        : String out ( string_from `/packages/` )
        ( string_push_str out ( string_data sib ) )
        ( string_free sib )
        ^ out
    } {}
    ( string_free sib )
    : String norm ( reg_relpath_norm url )
    ? == ( string_len norm ) 0 {
        ( string_free norm )
        ^ ( string_new )
    } {}
    : String out ( string_from `/files/` )
    ( string_push_str out name )
    ( string_push_char out 47 )
    ( string_push_str out version )
    ( string_push_char out 47 )
    ( string_push_str out ( string_data norm ) )
    ( string_free norm )
    ^ out
}

// Rewrite the relative href="…"/src="…" targets in rendered README HTML
// onto /files/<name>/<version>/… (version-pinned, immutable-cacheable).
// md2html emits double-quoted attributes; anything else passes through.
@ reg_readme_rewrite_links s html s name s version → String {
    : String out ( string_with_cap + ( nurl_str_len html ) 64 )
    : i n ( nurl_str_len html )
    : ~ i k 0
    ~ < k n {
        : i c ( nurl_str_get html k )
        // match href=" or src=" (only ever emitted inside tags)
        : ~ i alen 0
        ? & <= + k 6 n == c 104 {  // h
            ? & & & & == ( nurl_str_get html + k 1 ) 114 == ( nurl_str_get html + k 2 ) 101 == ( nurl_str_get html + k 3 ) 102 == ( nurl_str_get html + k 4 ) 61 == ( nurl_str_get html + k 5 ) 34 {
                = alen 6
            } {}
        } {}
        ? & <= + k 5 n == c 115 {  // s
            ? & & & == ( nurl_str_get html + k 1 ) 114 == ( nurl_str_get html + k 2 ) 99 == ( nurl_str_get html + k 3 ) 61 == ( nurl_str_get html + k 4 ) 34 {
                = alen 5
            } {}
        } {}
        ? > alen 0 {
            // copy the attr prefix, collect the value to the closing quote
            : ~ i j 0
            ~ < j alen {
                ( string_push_char out ( nurl_str_get html + k j ) )
                = j + j 1
            }
            : ~ i e + k alen
            : String val ( string_new )
            ~ & < e n != ( nurl_str_get html e ) 34 {
                ( string_push_char val ( nurl_str_get html e ) )
                = e + e 1
            }
            : String repl ( __reg_resolve_url ( string_data val ) name version )
            ? > ( string_len repl ) 0 {
                ( string_push_str out ( string_data repl ) )
            } {
                ( string_push_str out ( string_data val ) )
            }
            ( string_free repl )
            ( string_free val )
            = k e
        } {
            ( string_push_char out c )
            = k + k 1
        }
    }
    ^ out
}

// Markdown README → link-rewritten HTML fragment; "" stays "".
@ reg_readme_html s md s name s version → String {
    ? == ( nurl_str_len md ) 0 { ^ ( string_new ) } {}
    : String html ( md_to_html md )
    : String out ( reg_readme_rewrite_links ( string_data html ) name version )
    ( string_free html )
    ^ out
}
