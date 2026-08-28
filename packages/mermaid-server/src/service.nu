// mermaid-server/src/service.nu — the render pipeline and the two faces
// that expose it: an HTTP API and an MCP server, in one process.
//
// The pipeline is the whole program in four calls:
//
//     parse → layout → render → SVG
//
// with the template chosen per request. Everything the HTTP routes and the
// MCP tools do is a wrapper around `mmd_render_source`.
//
// Threading: the server runs a worker POOL, so several requests render at
// once, each on its own OS thread. The only state shared between them is
// the loaded template set, which is built once before the listener opens
// and is read-only from then on — no lock is needed, and none is taken on
// the hot path. It lives behind a global pointer rather than a captured
// closure environment so that every worker sees the same set.

$ `deps/http/src/http.nu`
$ `stdlib/ext/mcp.nu`
$ `stdlib/ext/mcp_http.nu`
$ `stdlib/ext/json.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `graph.nu`
$ `parse.nu`
$ `theme.nu`
$ `layout.nu`
$ `render.nu`

: ~ i g_mmd_ts 0

@ mmd_state_init MmdTemplateSet ts → v {
    : *MmdTemplateSet p # *MmdTemplateSet ( nurl_alloc Z MmdTemplateSet )
    = . p kind . ts kind
    = . p root . ts root
    = . p items . ts items
    = . p default_name . ts default_name
    = g_mmd_ts # i p
}

@ mmd_state → MmdTemplateSet {
    : *MmdTemplateSet p # *MmdTemplateSet g_mmd_ts
    ^ @ MmdTemplateSet { . p kind . p root . p items . p default_name }
}

@ mmd_state_free → v {
    ? == g_mmd_ts 0 { ^ v } {}
    ( mmd_templates_free ( mmd_state ) )
    ( nurl_free # s # *MmdTemplateSet g_mmd_ts )
    = g_mmd_ts 0
}

// ── The pipeline ─────────────────────────────────────────────────────

: MmdRenderRes {
    b ok
    String svg  // the SVG on success, the error message otherwise
    i width
    i height
    i nodes
    i edges
    i line  // parse-error position, 0 when there is none
    i col
    ( Vec String ) warnings
}

@ mmd_render_res_free MmdRenderRes r → v {
    ( string_free . r svg )
    : i n ( vec_len [String] . r warnings )
    : ~ i i 0
    ~ < i n {
        ?? ( vec_get [String] . r warnings i ) {
            T s → ( string_free s )
            F _ → {}
        }
        = i + i 1
    }
    ( vec_free [String] . r warnings )
}

@ __mmds_err s msg i line i col → MmdRenderRes {
    ^ @ MmdRenderRes { F ( string_from msg ) 0 0 0 0 line col ( vec_new [String] ) }
}

// Parse, lay out and render `src` with the named template (empty = the
// default one). The returned struct owns everything in it.
@ mmd_render_source s src s tmpl → MmdRenderRes {
    : MmdTemplateSet ts ( mmd_state )
    : i ti ( mmd_templates_find ts tmpl )
    ? < ti 0 {
        : String m ( string_with_cap 96 )
        ( string_push_str m `unknown template '` )
        ( string_push_str m tmpl )
        ( string_push_str m `' — GET /templates lists the ones that are loaded` )
        : MmdRenderRes bad @ MmdRenderRes { F m 0 0 0 0 0 0 ( vec_new [String] ) }
        ^ bad
    } {}
    : MmdTheme theme ( mmd_templates_theme ts ti )

    : MmdParseResult pr ( mmd_parse src )
    ? ! . pr ok {
        : String m ( string_clone . pr message )
        : i ln . pr line
        : i cl . pr col
        ( mmd_parse_result_free pr )
        ^ @ MmdRenderRes { F m 0 0 0 0 ln cl ( vec_new [String] ) }
    } {}

    : MmdGraph g . pr graph
    : MmdLayout lay ( mmd_layout g theme )
    : String svg ( mmd_render_svg g lay theme )

    : ( Vec String ) warns ( vec_new [String] )
    : i nw ( vec_len [String] . g warnings )
    : ~ i wi 0
    ~ < wi nw {
        ?? ( vec_get [String] . g warnings wi ) {
            T s → ( vec_push [String] warns ( string_clone s ) )
            F _ → {}
        }
        = wi + wi 1
    }

    : i nn ( mmd_node_count g )
    : i ne ( mmd_edge_count g )
    : i w . lay width
    : i h . lay height
    ( mmd_layout_free lay )
    ( mmd_parse_result_free pr )
    ^ @ MmdRenderRes { T svg w h nn ne 0 0 warns }
}

// ── Request helpers ──────────────────────────────────────────────────

// The value of a query parameter, as an owned String (empty when absent).
@ __mmds_query HttpRequest req s name → String {
    : ( Vec QueryPair ) pairs ( parse_query ( string_data . req query ) )
    : ~ String out ( string_new )
    : i n ( vec_len [QueryPair] pairs )
    : ~ i i 0
    ~ < i n {
        ?? ( vec_get [QueryPair] pairs i ) {
            T p → {
                ? != 0 ( nurl_str_eq ( string_data . p key ) name ) {
                    ( string_free out )
                    = out ( string_clone . p value )
                } {}
            }
            F _ → {}
        }
        = i + i 1
    }
    ( query_pairs_free pairs )
    ^ out
}

@ __mmds_body HttpRequest req → String {
    : i n ( vec_len [u] . req body )
    ? == n 0 { ^ ( string_new ) } {}
    ^ ( string_from_bytes ( vec_data [u] . req body ) n )
}

// `?template=`, else the `X-Template` header, else empty (the default).
@ __mmds_template HttpRequest req → String {
    : String q ( __mmds_query req `template` )
    ? > ( string_len q ) 0 { ^ q } {}
    ( string_free q )
    ?? ( header_get . req headers `x-template` ) {
        T h → ^ h
        F _ → {}
    }
    ^ ( string_new )
}

@ __mmds_svg_response MmdRenderRes r → HttpResponse {
    : HttpResponse resp ( response_new 200 )
    ( response_set_body_str resp ( string_data . r svg ) )
    ( response_set_header resp `Content-Type` `image/svg+xml; charset=utf-8` )
    ( response_set_header resp `Cache-Control` `no-store` )
    : i n ( vec_len [String] . r warnings )
    ? > n 0 {
        : String w ( string_with_cap 128 )
        : ~ i i 0
        ~ < i n {
            ?? ( vec_get [String] . r warnings i ) {
                T s → {
                    ? > i 0 { ( string_push_str w `; ` ) } {}
                    ( string_push_str w ( string_data s ) )
                }
                F _ → {}
            }
            = i + i 1
        }
        ( response_set_header resp `X-Mermaid-Warnings` ( string_data w ) )
        ( string_free w )
    } {}
    ^ resp
}

@ __mmds_error_json MmdRenderRes r i status → HttpResponse {
    : Json o ( json_obj_new )
    ( json_obj_set o `error` ( json_str_lit ( string_data . r svg ) ) )
    ? > . r line 0 {
        ( json_obj_set o `line` ( json_int . r line ) )
        ( json_obj_set o `column` ( json_int . r col ) )
    } {}
    : HttpResponse resp ( response_json status o )
    ( json_free o )
    ^ resp
}

// ── HTTP handlers ────────────────────────────────────────────────────

@ __mmds_h_health HttpRequest req Params p → HttpResponse {
    : HttpResponse r ( response_text 200 `ok\n` )
    ( response_set_header r `Content-Type` `text/plain; charset=utf-8` )
    ^ r
}

@ mmd_templates_json → Json {
    : MmdTemplateSet ts ( mmd_state )
    : Json arr ( json_arr_new )
    : i n ( mmd_templates_count ts )
    : ~ i i 0
    ~ < i n {
        ?? ( vec_get [MmdTemplate] . ts items i ) {
            T tp → {
                : MmdTheme th . tp theme
                : Json o ( json_obj_new )
                ( json_obj_set o `name` ( json_str_lit ( string_data . tp name ) ) )
                ( json_obj_set o `description` ( json_str_lit ( string_data . th desc ) ) )
                ( json_obj_set o `path` ( json_str_lit ( string_data . tp path ) ) )
                ( json_obj_set o `default` ( json_bool
                != 0 ( nurl_str_eq ( string_data . tp name ) ( string_data . ts default_name ) ) ) )
                ( json_arr_push arr o )
            }
            F _ → {}
        }
        = i + i 1
    }
    : Json out ( json_obj_new )
    ( json_obj_set out `templates` arr )
    ( json_obj_set out `default` ( json_str_lit ( string_data . ts default_name ) ) )
    ( json_obj_set out `source` ( json_str_lit ( string_data . ts root ) ) )
    ^ out
}

@ __mmds_h_templates HttpRequest req Params p → HttpResponse {
    : Json o ( mmd_templates_json )
    : HttpResponse r ( response_json 200 o )
    ( json_free o )
    ^ r
}

// Shared by GET (source in `?src=`) and POST (source in the body).
@ __mmds_render_common HttpRequest req String src → HttpResponse {
    ? == ( string_len src ) 0 {
        : MmdRenderRes e ( __mmds_err `empty diagram — send the mermaid source in the request body (POST) or in ?src= (GET)` 0 0 )
        : HttpResponse r ( __mmds_error_json e 400 )
        ( mmd_render_res_free e )
        ^ r
    } {}
    : String tmpl ( __mmds_template req )
    : MmdRenderRes res ( mmd_render_source ( string_data src ) ( string_data tmpl ) )
    ( string_free tmpl )
    : ~ HttpResponse out ( response_status_only 204 )
    ? . res ok {
        ( http_response_free out )
        = out ( __mmds_svg_response res )
    } {
        ( http_response_free out )
        = out ( __mmds_error_json res 400 )
    }
    ( mmd_render_res_free res )
    ^ out
}

@ __mmds_h_render_get HttpRequest req Params p → HttpResponse {
    : String src ( __mmds_query req `src` )
    : HttpResponse r ( __mmds_render_common req src )
    ( string_free src )
    ^ r
}

@ __mmds_h_render_post HttpRequest req Params p → HttpResponse {
    : String src ( __mmds_body req )
    : HttpResponse r ( __mmds_render_common req src )
    ( string_free src )
    ^ r
}

@ __mmds_h_render_json HttpRequest req Params p → HttpResponse {
    : ~ String src ( __mmds_body req )
    ? == ( string_len src ) 0 {
        ( string_free src )
        = src ( __mmds_query req `src` )
    } {}
    : String tmpl ( __mmds_template req )
    : MmdRenderRes res ( mmd_render_source ( string_data src ) ( string_data tmpl ) )
    ( string_free src )
    ( string_free tmpl )
    : ~ HttpResponse out ( response_status_only 204 )
    ? . res ok {
        : Json o ( json_obj_new )
        ( json_obj_set o `svg` ( json_str_lit ( string_data . res svg ) ) )
        ( json_obj_set o `width` ( json_int . res width ) )
        ( json_obj_set o `height` ( json_int . res height ) )
        ( json_obj_set o `nodes` ( json_int . res nodes ) )
        ( json_obj_set o `edges` ( json_int . res edges ) )
        : Json warr ( json_arr_new )
        : i nw ( vec_len [String] . res warnings )
        : ~ i wi 0
        ~ < wi nw {
            ?? ( vec_get [String] . res warnings wi ) {
                T s → ( json_arr_push warr ( json_str_lit ( string_data s ) ) )
                F _ → {}
            }
            = wi + wi 1
        }
        ( json_obj_set o `warnings` warr )
        ( http_response_free out )
        = out ( response_json 200 o )
        ( json_free o )
    } {
        ( http_response_free out )
        = out ( __mmds_error_json res 400 )
    }
    ( mmd_render_res_free res )
    ^ out
}

// ── MCP ──────────────────────────────────────────────────────────────

@ __mmds_tool_schema_render → Json {
    : Json schema ( json_obj_new )
    ( json_obj_set schema `type` ( json_str_lit `object` ) )
    : Json props ( json_obj_new )
    : Json p_src ( json_obj_new )
    ( json_obj_set p_src `type` ( json_str_lit `string` ) )
    ( json_obj_set p_src `description` ( json_str_lit `Mermaid flowchart source, starting with 'graph <dir>' or 'flowchart <dir>'.` ) )
    ( json_obj_set props `source` p_src )
    : Json p_tpl ( json_obj_new )
    ( json_obj_set p_tpl `type` ( json_str_lit `string` ) )
    ( json_obj_set p_tpl `description` ( json_str_lit `Template name; omit for the server default. mermaid_templates lists them.` ) )
    ( json_obj_set props `template` p_tpl )
    ( json_obj_set schema `properties` props )
    : Json req ( json_arr_new )
    ( json_arr_push req ( json_str_lit `source` ) )
    ( json_obj_set schema `required` req )
    ^ schema
}

@ __mmds_tool_schema_source_only → Json {
    : Json schema ( json_obj_new )
    ( json_obj_set schema `type` ( json_str_lit `object` ) )
    : Json props ( json_obj_new )
    : Json p_src ( json_obj_new )
    ( json_obj_set p_src `type` ( json_str_lit `string` ) )
    ( json_obj_set p_src `description` ( json_str_lit `Mermaid flowchart source.` ) )
    ( json_obj_set props `source` p_src )
    ( json_obj_set schema `properties` props )
    : Json req ( json_arr_new )
    ( json_arr_push req ( json_str_lit `source` ) )
    ( json_obj_set schema `required` req )
    ^ schema
}

@ __mmds_tool_schema_empty → Json {
    : Json schema ( json_obj_new )
    ( json_obj_set schema `type` ( json_str_lit `object` ) )
    ( json_obj_set schema `properties` ( json_obj_new ) )
    ^ schema
}

@ mmd_tools_list → ( Vec Json ) {
    : ( Vec Json ) tools ( vec_new [Json] )
    ( vec_push [Json] tools ( mcp_tool_descriptor `mermaid_render`
    `Render a mermaid flowchart to an SVG image and return the SVG markup. The look comes from a named template; omit 'template' for the server default.`
    ( __mmds_tool_schema_render ) ) )
    ( vec_push [Json] tools ( mcp_tool_descriptor `mermaid_templates`
    `List the templates this server has loaded — the names accepted by mermaid_render's 'template' argument — with their descriptions.`
    ( __mmds_tool_schema_empty ) ) )
    ( vec_push [Json] tools ( mcp_tool_descriptor `mermaid_validate`
    `Parse a mermaid flowchart WITHOUT rendering it: reports node and edge counts, or the line and column of the first syntax error, plus any statements that were ignored.`
    ( __mmds_tool_schema_source_only ) ) )
    ^ tools
}

@ __mmds_arg_str Json args s key → String {
    ?? ( json_obj_get args key ) {
        T v → {
            ? ( json_is_str v ) { ^ ( string_from ( json_str_data v ) ) } {}
        }
        F _ → {}
    }
    ^ ( string_new )
}

@ __mmds_tool_render Json args → Json {
    : String src ( __mmds_arg_str args `source` )
    ? == ( string_len src ) 0 {
        ( string_free src )
        ^ ( mcp_tool_result_error `missing required argument: source` )
    } {}
    : String tmpl ( __mmds_arg_str args `template` )
    : MmdRenderRes res ( mmd_render_source ( string_data src ) ( string_data tmpl ) )
    ( string_free src )
    ( string_free tmpl )
    : ~ Json out ( json_null )
    ? . res ok {
        : String body ( string_with_cap + 256 ( string_len . res svg ) )
        : i nw ( vec_len [String] . res warnings )
        : ~ i wi 0
        ~ < wi nw {
            ?? ( vec_get [String] . res warnings wi ) {
                T s → {
                    ( string_push_str body `<!-- ` )
                    ( string_push_str body ( string_data s ) )
                    ( string_push_str body ` -->\n` )
                }
                F _ → {}
            }
            = wi + wi 1
        }
        ( string_push_str body ( string_data . res svg ) )
        ( json_free out )
        = out ( mcp_tool_result_text ( string_data body ) )
        ( string_free body )
    } {
        : String m ( string_with_cap 128 )
        ? > . res line 0 {
            ( string_push_str m `line ` )
            ( string_push_int m . res line )
            ( string_push_str m `, column ` )
            ( string_push_int m . res col )
            ( string_push_str m `: ` )
        } {}
        ( string_push_str m ( string_data . res svg ) )
        ( json_free out )
        = out ( mcp_tool_result_error ( string_data m ) )
        ( string_free m )
    }
    ( mmd_render_res_free res )
    ^ out
}

@ __mmds_tool_templates → Json {
    : MmdTemplateSet ts ( mmd_state )
    : String body ( string_with_cap 256 )
    ( string_push_str body `templates loaded from ` )
    ( string_push_str body ( string_data . ts root ) )
    ( string_push_str body `:\n` )
    : i n ( mmd_templates_count ts )
    : ~ i i 0
    ~ < i n {
        ?? ( vec_get [MmdTemplate] . ts items i ) {
            T tp → {
                : MmdTheme th . tp theme
                ( string_push_str body `  ` )
                ( string_push_str body ( string_data . tp name ) )
                ? != 0 ( nurl_str_eq ( string_data . tp name ) ( string_data . ts default_name ) ) {
                    ( string_push_str body ` (default)` )
                } {}
                ? > ( string_len . th desc ) 0 {
                    ( string_push_str body ` — ` )
                    ( string_push_str body ( string_data . th desc ) )
                } {}
                ( string_push_str body `\n` )
            }
            F _ → {}
        }
        = i + i 1
    }
    : Json out ( mcp_tool_result_text ( string_data body ) )
    ( string_free body )
    ^ out
}

@ __mmds_tool_validate Json args → Json {
    : String src ( __mmds_arg_str args `source` )
    ? == ( string_len src ) 0 {
        ( string_free src )
        ^ ( mcp_tool_result_error `missing required argument: source` )
    } {}
    : MmdParseResult pr ( mmd_parse ( string_data src ) )
    ( string_free src )
    : ~ Json out ( json_null )
    ? . pr ok {
        : MmdGraph g . pr graph
        : String m ( string_with_cap 128 )
        ( string_push_str m `ok: ` )
        ( string_push_int m ( mmd_node_count g ) )
        ( string_push_str m ` nodes, ` )
        ( string_push_int m ( mmd_edge_count g ) )
        ( string_push_str m ` edges, direction ` )
        ( string_push_str m ( mmd_dir_name . g dir ) )
        : i nw ( vec_len [String] . g warnings )
        : ~ i wi 0
        ~ < wi nw {
            ?? ( vec_get [String] . g warnings wi ) {
                T s → {
                    ( string_push_str m `\n` )
                    ( string_push_str m ( string_data s ) )
                }
                F _ → {}
            }
            = wi + wi 1
        }
        ( json_free out )
        = out ( mcp_tool_result_text ( string_data m ) )
        ( string_free m )
    } {
        : String m ( string_with_cap 128 )
        ( string_push_str m `line ` )
        ( string_push_int m . pr line )
        ( string_push_str m `, column ` )
        ( string_push_int m . pr col )
        ( string_push_str m `: ` )
        ( string_push_str m ( string_data . pr message ) )
        ( json_free out )
        = out ( mcp_tool_result_error ( string_data m ) )
        ( string_free m )
    }
    ( mmd_parse_result_free pr )
    ^ out
}

@ mmd_dispatch_tool s name Json args → Json {
    ? != 0 ( nurl_str_eq name `mermaid_render` ) { ^ ( __mmds_tool_render args ) } {}
    ? != 0 ( nurl_str_eq name `mermaid_templates` ) { ^ ( __mmds_tool_templates ) } {}
    ? != 0 ( nurl_str_eq name `mermaid_validate` ) { ^ ( __mmds_tool_validate args ) } {}
    : String m ( string_with_cap 64 )
    ( string_push_str m `unknown tool: ` )
    ( string_push_str m name )
    : Json out ( mcp_tool_result_error ( string_data m ) )
    ( string_free m )
    ^ out
}

@ __mmds_mcp_call Json id Json params → Json {
    ?? ( json_obj_get params `name` ) {
        T nv → {
            : s name ( json_str_data nv )
            : Json args ?? ( json_obj_get params `arguments` ) {
                T av → ( json_clone av )
                F → ( json_obj_new )
            }
            : Json result ( mmd_dispatch_tool name args )
            ( json_free args )
            ^ ( mcp_response_result id result )
        }
        F → ^ ( mcp_response_error id mcp_err_invalid_params `tools/call requires a "name" parameter` )
    }
}

// One JSON-RPC request in, the reply (or None for a notification) out. The
// same function backs both the HTTP transport and `--stdio`.
@ mmd_mcp_dispatch Json req → ?Json {
    ?? ( json_obj_get req `method` ) {
        T mv → {
            : s method ( json_str_data mv )
            ?? ( json_obj_get req `id` ) {
                T id → {
                    ? != 0 ( nurl_str_eq method `initialize` ) {
                        ^ @ ?Json { T ( mcp_response_result id ( mcp_initialize_result `mermaid-server` `0.1.0` ) ) }
                    } {}
                    ? != 0 ( nurl_str_eq method `ping` ) {
                        ^ @ ?Json { T ( mcp_response_result id ( json_obj_new ) ) }
                    } {}
                    ? != 0 ( nurl_str_eq method `tools/list` ) {
                        ^ @ ?Json { T ( mcp_response_result id ( mcp_tools_list_result ( mmd_tools_list ) ) ) }
                    } {}
                    ? != 0 ( nurl_str_eq method `tools/call` ) {
                        : Json params ?? ( json_obj_get req `params` ) {
                            T pv → ( json_clone pv )
                            F → ( json_obj_new )
                        }
                        : Json out ( __mmds_mcp_call id params )
                        ( json_free params )
                        ^ @ ?Json { T out }
                    } {}
                    : String m ( string_with_cap 48 )
                    ( string_push_str m `unknown method: ` )
                    ( string_push_str m method )
                    : Json err ( mcp_response_error id mcp_err_method_not_found ( string_data m ) )
                    ( string_free m )
                    ^ @ ?Json { T err }
                }
                F → ^ @ ?Json { F @ Json { JNull } }
            }
        }
        F → ^ @ ?Json { F @ Json { JNull } }
    }
}

// ── The playground ───────────────────────────────────────────────────

@ __mmds_playground → s {
    ^ `<!doctype html>
<html lang="en"><head><meta charset="utf-8" />
<meta name="viewport" content="width=device-width,initial-scale=1" />
<title>mermaid-server</title>
<style>
 :root{color-scheme:light dark}
 body{margin:0;font:14px/1.5 system-ui,-apple-system,Segoe UI,Roboto,sans-serif}
 header{display:flex;gap:.75rem;align-items:center;padding:.6rem 1rem;border-bottom:1px solid #8884}
 h1{font-size:15px;margin:0;font-weight:600}
 main{display:grid;grid-template-columns:minmax(280px,38%) 1fr;height:calc(100vh - 49px)}
 textarea{width:100%;height:100%;box-sizing:border-box;border:0;border-right:1px solid #8884;
          padding:1rem;font:13px/1.5 ui-monospace,SFMono-Regular,Menlo,Consolas,monospace;resize:none}
 #out{overflow:auto;padding:1rem;display:flex;align-items:flex-start;justify-content:center}
 #out svg{max-width:100%;height:auto}
 #err{color:#b91c1c;white-space:pre-wrap;font:13px/1.5 ui-monospace,monospace}
 select,button{font:inherit;padding:.2rem .4rem}
 .warn{color:#92400e;font-size:12px;margin-left:auto}
</style></head><body>
<header>
  <h1>mermaid-server</h1>
  <select id="tpl"></select>
  <span class="warn" id="warn"></span>
</header>
<main>
  <textarea id="src" spellcheck="false">graph TD
  A[Client] --&gt;|POST /render| B{{mermaid-server}}
  B --&gt; C[parse]
  C --&gt; D[layout]
  D --&gt; E([SVG])
  B -.-&gt; F[(templates)]
  F -.-&gt; D</textarea>
  <div id="out"></div>
</main>
<script>
var src = document.getElementById("src"),
    out = document.getElementById("out"),
    tpl = document.getElementById("tpl"),
    warn = document.getElementById("warn"),
    timer = null;

fetch("/templates").then(function (r) { return r.json(); }).then(function (j) {
  j.templates.forEach(function (t) {
    var o = document.createElement("option");
    o.value = t.name;
    o.textContent = t.name + (t.description ? " - " + t.description : "");
    if (t.default) { o.selected = true; }
    tpl.appendChild(o);
  });
  render();
});

function render() {
  fetch("/render.json?template=" + encodeURIComponent(tpl.value), {
    method: "POST",
    headers: { "Content-Type": "text/plain" },
    body: src.value
  }).then(function (r) { return r.json(); }).then(function (j) {
    if (j.error) {
      warn.textContent = "";
      out.innerHTML = "";
      var p = document.createElement("pre");
      p.id = "err";
      p.textContent = (j.line ? "line " + j.line + ", column " + j.column + ": " : "") + j.error;
      out.appendChild(p);
      return;
    }
    warn.textContent = (j.warnings && j.warnings.length) ? j.warnings.join("; ") : "";
    out.innerHTML = j.svg;
  });
}

function schedule() { clearTimeout(timer); timer = setTimeout(render, 250); }
src.addEventListener("input", schedule);
tpl.addEventListener("change", render);
</script></body></html>
`
}

@ __mmds_h_index HttpRequest req Params p → HttpResponse {
    : HttpResponse r ( response_new 200 )
    ( response_set_body_str r ( __mmds_playground ) )
    ( response_set_header r `Content-Type` `text/html; charset=utf-8` )
    ^ r
}

// ── Wiring ───────────────────────────────────────────────────────────

// Build the router for the whole service. Exposed separately from
// `mmd_serve` so the tests can drive it without opening a socket.
@ mmd_build_app i workers b quiet → *HttpApp {
    : *HttpApp a ( http_app_new )
    ( http_app_workers a workers )
    ( http_app_cors a )
    ( http_app_body_max a 4194304 )
    ? quiet { ( http_app_quiet a ) } {}

    ( http_app_get a `/` \ HttpRequest req Params p → HttpResponse { ^ ( __mmds_h_index req p ) } )
    ( http_app_get a `/healthz` \ HttpRequest req Params p → HttpResponse { ^ ( __mmds_h_health req p ) } )
    ( http_app_get a `/templates` \ HttpRequest req Params p → HttpResponse { ^ ( __mmds_h_templates req p ) } )
    ( http_app_get a `/render` \ HttpRequest req Params p → HttpResponse { ^ ( __mmds_h_render_get req p ) } )
    ( http_app_post a `/render` \ HttpRequest req Params p → HttpResponse { ^ ( __mmds_h_render_post req p ) } )
    ( http_app_post a `/render.json` \ HttpRequest req Params p → HttpResponse { ^ ( __mmds_h_render_json req p ) } )

    // MCP shares the process, the port and the template set.
    : ( @ HttpResponse HttpRequest ) mcph ( mcp_http_handler \ Json rq → ?Json { ^ ( mmd_mcp_dispatch rq ) } )
    ( http_app_route a `POST` `/mcp` \ HttpRequest req Params p → HttpResponse { ^ ( mcph req ) } )
    ( http_app_route a `GET` `/mcp` \ HttpRequest req Params p → HttpResponse { ^ ( mcph req ) } )
    ( http_app_route a `DELETE` `/mcp` \ HttpRequest req Params p → HttpResponse { ^ ( mcph req ) } )
    ^ a
}
