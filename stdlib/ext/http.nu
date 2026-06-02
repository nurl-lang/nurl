// stdlib/ext/http.nu — HTTP client (GET / POST / PUT / DELETE / PATCH
//                       + arbitrary outbound headers)
//
// Wraps the libcurl bridge in stdlib/runtime.c (§14). Synchronous only —
// one call blocks until the response arrives or the request times out
// (30 s by default; not user-tunable in this MVP).
//
// Build:
//   * Link the runtime against -lcurl when libcurl-dev is present.
//     build.sh, nurl.sh and run_tests.sh all detect libcurl via
//     pkg-config and pass `-DNURL_HAVE_LIBCURL` + `-lcurl`.
//   * On native Windows clang the runtime falls back to WinHTTP
//     (-lwinhttp), so http_get / http_post work out of the box on
//     Windows builds without bundling libcurl.
//   * wasm32-wasi targets compile but no HTTP backend is wired in;
//     every call returns HttpErr::HttpOther there.
//
// API (this revision):
//
//   ( header_new   s name s value )                  → Header
//   ( header_free  Header h )                        → v
//   ( header_blob_one s name s value )               → String  one-line blob
//
//   ( http_request   s method s url s body s headers_blob )
//                                                    → ! Response HttpErr
//   ( http_get       s url )                         → ! Response HttpErr
//   ( http_get_with_headers s url s headers_blob )   → ! Response HttpErr
//   ( http_post      s url s body s content_type )   → ! Response HttpErr
//   ( http_post_with_headers s url s body s content_type s headers_blob )
//                                                    → ! Response HttpErr
//   ( http_put       s url s body s content_type )   → ! Response HttpErr
//   ( http_delete    s url )                         → ! Response HttpErr
//   ( http_patch     s url s body s content_type )   → ! Response HttpErr
//
//   ( http_options_default )                         → HttpOptions
//   ( http_request_with_opts s method s url s body s headers_blob HttpOptions opt )
//                                                    → ! Response HttpErr
//   ( http_get_opts  s url HttpOptions opt )         → ! Response HttpErr
//   ( http_post_opts s url s body s content_type HttpOptions opt )
//                                                    → ! Response HttpErr
//
//   ( http_status   Response r )                     → i      shortcut
//   ( http_body_str Response r )                     → s      borrowed view
//   ( http_header_count Response r )                 → i
//   ( http_header_name  Response r i idx )           → s      borrowed
//   ( http_header_value Response r i idx )           → s      borrowed
//   ( response_free Response r )                     → v
//
// Header blob format ("headers_blob"):
//
//   "Name1: Value1\r\nName2: Value2\r\n"
//
// Pass an empty string `` (or NULL via raw FFI) to send no extra headers.
// Lines with no `:` are silently dropped both client-side and by the
// transport. The caller MUST own the blob long enough to outlive the
// http_request call; freeing the backing String afterwards is fine.
//
// http_post / http_put / http_patch take an explicit `content_type`
// argument — pass `` to omit the Content-Type header entirely (curl
// then picks "application/x-www-form-urlencoded" by default for POST,
// or no header at all for the custom verbs). Non-empty `content_type`
// is prepended to the headers blob the runtime sees.
//
// JSON convenience (`http_post_json url j`) lives in
// `stdlib/ext/http_json.nu` so HTTP-only callers don't pay the
// json.nu import cost.
//
// Memory model — single-owner, LLM-friendly:
//
//   * Each call returns a fresh OWNED Response. Caller MUST call
//     `response_free` exactly once on the Result-Ok path. (HttpErr
//     arms produced by these wrappers never carry a Response pointer.)
//   * The Response wraps a heap struct allocated by the C runtime
//     that owns its own copies of the body bytes and every header
//     name/value pair. `response_free` cascades to all of them.
//   * `http_status`, `http_body_str`, `http_header_*` return
//     BORROWED views (raw `s` pointers) into the response. Do not
//     free them; use `string_from` if you need a long-lived `String`
//     copy that outlives the Response.
//   * `headers_blob` arguments are BORROWED — never freed by the
//     runtime. Build them with `header_blob_one` + `string_concat`,
//     or pass a literal directly.
//   * `Header` + `header_new` / `header_free` are kept as a small
//     ergonomic helper for callers that want a typed pair, but the
//     transport itself reads only raw `s` blobs.
//
// Errors — `HttpErr` tags must match the C runtime constants
// in stdlib/runtime.c §14:
//
//   HttpConnect    1   TCP/SSL connect failed
//   HttpTimeout    2   request exceeded the 30 s ceiling
//   HttpTls        3   TLS handshake or cert verification failed
//   HttpDns        4   could not resolve hostname
//   HttpInvalidUrl 5   malformed URL or unsupported scheme
//   HttpOther      6   anything else / runtime built without libcurl

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/errors.nu`

// HttpErr tags — see stdlib/runtime.c §14 NURL_HTTP_ERR_*.
//
// Variants are prefixed (`Http*`) because NURL enum variants live in a
// flat global namespace — `Other` and `NotFound` already belong to
// IoErr, so reusing them here would collide at link time.
: | HttpErr { HttpConnect HttpTimeout HttpTls HttpDns HttpInvalidUrl HttpOther }

: Header { String name String value }

// Response wraps the runtime-owned RawResponse pointer (`s ptr`).
// All accessors go through the FFI helpers in runtime §14 so the
// representation can change without touching call sites.
: Response { s raw }

// HttpOptions bundles the per-request transport overrides that used to
// be hardcoded inside the libcurl orchestrator. Pass one to
// `http_request_with_opts` (or the `*_opts` convenience wrappers) for
// fine control over timeouts, redirect policy, TLS verification and the
// User-Agent header.
//
//   timeout_ms          total request budget; <=0 → 30000 (30 s)
//   connect_timeout_ms  TCP/TLS connect budget; <=0 → 10000 (10 s)
//   follow_redirects    1 = follow 3xx Location (default), 0 = don't
//   max_redirects       cap on followed hops; <0 → unlimited. Ignored
//                       when follow_redirects is 0.
//   verify_tls          1 = verify peer cert + hostname (default),
//                       0 = INSECURE (skip both — dev/self-signed only)
//   user_agent          override; empty `` → `nurl-http/0.1`. BORROWED
//                       (must outlive the call; never freed here).
//
// `user_agent` is a raw `s` (borrowed) so HttpOptions carries no owned
// resources — it needs no free function and is safe to pass by value.
//
// Note: these overrides apply only on the libcurl backend. The native
// WinHTTP / stub backends honour just the two timeouts; redirect / TLS /
// user-agent fields are silently ignored there.
: HttpOptions {
    i timeout_ms
    i connect_timeout_ms
    i follow_redirects
    i max_redirects
    i verify_tls
    s user_agent
}

// Default options: runtime-default timeouts, follow redirects with no
// cap, verify TLS, stock User-Agent.
@ http_options_default → HttpOptions {
    ^ @ HttpOptions { 0 0 1 -1 1 `` }
}

@ header_new s name s value → Header {
    : String n ( string_from name )
    : String v ( string_from value )
    ^ @ Header { n v }
}

@ header_free Header h → v {
    ( string_free . h name )
    ( string_free . h value )
}

// Build a one-line "Name: Value\r\n" String. Useful for assembling a
// blob with `string_concat` when the caller wants typed pieces but not
// a full Vec[Header].
@ header_blob_one s name s value → String {
    : i nl ( nurl_str_len name )
    : i vl ( nurl_str_len value )
    : String b ( string_with_cap + + nl vl 4 )
    ( string_push_str b name )
    ( string_push_str b `: ` )
    ( string_push_str b value )
    ( string_push_str b `\r\n` )
    ^ b
}

// ── Pure-NURL libcurl orchestrator ──────────────────────────────────
//
// On targets built with libcurl (Linux + Docker mingw cross-build),
// the request path is entirely NURL: we drive `curl_easy_init` /
// `_setopt` / `_perform` / `_getinfo` / `_cleanup` through narrow
// monomorphic wrappers in `stdlib/runtime.c §14` (`nurl_curl_*`) and
// populate the same NurlHttpResponse i64-slot layout the WinHTTP
// backend uses. NURL gates on `nurl_curl_available` and falls
// through to the C `nurl_http_perform_full_to` (WinHTTP / stub)
// when libcurl is not linked.
//
// Why C trampolines exist at all:
//   * `curl_easy_setopt` / `_getinfo` are variadic — NURL FFI can't
//     call C varargs safely, so one monomorphic wrapper per arg
//     shape (long / string / pointer).
//   * libcurl write/header callbacks have to be raw C function
//     pointers; `nurl_curl_attach_callbacks` wires them up so the
//     callback symbols stay fully encapsulated.

& `c` @ nurl_curl_easy_init → *u

& `c` @ nurl_curl_easy_cleanup *u eh → v

& `c` @ nurl_curl_easy_perform *u eh → i

& `c` @ nurl_curl_setopt_l *u eh i opt i val → i

& `c` @ nurl_curl_setopt_s *u eh i opt s val → i

& `c` @ nurl_curl_setopt_p *u eh i opt *u val → i

& `c` @ nurl_curl_getinfo_l *u eh i info *u out → i

& `c` @ nurl_curl_slist_append *u list s str → *u

& `c` @ nurl_curl_slist_free_all *u list → v

& `c` @ nurl_curl_attach_callbacks *u eh *u body_buf *u hdr_buf → i

& `c` @ nurl_curl_available → i

// Multi-handle trampolines + NurlHttpStream state helpers — drive
// the streaming pump loop from NURL. See stdlib/runtime.c §14b.
& `c` @ nurl_curl_multi_init → *u

& `c` @ nurl_curl_multi_cleanup *u m → i

& `c` @ nurl_curl_multi_add_handle *u m *u easy → i

& `c` @ nurl_curl_multi_remove_handle *u m *u easy → i

& `c` @ nurl_curl_multi_perform *u m → i

& `c` @ nurl_curl_multi_wait *u m i timeout_ms → i

& `c` @ nurl_curl_multi_drain_done *u m → i

& `c` @ nurl_curl_stream_alloc → *u

& `c` @ nurl_curl_stream_attach_callbacks *u h *u easy → i

& `c` @ nurl_curl_stream_take_body *u h → s

& `c` @ nurl_curl_stream_finalize *u h i curle_result → v

// CURLcode → NURL_HTTP_ERR_* (matches stdlib/runtime.c §14). Unknown
// codes collapse to HttpOther. libcurl's CURLE_* numbers are part of
// its public ABI (documented in curl/curl.h) and stable across
// versions, so hard-coding them here is safe.
@ __curle_to_http_err i rc → i {
    ? == rc 6 { ^ 4 } {}  // CURLE_COULDNT_RESOLVE_HOST → HttpDns
    ? == rc 7 { ^ 1 } {}  // CURLE_COULDNT_CONNECT      → HttpConnect
    ? == rc 28 { ^ 2 } {}  // CURLE_OPERATION_TIMEDOUT   → HttpTimeout
    ? == rc 35 { ^ 3 } {}  // CURLE_SSL_CONNECT_ERROR    → HttpTls
    ? == rc 60 { ^ 3 } {}  // CURLE_PEER_FAILED_VERIFICATION → HttpTls
    ? == rc 3 { ^ 5 } {}  // CURLE_URL_MALFORMAT        → HttpInvalidUrl
    ? == rc 1 { ^ 5 } {}  // CURLE_UNSUPPORTED_PROTOCOL → HttpInvalidUrl
    ^ 6  // HttpOther
}

// Walk a CRLF-delimited "Name: Value\r\n…" blob and append each line
// that contains a ':' to a libcurl slist. Returns the slist head (or
// 0 if the blob is empty / contains no parseable lines). Caller frees
// with `nurl_curl_slist_free_all`. curl_slist_append makes its own
// copy of the line, so we free the slice immediately after each call.
@ __curl_build_slist s blob → *u {
    ? == # i blob 0 { ^ # *u 0 } {}
    : i blen ( nurl_str_len blob )
    ? == blen 0 { ^ # *u 0 } {}
    : ~ * u list # *u 0
    : ~ i i 0
    ~ < i blen {
        : ~ i j i
        ~ && < j blen != ( nurl_str_get blob j ) 10 {
            = j + j 1
        }
        : ~ i n - j i
        ~ && > n 0 == ( nurl_str_get blob + i - n 1 ) 13 {
            = n - n 1
        }
        ? > n 0 {
            : ~ i has_colon 0
            : ~ i k 0
            ~ && < k n == has_colon 0 {
                ? == ( nurl_str_get blob + i k ) 58 { = has_colon 1 } {}
                = k + k 1
            }
            ? != has_colon 0 {
                // `line` is an owned slice of `blob`; curl_slist_append
                // copies the bytes, so `line` is dropped at this arm's
                // exit by the compiler's owned-string auto-drop. Do NOT
                // also free it by hand — that is a double free (the auto
                // drop already releases it).
                : s line ( nurl_str_slice blob i n )
                : *u next ( nurl_curl_slist_append list line )
                ? != # i next 0 { = list next } {}
            } {}
        } {}
        = i + j 1
    }
    ^ list
}

// Pure-NURL libcurl orchestrator. Allocates a 48-byte NurlHttpResponse,
// drives the easy handle through nurl_curl_* trampolines, transfers
// ownership of the body bytes and header items from the callback
// scratch structs into the response, and returns the i64 heap pointer
// (consumed by __http_dispatch). Returns 0 only on the response-struct
// allocation failure — every other failure mode populates err_kind and
// returns a non-zero pointer.
//
// All per-request knobs (timeouts, redirect policy, TLS verification,
// User-Agent) ride in `opt`. The timeout-only `__libcurl_perform_full_to`
// below is a thin shim that builds a default-options struct.
@ __libcurl_perform_full_opts s url s method *u body_ptr i body_len s headers_blob
HttpOptions opt → i {
    : i resp # i ( nurl_zalloc 48 )
    ? == resp 0 { ^ 0 } {}
    : *u rp # *u resp

    ? || == # i url 0 == ( nurl_str_len url ) 0 {
        ( nurl_poke rp 1 5 )  // err_kind = HttpInvalidUrl
        ( nurl_poke rp 4 # i ( strdup `` ) )
        ^ resp
    } {}

    : i timeout_ms . opt timeout_ms
    : i connect_timeout_ms . opt connect_timeout_ms
    : i tmo ? <= timeout_ms 0 30000 timeout_ms
    : i cto ? <= connect_timeout_ms 0 10000 connect_timeout_ms

    : *u eh ( nurl_curl_easy_init )
    ? == # i eh 0 {
        ( nurl_poke rp 1 6 )  // err_kind = HttpOther
        ( nurl_poke rp 4 # i ( strdup `` ) )
        ^ resp
    } {}

    // NurlHttpBuf / NurlHttpHeaderBuf are both 24 B / 3 i64 slots —
    // see the static_asserts in stdlib/runtime.c §14.
    : i bbuf # i ( nurl_zalloc 24 )
    : i hbuf # i ( nurl_zalloc 24 )

    // Per-request overrides from HttpOptions.
    : i follow . opt follow_redirects
    : i maxr . opt max_redirects
    : i verify . opt verify_tls
    : s ua_in . opt user_agent
    : i has_ua && != # i ua_in 0 != ( nurl_str_len ua_in ) 0
    : s ua ? != has_ua 0 ua_in `nurl-http/0.1`

    // Common options.
    ( nurl_curl_setopt_s eh 10002 url )  // CURLOPT_URL
    ( nurl_curl_setopt_l eh 52 ? != follow 0 1 0 )  // CURLOPT_FOLLOWLOCATION
    ? != follow 0 {
        ( nurl_curl_setopt_l eh 68 maxr )  // CURLOPT_MAXREDIRS (<0 = unlimited)
    } {}
    ( nurl_curl_setopt_l eh 64 ? != verify 0 1 0 )  // CURLOPT_SSL_VERIFYPEER
    ( nurl_curl_setopt_l eh 81 ? != verify 0 2 0 )  // CURLOPT_SSL_VERIFYHOST
    ( nurl_curl_setopt_l eh 99 1 )  // CURLOPT_NOSIGNAL (thread-safe)
    ( nurl_curl_setopt_l eh 155 tmo )  // CURLOPT_TIMEOUT_MS
    ( nurl_curl_setopt_l eh 156 cto )  // CURLOPT_CONNECTTIMEOUT_MS
    ( nurl_curl_setopt_s eh 10018 ua )  // CURLOPT_USERAGENT
    ( nurl_curl_setopt_s eh 10102 `` )  // CURLOPT_ACCEPT_ENCODING

    ( nurl_curl_attach_callbacks eh # *u bbuf # *u hbuf )

    : *u slist ( __curl_build_slist headers_blob )
    ? != # i slist 0 {
        ( nurl_curl_setopt_p eh 10023 slist )  // CURLOPT_HTTPHEADER
    } {}

    : i is_post ( nurl_str_eq method `POST` )
    : i is_put ( nurl_str_eq method `PUT` )
    : i is_del ( nurl_str_eq method `DELETE` )
    : i is_patch ( nurl_str_eq method `PATCH` )
    : i has_body && != # i body_ptr 0 > body_len 0
    ? != is_post 0 {
        ( nurl_curl_setopt_l eh 47 1 )  // CURLOPT_POST
        ? != has_body 0 {
            // POSTFIELDSIZE before COPYPOSTFIELDS so libcurl copies the
            // exact byte count (embedded NULs survive) rather than strlen.
            ( nurl_curl_setopt_l eh 60 body_len )  // CURLOPT_POSTFIELDSIZE
            ( nurl_curl_setopt_p eh 10165 body_ptr )  // CURLOPT_COPYPOSTFIELDS
        } {
            ( nurl_curl_setopt_l eh 60 0 )  // CURLOPT_POSTFIELDSIZE
            ( nurl_curl_setopt_s eh 10015 `` )  // CURLOPT_POSTFIELDS (empty)
        }
    } {
        ? || || != is_put 0 != is_del 0 != is_patch 0 {
            ( nurl_curl_setopt_s eh 10036 method )  // CURLOPT_CUSTOMREQUEST
            ? != has_body 0 {
                ( nurl_curl_setopt_l eh 60 body_len )  // CURLOPT_POSTFIELDSIZE
                ( nurl_curl_setopt_p eh 10165 body_ptr )  // CURLOPT_COPYPOSTFIELDS
            } {}
        } {}
    }

    : i rc ( nurl_curl_easy_perform eh )
    ? != rc 0 {
        ( nurl_poke rp 1 ( __curle_to_http_err rc ) )
    } {
        // CURLINFO_RESPONSE_CODE writes a `long` (4 B on LLP64, 8 on
        // LP64). zalloc gives 8; reading slot 0 as i64 picks up the
        // value either way because the trailing pad stays zeroed.
        : i cbuf # i ( nurl_zalloc 8 )
        ( nurl_curl_getinfo_l eh 2097154 # *u cbuf )  // CURLINFO_RESPONSE_CODE
        ( nurl_poke rp 0 ( nurl_peek # *u cbuf 0 ) )
        ( nurl_free # s cbuf )
    }

    ? != # i slist 0 { ( nurl_curl_slist_free_all slist ) } {}
    ( nurl_curl_easy_cleanup eh )

    // Transfer ownership: callback-grown body bytes → response.body;
    // header items array → response.headers. Then free the now-empty
    // 24-byte scratch structs.
    : *u bbp # *u bbuf
    : *u hbp # *u hbuf
    : i bdata ( nurl_peek bbp 0 )
    : i blen ( nurl_peek bbp 1 )
    ? != bdata 0 {
        ( nurl_poke rp 4 bdata )
        ( nurl_poke rp 5 blen )
    } {
        ( nurl_poke rp 4 # i ( strdup `` ) )
    }
    ( nurl_poke rp 3 ( nurl_peek hbp 0 ) )  // headers
    ( nurl_poke rp 2 ( nurl_peek hbp 1 ) )  // header_count

    ( nurl_free # s bbuf )
    ( nurl_free # s hbuf )
    ^ resp
}

// Timeout-only shim over the orchestrator: builds a default-options
// struct (follow redirects, verify TLS, stock UA) overriding just the
// two timeouts. Kept for the existing http_request_to call path.
@ __libcurl_perform_full_to s url s method *u body_ptr i body_len s headers_blob
i timeout_ms i connect_timeout_ms → i {
    : HttpOptions opt @ HttpOptions { timeout_ms connect_timeout_ms 1 -1 1 `` }
    ^ ( __libcurl_perform_full_opts url method body_ptr body_len headers_blob opt )
}

// Internal: dispatch the runtime call result onto a NURL ! Response HttpErr.
// `raw` is the i64 returned by `nurl_http_perform_full` — 0 means the
// runtime couldn't even allocate; non-zero is a heap pointer whose
// `err_kind` slot (slot 1) tells us whether the transport succeeded.
//
// Slot layout of the C NurlHttpResponse heap struct (PURIFY §14, native
// 64-bit; wasm32 layout differs but the wasm HTTP backend always returns
// err_kind = HttpOther so the err-kind probe at slot 1 still works and
// every other slot stays unreachable):
//
//   slot 0  status         i64
//   slot 1  err_kind       i64
//   slot 2  header_count   i64
//   slot 3  headers        *u — NurlHttpHeader[]; each entry is two i64
//                              slots (name, value), 16 bytes on native
//   slot 4  body           *u — owned NUL-terminated body bytes
//   slot 5  body_len       i64
@ __http_dispatch i raw → !Response HttpErr {
    ? == raw 0 { ^ @ !Response HttpErr { F # HttpErr HttpOther } } {}
    : *u rawp # *u raw
    : i ek ( nurl_peek rawp 1 )
    ? != ek 0 {
        ( nurl_http_response_free raw )
        ? == ek 1 { ^ @ !Response HttpErr { F # HttpErr HttpConnect } } {}
        ? == ek 2 { ^ @ !Response HttpErr { F # HttpErr HttpTimeout } } {}
        ? == ek 3 { ^ @ !Response HttpErr { F # HttpErr HttpTls } } {}
        ? == ek 4 { ^ @ !Response HttpErr { F # HttpErr HttpDns } } {}
        ? == ek 5 { ^ @ !Response HttpErr { F # HttpErr HttpInvalidUrl } } {}
        ^ @ !Response HttpErr { F # HttpErr HttpOther }
    } {}
    : s rp # s raw
    : Response r @ Response { rp }
    ^ @ !Response HttpErr { T r }
}

// Core entry point: every other wrapper funnels through here.
@ http_request s method s url s body s headers_blob → !Response HttpErr {
    ^ ( http_request_to method url body headers_blob 0 0 )
}

// Same as http_request but with explicit per-call timeouts in
// milliseconds. Pass 0 (or any non-positive value) to fall back to the
// runtime default of 30 000 ms total / 10 000 ms connect. Useful for
// LLM clients (Anthropic / OpenAI etc.) where a single request can
// take a minute or more, far longer than the MVP HTTP budget.
//
// Dispatch: libcurl path (pure NURL via __libcurl_perform_full_to) on
// targets built with -DNURL_HAVE_LIBCURL; otherwise the C-side WinHTTP
// backend (native Windows) or stub (wasi / no-backend) via
// nurl_http_perform_full_to.
@ http_request_to s method s url s body s headers_blob i timeout_ms i connect_timeout_ms
→ !Response HttpErr {
    ? != ( nurl_curl_available ) 0 {
        // s-body path: recover length via strlen (text/JSON callers).
        : i raw ( __libcurl_perform_full_to url method # *u body ( nurl_str_len body ) headers_blob timeout_ms connect_timeout_ms )
        ^ ( __http_dispatch raw )
    } {}
    : i raw ( nurl_http_perform_full_to url method body headers_blob
    timeout_ms connect_timeout_ms )
    ^ ( __http_dispatch raw )
}

// Full-control entry point: every transport knob comes from `opt`
// (see HttpOptions). On the libcurl backend all fields are honoured; on
// the WinHTTP / stub backends only the two timeouts apply (redirect /
// TLS / user-agent are ignored — same degradation as http_request_to).
@ http_request_with_opts s method s url s body s headers_blob HttpOptions opt
→ !Response HttpErr {
    ? != ( nurl_curl_available ) 0 {
        : i raw ( __libcurl_perform_full_opts url method # *u body ( nurl_str_len body ) headers_blob opt )
        ^ ( __http_dispatch raw )
    } {}
    : i otmo . opt timeout_ms
    : i octo . opt connect_timeout_ms
    : i raw ( nurl_http_perform_full_to url method body headers_blob otmo octo )
    ^ ( __http_dispatch raw )
}

// Convenience: GET / POST with an explicit HttpOptions.
@ http_get_opts s url HttpOptions opt → !Response HttpErr {
    ^ ( http_request_with_opts `GET` url `` `` opt )
}

@ http_post_opts s url s body s content_type HttpOptions opt → !Response HttpErr {
    : String hb ( __with_ct content_type `` )
    : !Response HttpErr res ( http_request_with_opts `POST` url body ( string_data hb ) opt )
    ( string_free hb )
    ^ res
}

// ── GET ─────────────────────────────────────────────────────────────

@ http_get s url → !Response HttpErr {
    ^ ( http_request `GET` url `` `` )
}

@ http_get_with_headers s url s headers_blob → !Response HttpErr {
    ^ ( http_request `GET` url `` headers_blob )
}

// ── POST / PUT / PATCH (body + Content-Type) ───────────────────────
//
// content_type may be `` to skip the Content-Type header (curl picks a
// per-method default). When non-empty, it's prepended to whatever the
// caller put into headers_blob so user-provided headers can still
// override individual fields if desired.

@ __with_ct s ct s headers_blob → String {
    : i ctl ( nurl_str_len ct )
    : i hbl ( nurl_str_len headers_blob )
    : String b ( string_with_cap + + ctl hbl 32 )
    ? > ctl 0 {
        ( string_push_str b `Content-Type: ` )
        ( string_push_str b ct )
        ( string_push_str b `\r\n` )
    } {}
    ? > hbl 0 { ( string_push_str b headers_blob ) } {}
    ^ b
}

@ http_post s url s body s content_type → !Response HttpErr {
    : String hb ( __with_ct content_type `` )
    : !Response HttpErr res ( http_request `POST` url body ( string_data hb ) )
    ( string_free hb )
    ^ res
}

@ http_post_with_headers s url s body s content_type s headers_blob → !Response HttpErr {
    : String hb ( __with_ct content_type headers_blob )
    : !Response HttpErr res ( http_request `POST` url body ( string_data hb ) )
    ( string_free hb )
    ^ res
}

@ http_put s url s body s content_type → !Response HttpErr {
    : String hb ( __with_ct content_type `` )
    : !Response HttpErr res ( http_request `PUT` url body ( string_data hb ) )
    ( string_free hb )
    ^ res
}

@ http_patch s url s body s content_type → !Response HttpErr {
    : String hb ( __with_ct content_type `` )
    : !Response HttpErr res ( http_request `PATCH` url body ( string_data hb ) )
    ( string_free hb )
    ^ res
}

@ http_delete s url → !Response HttpErr {
    ^ ( http_request `DELETE` url `` `` )
}

// ── Binary-safe body (length-carrying ( Vec u )) ───────────────────
//
// The s-body http_request_* family recovers the body length via
// strlen, so a body with embedded NUL bytes (binary file uploads,
// MessagePack, protobuf, …) truncates at the first NUL. These
// variants carry the body as a length-tracked ( Vec u ) and ship it
// via CURLOPT_COPYPOSTFIELDS + an explicit POSTFIELDSIZE, so the exact
// byte count is sent. `body` is BORROWED — the caller still owns it.
//
// Backend note: binary fidelity requires the libcurl backend (the
// default on Linux/macOS/Windows builds with -DNURL_HAVE_LIBCURL). On
// the WinHTTP / stub fallback the body round-trips through a
// NUL-terminated s and truncates at the first embedded NUL.
@ http_request_bytes_to s method s url ( Vec u ) body s headers_blob
i timeout_ms i connect_timeout_ms → !Response HttpErr {
    ? != ( nurl_curl_available ) 0 {
        : i raw ( __libcurl_perform_full_to url method ( vec_data [u] body ) ( vec_len [u] body ) headers_blob timeout_ms connect_timeout_ms )
        ^ ( __http_dispatch raw )
    } {}
    : String tmp ( string_from_bytes ( vec_data [u] body ) ( vec_len [u] body ) )
    : i raw ( nurl_http_perform_full_to url method ( string_data tmp ) headers_blob timeout_ms connect_timeout_ms )
    ( string_free tmp )
    ^ ( __http_dispatch raw )
}

@ http_request_bytes s method s url ( Vec u ) body s headers_blob → !Response HttpErr {
    ^ ( http_request_bytes_to method url body headers_blob 0 0 )
}

@ http_post_bytes s url ( Vec u ) body s content_type → !Response HttpErr {
    : String hb ( __with_ct content_type `` )
    : !Response HttpErr res ( http_request_bytes `POST` url body ( string_data hb ) )
    ( string_free hb )
    ^ res
}

@ http_put_bytes s url ( Vec u ) body s content_type → !Response HttpErr {
    : String hb ( __with_ct content_type `` )
    : !Response HttpErr res ( http_request_bytes `PUT` url body ( string_data hb ) )
    ( string_free hb )
    ^ res
}

// ── Accessors (borrowed views) — pure NURL over the NurlHttpResponse
//                                 heap struct's i64-slot layout (see
//                                 __http_dispatch above for the map).
//
// Strings returned here point into the response struct's owned storage
// and are valid until `response_free`. The cast pattern is
// `^ # s ( nurl_peek ... )` so the auto-detector sees an i64 binding at
// fn exit and does NOT tag the @-fn's return as owned (avoiding a
// spurious auto-drop of borrowed bytes).

@ http_status Response r → i {
    : s rp . r raw
    : *u rawp # *u rp
    ^ ( nurl_peek rawp 0 )
}

@ http_body_str Response r → s {
    : s rp . r raw
    : *u rawp # *u rp
    : i bp ( nurl_peek rawp 4 )
    ^ ? == bp 0 `` # s bp
}

@ http_header_count Response r → i {
    : s rp . r raw
    : *u rawp # *u rp
    ^ ( nurl_peek rawp 2 )
}

@ http_header_name Response r i idx → s {
    : s rp . r raw
    : *u rawp # *u rp
    : i hc ( nurl_peek rawp 2 )
    ? || < idx 0 >= idx hc { ^ `` } {}
    : i ap ( nurl_peek rawp 3 )
    ? == ap 0 { ^ `` } {}
    : *u arr # *u ap
    : i name_slot * idx 2
    : i np ( nurl_peek arr name_slot )
    ^ ? == np 0 `` # s np
}

@ http_header_value Response r i idx → s {
    : s rp . r raw
    : *u rawp # *u rp
    : i hc ( nurl_peek rawp 2 )
    ? || < idx 0 >= idx hc { ^ `` } {}
    : i ap ( nurl_peek rawp 3 )
    ? == ap 0 { ^ `` } {}
    : *u arr # *u ap
    : i name_slot * idx 2
    : i value_slot + name_slot 1
    : i vp ( nurl_peek arr value_slot )
    ^ ? == vp 0 `` # s vp
}

@ response_free Response r → v {
    : s rp . r raw
    : i raw # i rp
    ( nurl_http_response_free raw )
}

// Render a HttpErr variant name. Useful for diagnostic messages without
// a full match cascade at every call site.
@ http_err_name HttpErr e → s {
    ^ ?? e {
        HttpConnect → `HttpConnect`
        HttpTimeout → `HttpTimeout`
        HttpTls → `HttpTls`
        HttpDns → `HttpDns`
        HttpInvalidUrl → `HttpInvalidUrl`
        HttpOther → `HttpOther`
    }
}

// ── HTTP streaming (pull-based) ─────────────────────────────────────
//
// For SSE / chunked responses where the body arrives over time and the
// caller wants to react to each chunk before the request completes.
// Backed by libcurl's multi handle in `runtime.c §14b`; WinHTTP and
// WASI builds return `HttpOther` on open.
//
//   ( http_stream_open_to s method s url s body s headers_blob
//                         i timeout_ms i connect_timeout_ms )
//                                                  → ! HttpStream HttpErr
//   ( http_stream_open    s method s url s body s headers_blob )
//                                                  → ! HttpStream HttpErr
//   ( http_stream_next    HttpStream s )           → ? String
//                       owned chunk; None = EOF or error (probe via
//                       http_stream_err / http_stream_status). Each
//                       chunk is whatever libcurl flushed since the
//                       last call — NOT a single SSE frame. Compose
//                       with `SseDecoder` (below) for event-aligned
//                       reads.
//   ( http_stream_status  HttpStream s )           → i
//                       Final HTTP status, valid after http_stream_next
//                       has returned None.
//   ( http_stream_err     HttpStream s )           → ? HttpErr
//                       None = transfer succeeded; Some(e) = failure.
//   ( http_stream_close   HttpStream s )           → v
//                       MUST be called exactly once per opened stream.
//
// Memory model:
//   * Each `http_stream_next` chunk is a freshly-owned `String` —
//     callers are responsible for freeing them. Returning a Vec[u]
//     instead would double the per-chunk allocation cost; SSE is text
//     so String is the right type.
//   * The HttpStream handle owns the libcurl multi+easy pair and a
//     small accumulator buffer. `http_stream_close` cascades to all of
//     them; do not call after close.
//   * Inputs (method/url/body/headers_blob) are BORROWED — a snapshot
//     is taken inside libcurl, so the caller may free them right away.

// NurlHttpStream layout (PURIFY §14b, native 64-bit; 14 × i64 slots,
// pinned by static_assert in stdlib/runtime.c §14b):
//
//   slot 0  multi          CURLM*
//   slot 1  easy           CURL*
//   slot 2  req_headers    struct curl_slist*
//   slot 3  body_buf.data  char*
//   slot 4  body_buf.len   i64
//   slot 5  body_buf.cap   i64
//   slot 6  hdr_buf.items  NurlHttpHeader*
//   slot 7  hdr_buf.len    i64
//   slot 8  hdr_buf.cap    i64
//   slot 9  headers_done   bool (i64)
//   slot 10 still_running  i64
//   slot 11 finished       bool (i64)
//   slot 12 status         i64
//   slot 13 err_kind       i64

// Pure-NURL libcurl multi orchestrator. Mirrors the C
// nurl_http_stream_open_to in stdlib/runtime.c §14b (now stub-only
// when libcurl is linked — NURL drives via this path). Returns the
// i64 heap pointer; 0 only on the state-struct allocation failure.
@ __http_stream_open_to_libcurl s method s url *u body_ptr i body_len s headers_blob
i timeout_ms i connect_timeout_ms → i {
    : *u state ( nurl_curl_stream_alloc )
    ? == # i state 0 { ^ 0 } {}

    : *u multi ( nurl_curl_multi_init )
    : *u easy ( nurl_curl_easy_init )
    ? || == # i multi 0 == # i easy 0 {
        ? != # i multi 0 { ( nurl_curl_multi_cleanup multi ) } {}
        ? != # i easy 0 { ( nurl_curl_easy_cleanup easy ) } {}
        ( nurl_poke state 13 6 )  // err_kind = HttpOther
        ( nurl_poke state 11 1 )  // finished
        ^ # i state
    } {}
    ( nurl_poke state 0 # i multi )
    ( nurl_poke state 1 # i easy )

    : i tmo ? <= timeout_ms 0 30000 timeout_ms
    : i cto ? <= connect_timeout_ms 0 10000 connect_timeout_ms
    : s url_or_empty ? == # i url 0 `` url

    ( nurl_curl_setopt_s easy 10002 url_or_empty )  // CURLOPT_URL
    ( nurl_curl_setopt_l easy 52 1 )  // CURLOPT_FOLLOWLOCATION
    ( nurl_curl_setopt_l easy 99 1 )  // CURLOPT_NOSIGNAL
    ( nurl_curl_setopt_l easy 155 tmo )  // CURLOPT_TIMEOUT_MS
    ( nurl_curl_setopt_l easy 156 cto )  // CURLOPT_CONNECTTIMEOUT_MS
    ( nurl_curl_setopt_s easy 10018 `nurl-http/0.1` )  // CURLOPT_USERAGENT
    ( nurl_curl_setopt_s easy 10102 `` )  // CURLOPT_ACCEPT_ENCODING

    ( nurl_curl_stream_attach_callbacks state easy )

    : *u slist ( __curl_build_slist headers_blob )
    ? != # i slist 0 {
        ( nurl_poke state 2 # i slist )
        ( nurl_curl_setopt_p easy 10023 slist )  // CURLOPT_HTTPHEADER
    } {}

    : i is_post ( nurl_str_eq method `POST` )
    : i is_get ( nurl_str_eq method `GET` )
    : i has_body && != # i body_ptr 0 > body_len 0
    ? != is_post 0 {
        ( nurl_curl_setopt_l easy 47 1 )  // CURLOPT_POST
        ? != has_body 0 {
            // COPYPOSTFIELDS copies body_len bytes at setopt time, so the
            // caller may free the buffer right after open — and embedded
            // NULs survive (POSTFIELDSIZE set first).
            ( nurl_curl_setopt_l easy 60 body_len )  // CURLOPT_POSTFIELDSIZE
            ( nurl_curl_setopt_p easy 10165 body_ptr )  // CURLOPT_COPYPOSTFIELDS
        } {
            ( nurl_curl_setopt_l easy 60 0 )  // CURLOPT_POSTFIELDSIZE
            ( nurl_curl_setopt_s easy 10015 `` )  // CURLOPT_POSTFIELDS (empty)
        }
    } {
        ? == is_get 0 {
            ( nurl_curl_setopt_s easy 10036 method )  // CURLOPT_CUSTOMREQUEST
            ? != has_body 0 {
                ( nurl_curl_setopt_l easy 60 body_len )  // CURLOPT_POSTFIELDSIZE
                ( nurl_curl_setopt_p easy 10165 body_ptr )  // CURLOPT_COPYPOSTFIELDS
            } {}
        } {}
    }

    : i mrc ( nurl_curl_multi_add_handle multi easy )
    ? != mrc 0 {
        ( nurl_poke state 13 6 )  // err_kind = HttpOther
        ( nurl_poke state 11 1 )  // finished
        ^ # i state
    } {}
    ( nurl_poke state 10 1 )  // still_running = 1
    ^ # i state
}

// One iteration of the multi-perform pump. Returns 1 if the caller
// should keep pumping, 0 if we've reached a stop condition (finished,
// CURLM error, or fresh data). Used by both __http_stream_next_libcurl
// and __http_stream_pump_headers_libcurl.
@ __http_stream_pump_once * u state → v {
    : *u multi # *u ( nurl_peek state 0 )
    : i still ( nurl_curl_multi_perform multi )
    ? < still 0 {
        ( nurl_poke state 13 6 )  // err_kind = HttpOther
        ( nurl_poke state 11 1 )  // finished
        ^ # v 0
    } {}
    ( nurl_poke state 10 still )
    ? == still 0 {
        : i rc ( nurl_curl_multi_drain_done multi )
        ? >= rc 0 { ( nurl_curl_stream_finalize state rc ) } { ( nurl_poke state 11 1 ) }
        ^ # v 0
    } {}
    ( nurl_curl_multi_wait multi 100 )
}

@ __http_stream_next_libcurl i raw → s {
    : *u state # *u raw
    ~ && == ( nurl_peek state 4 ) 0 == ( nurl_peek state 11 ) 0 {
        ( __http_stream_pump_once state )
    }
    ? == ( nurl_peek state 4 ) 0 { ^ # s 0 } {}
    ^ ( nurl_curl_stream_take_body state )
}

@ __http_stream_pump_headers_libcurl i raw → i {
    : *u state # *u raw
    ~ && == ( nurl_peek state 9 ) 0 == ( nurl_peek state 11 ) 0 {
        ( __http_stream_pump_once state )
    }
    ^ ( nurl_peek state 12 )
}

: HttpStream { i raw }

// Shared open-result dispatch for both the s-body and ( Vec u )-body
// stream openers. Probes err_kind in case open succeeded structurally
// but libcurl refused (e.g. malformed URL).
@ __http_stream_dispatch_open i raw → !HttpStream HttpErr {
    ? == raw 0 {
        ^ @ !HttpStream HttpErr { F # HttpErr HttpOther }
    } {}
    : i ek ( nurl_peek # *u raw 13 )
    ? != ek 0 {
        ( nurl_http_stream_close raw )
        ? == ek 1 { ^ @ !HttpStream HttpErr { F # HttpErr HttpConnect } } {}
        ? == ek 2 { ^ @ !HttpStream HttpErr { F # HttpErr HttpTimeout } } {}
        ? == ek 3 { ^ @ !HttpStream HttpErr { F # HttpErr HttpTls } } {}
        ? == ek 4 { ^ @ !HttpStream HttpErr { F # HttpErr HttpDns } } {}
        ? == ek 5 { ^ @ !HttpStream HttpErr { F # HttpErr HttpInvalidUrl } } {}
        ^ @ !HttpStream HttpErr { F # HttpErr HttpOther }
    } {}
    ^ @ !HttpStream HttpErr { T @ HttpStream { raw } }
}

@ http_stream_open_to s method s url s body s headers_blob
i timeout_ms i connect_timeout_ms
→ !HttpStream HttpErr {
    : i raw ? != ( nurl_curl_available ) 0
    ( __http_stream_open_to_libcurl method url # *u body ( nurl_str_len body ) headers_blob timeout_ms connect_timeout_ms )
    ( nurl_http_stream_open_to method url body headers_blob timeout_ms connect_timeout_ms )
    ^ ( __http_stream_dispatch_open raw )
}

// Binary-safe streaming open: the body is a length-carrying ( Vec u ),
// so embedded NUL bytes survive (the s-body opener recovers length via
// strlen). COPYPOSTFIELDS copies the bytes during open, so `body` may be
// freed as soon as this returns. libcurl backend only — the stub
// fallback round-trips through a NUL-terminated s (truncates at the
// first embedded NUL).
@ http_stream_open_bytes_to s method s url ( Vec u ) body s headers_blob
i timeout_ms i connect_timeout_ms
→ !HttpStream HttpErr {
    ? != ( nurl_curl_available ) 0 {
        : i raw ( __http_stream_open_to_libcurl method url ( vec_data [u] body ) ( vec_len [u] body ) headers_blob timeout_ms connect_timeout_ms )
        ^ ( __http_stream_dispatch_open raw )
    } {}
    : String tmp ( string_from_bytes ( vec_data [u] body ) ( vec_len [u] body ) )
    : i raw ( nurl_http_stream_open_to method url ( string_data tmp ) headers_blob timeout_ms connect_timeout_ms )
    ( string_free tmp )
    ^ ( __http_stream_dispatch_open raw )
}

@ http_stream_open s method s url s body s headers_blob
→ !HttpStream HttpErr {
    ^ ( http_stream_open_to method url body headers_blob 0 0 )
}

@ http_stream_next HttpStream st → ?String {
    : i raw . st raw
    : s p ? != ( nurl_curl_available ) 0
    ( __http_stream_next_libcurl raw )
    ( nurl_http_stream_next raw )
    ? == # i p 0 { ^ @ ?String { F # String 0 } } {}
    : String s ( string_from p )
    ^ @ ?String { T s }
}

@ http_stream_status HttpStream st → i {
    : i raw . st raw
    ^ ( nurl_peek # *u raw 12 )
}

@ http_stream_err HttpStream st → ?HttpErr {
    : i raw . st raw
    : i ek ( nurl_peek # *u raw 13 )
    ? == ek 0 { ^ @ ?HttpErr { F # HttpErr HttpOther } } {}
    ? == ek 1 { ^ @ ?HttpErr { T # HttpErr HttpConnect } } {}
    ? == ek 2 { ^ @ ?HttpErr { T # HttpErr HttpTimeout } } {}
    ? == ek 3 { ^ @ ?HttpErr { T # HttpErr HttpTls } } {}
    ? == ek 4 { ^ @ ?HttpErr { T # HttpErr HttpDns } } {}
    ? == ek 5 { ^ @ ?HttpErr { T # HttpErr HttpInvalidUrl } } {}
    ^ @ ?HttpErr { T # HttpErr HttpOther }
}

@ http_stream_close HttpStream st → v {
    : i raw . st raw
    ( nurl_http_stream_close raw )
}

// Pump the multi handle until the upstream response headers are
// received OR the transfer terminates. After this returns:
//   * `http_stream_status` carries the upstream status code (0 if the
//     transfer aborted before the status line was received).
//   * `http_stream_header_count` / `_name` / `_value` are populated.
//   * `http_stream_next` may now be called to pull body chunks.
//
// Returns the upstream status code (0 = no status, e.g. DNS / connect
// failure — call `http_stream_err` to learn why). 1xx informational
// responses are skipped automatically; the value here always reflects
// the FINAL response.
//
// Used by reverse-proxy code (`stdlib/ext/http_proxy.nu`) to learn the
// upstream status + headers before deciding what to write back to the
// downstream client.
@ http_stream_pump_headers HttpStream st → i {
    : i raw . st raw
    ^ ? != ( nurl_curl_available ) 0
    ( __http_stream_pump_headers_libcurl raw )
    ( nurl_http_stream_pump_headers raw )
}

@ http_stream_header_count HttpStream st → i {
    : i raw . st raw
    ^ ( nurl_peek # *u raw 7 )
}

// BORROWED — lifetime tied to the HttpStream handle. Free not required
// (and not allowed); copy with `string_from` if a long-lived String is
// needed.
@ http_stream_header_name HttpStream st i idx → s {
    : i raw . st raw
    : i hdrs ( nurl_peek # *u raw 6 )
    ? || == hdrs 0 || < idx 0 >= idx ( nurl_peek # *u raw 7 ) { ^ `` } {}
    ^ # s ( nurl_peek # *u hdrs * idx 2 )
}

@ http_stream_header_value HttpStream st i idx → s {
    : i raw . st raw
    : i hdrs ( nurl_peek # *u raw 6 )
    ? || == hdrs 0 || < idx 0 >= idx ( nurl_peek # *u raw 7 ) { ^ `` } {}
    ^ # s ( nurl_peek # *u hdrs + 1 * idx 2 )
}

// ── SSE parser (Server-Sent Events / W3C, Anthropic streaming) ──────
//
// Stateless helpers — the caller owns an accumulator (typically a
// `~ String acc`), feeds each `http_stream_next` chunk into it via
// `string_push_str`, and pops complete events with the loop below.
// We do not bundle the accumulator into a struct because NURL has no
// surface syntax for replacing a typed struct field — keeping the
// accumulator as a local mutable binding (`= acc <fresh String>`) is
// the idiomatic shape, and it sidesteps the issue cleanly.
//
// Frame format: lines separated by `\n`, frame terminated by an empty
// line (i.e. `\n\n`). Recognised fields: `event`, `data`, `id`. Lines
// beginning with `:` are comments per the spec (Anthropic emits them
// as keepalives). Multi-line `data:` lines are joined with `\n`.
//
// Typical loop:
//
//   : ~ String acc ( string_with_cap 1024 )
//   ~ T {
//     : ? String chopt ( http_stream_next st )
//     ?? chopt {
//       T ch → {
//         ( string_push_str acc ( string_data ch ) )
//         ( string_free ch )
//         ~ T {
//           : i fend ( sse_frame_end ( string_data acc ) ( string_len acc ) )
//           ? < fend 0 { ! T } {}
//           : SseEvent ev ( sse_parse_frame ( string_data acc ) fend )
//           // … use ev …
//           ( sse_event_free ev )
//           : i total ( string_len acc )
//           : i drop + fend 2
//           : String rest ( string_substr acc drop - total drop )
//           ( string_free acc )
//           = acc rest
//         }
//       }
//       F → { ! T }
//     }
//   }
//   ( string_free acc )

: SseEvent { String name String data String id }

// Copy bytes [from, from+n) of a raw `s` into a fresh owned String.
// Used internally by the SSE parser to materialise frame field tokens.
@ __sse_substr s p i from i n → String {
    : String out ( string_with_cap n )
    : ~ i k 0
    ~ < k n {
        ( string_push_char out ( nurl_str_get p + from k ) )
        = k + k 1
    }
    ^ out
}

@ sse_event_free SseEvent e → v {
    ( string_free . e name )
    ( string_free . e data )
    ( string_free . e id )
}

// Find the first `\n\n` separator inside the accumulator buffer. Returns
// the byte offset of the FIRST `\n` of the pair (so the frame is
// `acc[0 .. offset)` and the next frame starts at `offset + 2`). Returns
// -1 when no complete frame is buffered yet.
@ sse_frame_end s acc i acc_len → i {
    : ~ i i 0
    ~ < i - acc_len 1 {
        ? & == ( nurl_str_get acc i ) 10 == ( nurl_str_get acc + i 1 ) 10 {
            ^ i
        } {}
        = i + i 1
    }
    ^ -1
}

// Parse a complete frame (the bytes up to but excluding the `\n\n`
// separator). Returns an owned SseEvent — empty fields are valid (e.g.
// no `event:` line → name = ""). Caller frees with `sse_event_free`.
@ sse_parse_frame s frame i frame_len → SseEvent {
    : String name ( string_new )
    : String data ( string_new )
    : String id ( string_new )
    : ~ b first_data_line T

    : ~ i ls 0
    : ~ i i 0
    ~ <= i frame_len {
        : i c ? < i frame_len ( nurl_str_get frame i ) 10
        ? == c 10 {
            : i llen - i ls
            ? > llen 0 {
                : i firstc ( nurl_str_get frame ls )
                ? == firstc 58 {
                    // Comment line — skip.
                } {
                    // Find the colon delimiter inside [ls, i).
                    : ~ i ci ls
                    : ~ b found F
                    ~ & ! found < ci i {
                        ? == ( nurl_str_get frame ci ) 58 { = found T } {
                            = ci + ci 1
                        }
                    }
                    : i fld_len - ci ls
                    : i vstart ? found + ci 1 i
                    ? & found < vstart i {
                        ? == ( nurl_str_get frame vstart ) 32 { = vstart + vstart 1 } {}
                    } {}
                    : i vlen ? found - i vstart 0
                    : String fld ( __sse_substr frame ls fld_len )
                    : String val ( __sse_substr frame vstart vlen )

                    : s fp ( string_data fld )
                    ? != ( nurl_str_eq fp `event` ) 0 {
                        ( string_free name )
                        = name ( string_from ( string_data val ) )
                    } {
                        ? != ( nurl_str_eq fp `data` ) 0 {
                            ? first_data_line {
                                = first_data_line F
                            } {
                                ( string_push_str data `\n` )
                            }
                            ( string_push_str data ( string_data val ) )
                        } {
                            ? != ( nurl_str_eq fp `id` ) 0 {
                                ( string_free id )
                                = id ( string_from ( string_data val ) )
                            } {}
                        }
                    }
                    ( string_free fld )
                    ( string_free val )
                }
            } {}
            = ls + i 1
        } {}
        = i + i 1
    }
    ^ @ SseEvent { name data id }
}
