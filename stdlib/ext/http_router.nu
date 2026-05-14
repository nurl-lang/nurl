// stdlib/ext/http_router.nu — Phase 6 of HTTP_SERVER_PLAN.md.
// Method + path routing with named captures and tail wildcards.
// Sits on top of `stdlib/ext/http_request.nu` (HttpRequest + QueryPair)
// and `stdlib/ext/http_response.nu` (HttpResponse). Pure NURL — no
// runtime/compiler additions.
//
// Pattern syntax (Express/Sinatra-style):
//
//   "/users"            literal exact match (segment count must equal)
//   "/users/:id"        named capture; matches one path segment (no '/')
//   "/static/*path"     tail wildcard; captures the rest of the path
//                       INCLUDING any embedded slashes. Must be the
//                       last pattern segment.
//   "/"                 matches "/" only
//
// Method matching is upper-case literal ("GET", "POST", ...) or "*"
// for any. Trailing slashes are STRICT — "/foo" does not match "/foo/".
// Routes are scanned in registration order; the first match wins.
//
// API (this revision):
//
//   ( router_new )                                       → Router
//   ( router_free Router r )                             → v
//
//   ( router_get    Router r s pattern handler )         → v
//   ( router_post   Router r s pattern handler )         → v
//   ( router_put    Router r s pattern handler )         → v
//   ( router_patch  Router r s pattern handler )         → v
//   ( router_delete Router r s pattern handler )         → v
//   ( router_any    Router r s method s pattern handler ) → v
//                                                          ("*" = any method)
//
//   ( router_handle Router r HttpRequest req )           → HttpResponse
//   ( router_count  Router r )                           → i
//
//   ( params_new )                                       → Params
//   ( params_free Params p )                             → v
//   ( params_get  Params p s key )                       → ? String
//   ( params_count Params p )                            → i
//
//   ( with_log_requests  ( @ HttpResponse HttpRequest ) inner )
//                                                        → ( @ HttpResponse HttpRequest )
//   ( with_cors_default  ( @ HttpResponse HttpRequest ) inner )
//                                                        → ( @ HttpResponse HttpRequest )
//
// Memory model:
//
//   * `router_*` registrators COPY both `method` and `pattern` raw `s`
//     into freshly-owned Strings inside the Route. The closure handle
//     is captured by value (fn-ptr + env-ptr — bitwise copy). Caller
//     keeps ownership of the raw `s` literals.
//   * `router_handle` BORROWS the request and returns an OWNED
//     HttpResponse. The handler closure receives BORROWED HttpRequest
//     and BORROWED Params (the router frees Params after the handler
//     returns).
//   * `params_get` returns an OWNED String in the Some arm; caller frees.
//     The None arm carries a freshly-empty String — also free it (mirrors
//     `header_get`).
//   * `with_*` combinators capture the inner closure by value and return
//     a fresh closure handle. The caller owns the resulting closure
//     identically to a hand-written one — no extra cleanup.
//
// Notes on language gaps inherited from earlier phases (see
// HTTP_SERVER_PLAN.md "Cross-cutting prerequisites"):
//
//   * Multi-field structs can't ride `! T E` Ok arms. `router_handle`
//     can't fail (it always either dispatches or 404s) so it returns
//     HttpResponse directly.
//   * `vec_get [Route]` would miscompile for a multi-field Route
//     (String, String, closure). Iteration uses `vec_data + *Route`
//     direct-pointer access, mirroring the convention from
//     `http_request.nu`'s `header_get`.
//   * Route-level middleware (per-route filter chain) would need a
//     `Vec[Middleware]` of closure-handle-shaped structs, which the
//     current generic instantiator handles awkwardly. The handler-level
//     `with_*` combinators are the v1 substitute — caller composes
//     middleware around the handler closure they pass to the server.

$ `stdlib/std/net.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/option.nu`
$ `stdlib/ext/http.nu`
$ `stdlib/ext/http_request.nu`
$ `stdlib/ext/http_response.nu`

// ── Params (path captures) ────────────────────────────────────────────
//
// Backed by a `Vec[QueryPair]` (re-using the struct from
// http_request.nu) — same key/value shape, same case-sensitive lookup
// semantics. Path captures are typically short lists (< 5 entries on
// any reasonable URL pattern), so a linear scan in `params_get` is
// fine.

: Params {
    ( Vec QueryPair ) entries
}

@ params_new → Params {
    ^ @ Params { ( vec_new [QueryPair] ) }
}

@ params_free Params p → v {
    ( query_pairs_free . p entries )
}

@ params_count Params p → i {
    ^ ( vec_len [QueryPair] . p entries )
}

// Case-SENSITIVE lookup. Path-capture names come from the route author,
// not the client, so canonical casing is up to them — case-sensitivity
// matches NURL's everyday `vec_*` / `map_*` semantics.
@ params_get Params p s key → ?String {
    : i n ( vec_len [QueryPair] . p entries )
    : *QueryPair data ( vec_data [QueryPair] . p entries )
    : ~ i k 0
    ~ < k n {
        : QueryPair entry . data k
        ? != 0 ( nurl_str_eq ( string_data . entry key ) key ) {
            : String copy ( string_from ( string_data . entry value ) )
            ^ @ ?String { T copy }
        } {}
        = k + k 1
    }
    ^ @ ?String { F ( string_new ) }
}

// ── Route ─────────────────────────────────────────────────────────────
//
// Storage strategy: routes are heap-allocated `RouteImpl` blocks wrapped
// in single-pointer `Route { s ctl }` handles. The handle layout (one
// `i8*` field, 8 bytes) means `Vec[Route]` is a vec of 8-byte slots —
// no multi-field-struct stride hazard. We hit this when `Vec[Route]`
// is read from pthread worker threads under clang -O2 on Linux: even-
// indexed slots had their first multi-field-struct member overwritten
// with what looked like thread-stack regions (8 MiB+page apart). The
// boxed-handle pattern sidesteps the entire class of issues for
// multi-field collection elements, matching how `Regex`, `Channel`,
// and `McpClient` already work.

: RouteImpl {
    String method
    String pattern
    ( @ HttpResponse HttpRequest Params ) handler
}

: Route { s ctl }

@ __route_free Route route → v {
    : *RouteImpl impl # *RouteImpl . route ctl
    ( string_free . impl method )
    ( string_free . impl pattern )
    ( nurl_free # s impl )
}

// ── Router ────────────────────────────────────────────────────────────

: Router {
    ( Vec Route ) routes
}

@ router_new → Router {
    ^ @ Router { ( vec_new [Route] ) }
}

@ router_free Router r → v {
    ( vec_free_with [Route] . r routes \ Route route → v { ( __route_free route ) } )
}

@ router_count Router r → i {
    ^ ( vec_len [Route] . r routes )
}

// Register a (method, pattern, handler) tuple. Both `method` and
// `pattern` are copied into freshly-owned Strings; the closure handle
// (16 bytes) is captured by value. All three live inside a heap-
// allocated `RouteImpl`; the `Route` handle stored in the vec is a
// single pointer.
@ router_any Router r s method s pattern ( @ HttpResponse HttpRequest Params ) handler → v {
    : *RouteImpl impl # *RouteImpl ( nurl_alloc Z RouteImpl )
    = . impl method ( string_from method )
    = . impl pattern ( string_from pattern )
    = . impl handler handler
    : Route route @ Route { # s impl }
    ( vec_push [Route] . r routes route )
}

@ router_get Router r s pattern ( @ HttpResponse HttpRequest Params ) handler → v {
    ( router_any r `GET` pattern handler )
}

@ router_post Router r s pattern ( @ HttpResponse HttpRequest Params ) handler → v {
    ( router_any r `POST` pattern handler )
}

@ router_put Router r s pattern ( @ HttpResponse HttpRequest Params ) handler → v {
    ( router_any r `PUT` pattern handler )
}

@ router_patch Router r s pattern ( @ HttpResponse HttpRequest Params ) handler → v {
    ( router_any r `PATCH` pattern handler )
}

@ router_delete Router r s pattern ( @ HttpResponse HttpRequest Params ) handler → v {
    ( router_any r `DELETE` pattern handler )
}

// ── Pattern matcher ───────────────────────────────────────────────────
//
// Walks `pattern` and `path` in parallel, segment by segment. A segment
// is delimited by '/' (byte 47) or end-of-string. Three pattern-segment
// kinds:
//
//   ":name"   named capture — pushes ( name, path_segment ) onto params
//   "*name"   tail wildcard — pushes ( name, rest_of_path ) and ends
//   literal   byte-exact compare against the path segment
//
// Returns T on full match (and `params` is populated), F otherwise. On
// a F return, `params` may have been partially populated; the caller
// must free + reallocate it before trying the next route.
@ __match_pattern s pattern s path Params params → b {
    : i pn ( nurl_str_len pattern )
    : i sn ( nurl_str_len path )
    : ~ i pi 0
    : ~ i si 0
    : ~ b ok T
    : ~ b done F

    ~ & ok ! done {
        ? >= pi pn {
            = done T
        } {
            // Pattern-segment bounds: pi → p_end (not inclusive of '/').
            : ~ i p_end pi
            ~ & < p_end pn != ( nurl_str_get pattern p_end ) 47 {
                = p_end + p_end 1
            }
            // First byte of pattern segment classifies its kind.
            : i first ? < pi p_end ( nurl_str_get pattern pi ) 0

            ? == first 42 {
                // Wildcard tail: pattern[pi+1..p_end] is the capture name,
                // path[si..sn] is the value. Wildcard MUST be the final
                // pattern segment — anything after it would be unreachable.
                : String name ( __subraw_to_string pattern + pi 1 p_end )
                : String value ( __subraw_to_string path si sn )
                : QueryPair qp @ QueryPair { name value }
                ( vec_push [QueryPair] . params entries qp )
                = pi pn
                = si sn
                = done T
            } {
                // Path-segment bounds: si → s_end.
                : ~ i s_end si
                ~ & < s_end sn != ( nurl_str_get path s_end ) 47 {
                    = s_end + s_end 1
                }

                ? == first 58 {
                    // Named capture. The path segment must be non-empty (we
                    // refuse to match :id against a "//" gap).
                    ? <= s_end si {
                        = ok F
                    } {
                        : String name ( __subraw_to_string pattern + pi 1 p_end )
                        : String value ( __subraw_to_string path si s_end )
                        : QueryPair qp @ QueryPair { name value }
                        ( vec_push [QueryPair] . params entries qp )
                        = pi p_end
                        = si s_end
                    }
                } {
                    // Literal. Lengths must match, then bytewise compare.
                    : i p_len - p_end pi
                    : i s_len - s_end si
                    ? != p_len s_len {
                        = ok F
                    } {
                        : ~ i k 0
                        ~ & ok < k p_len {
                            ? != ( nurl_str_get pattern + pi k ) ( nurl_str_get path + si k ) {
                                = ok F
                            } {}
                            = k + k 1
                        }
                        ? ok {
                            = pi p_end
                            = si s_end
                        } {}
                    }
                }

                // After consuming a segment, advance over the joining '/' if
                // present in BOTH strings, or fail if one has '/' and the
                // other doesn't (mismatched segment counts).
                ? ok {
                    : b p_has_slash & < pi pn == ( nurl_str_get pattern pi ) 47
                    : b s_has_slash & < si sn == ( nurl_str_get path si ) 47
                    ? p_has_slash {
                        ? s_has_slash {
                            = pi + pi 1
                            = si + si 1
                        } {
                            = ok F
                        }
                    } {
                        ? s_has_slash {
                            = ok F
                        } {}
                    }
                } {}
            }
        }
    }

    // Pattern fully consumed but path has trailing bytes → strict-trailing
    // mismatch.
    ? & ok < si sn { = ok F } {}

    ^ ok
}

// Internal helper: copy bytes `raw[from..to)` into a fresh owned String.
// Used by the pattern matcher to extract capture names + values. Empty
// or inverted ranges yield an empty String.
@ __subraw_to_string s raw i from i to → String {
    : i len - to from
    ? <= len 0 { ^ ( string_new ) } {}
    : String out ( string_with_cap len )
    : ~ i k from
    ~ < k to {
        ( string_push_char out ( nurl_str_get raw k ) )
        = k + k 1
    }
    ^ out
}

// ── Dispatch ──────────────────────────────────────────────────────────
//
// Linear scan over the registered routes. Method match comes first
// (cheap nurl_str_eq), then pattern match (allocates per-attempt
// Params; freed on miss before continuing). The first match wins;
// the matched handler runs, the response propagates out, Params is
// freed.
//
// Falls back to a stock 404 response if no route matched. For a
// custom 404 (or 405-Method-Not-Allowed differentiation), wrap
// `router_handle` in a server-level handler closure that inspects
// `! response_text 404` and substitutes its own.

@ router_handle Router r HttpRequest req → HttpResponse {
    : i n ( vec_len [Route] . r routes )
    : *Route data ( vec_data [Route] . r routes )
    : s req_method ( string_data . req method )
    : s req_path ( string_data . req path )
    : ~ i k 0

    ~ < k n {
        : Route route . data k
        : *RouteImpl impl # *RouteImpl . route ctl
        : s rmethod ( string_data . impl method )
        : b method_ok | != 0 ( nurl_str_eq rmethod `*` ) != 0 ( nurl_str_eq rmethod req_method )
        ? method_ok {
            : Params params ( params_new )
            : s pattern ( string_data . impl pattern )
            ? ( __match_pattern pattern req_path params ) {
                : ( @ HttpResponse HttpRequest Params ) f . impl handler
                : HttpResponse resp ( f req params )
                ( params_free params )
                ^ resp
            } {
                ( params_free params )
            }
        } {}
        = k + k 1
    }

    ^ ( response_text 404 `not found\n` )
}

// ── Middleware combinators ────────────────────────────────────────────
//
// Each `with_*` takes the inner handler closure and returns a NEW
// closure that wraps it. They compose left-to-right: the OUTERMOST
// `with_*` runs first.
//
// Example composition (logging outside CORS outside dispatch):
//
//   : ( @ HttpResponse HttpRequest ) base
//     \ HttpRequest req → HttpResponse { ^ ( router_handle myrouter req ) }
//   : ( @ HttpResponse HttpRequest ) wrapped
//     ( with_log_requests ( with_cors_default base ) )
//   : HttpServer srv ( server_new listener wrapped )
//
// MEMORY: the returned closure captures `inner` BY VALUE — the
// caller's copy is still valid, but calling `inner` directly while
// the wrapper is also live is fine (closures don't have exclusive
// ownership of their captures).

// Logging middleware. Writes "[req] METHOD path" to stderr before
// delegating, and "[req] METHOD path → STATUS" after. Inert-by-design:
// no allocation, no log-level gate (callers can swap in a custom
// logger by wrapping `with_log_requests` themselves).
@ with_log_requests
( @ HttpResponse HttpRequest ) inner
→ ( @ HttpResponse HttpRequest ) {
    ^ \ HttpRequest req → HttpResponse {
        ( nurl_eprint `[req] ` )
        ( nurl_eprint ( string_data . req method ) )
        ( nurl_eprint ` ` )
        ( nurl_eprint ( string_data . req path ) )
        ( nurl_eprint `\n` )
        : HttpResponse resp ( inner req )
        ( nurl_eprint `[req] ` )
        ( nurl_eprint ( string_data . req method ) )
        ( nurl_eprint ` ` )
        ( nurl_eprint ( string_data . req path ) )
        ( nurl_eprint ` → ` )
        ( nurl_eprint ( nurl_str_int . resp status ) )
        ( nurl_eprint `\n` )
        ^ resp
    }
}

// Permissive CORS middleware. Adds `Access-Control-Allow-Origin: *`
// and `Access-Control-Allow-Headers: Content-Type, Authorization` to
// every response, and short-circuits OPTIONS preflight requests with a
// 204. Suitable for development; production deployments should pin a
// specific origin.
@ with_cors_default
( @ HttpResponse HttpRequest ) inner
→ ( @ HttpResponse HttpRequest ) {
    ^ \ HttpRequest req → HttpResponse {
        : s rm ( string_data . req method )
        ? != 0 ( nurl_str_eq rm `OPTIONS` ) {
            : HttpResponse pre ( response_status_only 204 )
            ( response_set_header pre `Access-Control-Allow-Origin` `*` )
            ( response_set_header pre `Access-Control-Allow-Methods` `GET, POST, PUT, PATCH, DELETE, OPTIONS` )
            ( response_set_header pre `Access-Control-Allow-Headers` `Content-Type, Authorization` )
            ( response_set_header pre `Access-Control-Max-Age` `86400` )
            ^ pre
        } {}
        : HttpResponse resp ( inner req )
        ( response_set_header resp `Access-Control-Allow-Origin` `*` )
        ( response_set_header resp `Access-Control-Allow-Headers` `Content-Type, Authorization` )
        ^ resp
    }
}
