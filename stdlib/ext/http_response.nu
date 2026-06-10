// stdlib/ext/http_response.nu — HTTP/1.1 response writer. Pure NURL.
// `response_serialize` produces an owned `( Vec u )` wire-payload;
// `response_begin_chunked` / `response_write_chunk` /
// `response_end_chunked` stream directly to a TcpConn for SSE /
// Server-Sent Events use.
//
// API (this revision):
//
//   ( response_new i status )                     → HttpResponse
//   ( http_response_free HttpResponse r )              → v
//   ( response_set_header  HttpResponse r s name s value ) → v
//   ( response_add_header  HttpResponse r s name s value ) → v
//   ( response_set_body_str   HttpResponse r s text )      → v
//   ( response_set_body_bytes HttpResponse r ( Vec u ) )   → v
//   ( response_set_body_json  HttpResponse r Json j )      → v
//
//   ( response_text     i status s text )          → HttpResponse
//   ( response_json     i status Json j )          → HttpResponse
//   ( response_redirect i status s location )      → HttpResponse
//   ( response_status_only i status )              → HttpResponse
//   ( response_error    i status s msg )           → HttpResponse
//
//   ( response_serialize HttpResponse r )          → ( Vec u )
//   ( status_reason i code )                       → s     (borrowed)
//
//   ( response_begin_chunked TcpConn c i status ( Vec Header ) hs ) → ! v NetErr
//   ( response_write_chunk   TcpConn c ( Vec u ) chunk ) → ! v NetErr
//   ( response_end_chunked   TcpConn c )                 → ! v NetErr
//
// Memory model:
//
//   * `response_new` allocates a fresh HttpResponse with empty headers
//     and empty body. Caller frees with `http_response_free` — cascades into
//     every Header (name + value) and the body Vec.
//   * `response_set_header` REPLACES any existing header with the same
//     name (case-insensitive ASCII match per RFC 7230 §3.2). If no
//     match exists, a fresh entry is appended. This is the right
//     default for single-valued headers like Content-Type, Location,
//     Cache-Control, etc. — which is the vast majority of headers.
//     Both `name` and `value` are copied; the caller keeps ownership
//     of the input raw `s`.
//   * `response_add_header` always APPENDS a new header line without
//     checking for existing entries. Use this for response headers
//     that legitimately repeat — primarily `Set-Cookie` (RFC 6265
//     §3) and `WWW-Authenticate` challenges.
//   * `response_set_body_*` BORROW their inputs (raw `s`, `( Vec u )`
//     bytes, Json) — the source is not moved. The body Vec is
//     overwritten (existing contents freed first).
//   * `response_serialize` returns an OWNED `( Vec u )` containing the
//     full HTTP/1.1 wire payload (status line + headers + blank line +
//     body). It does NOT consume the response — caller still owns the
//     HttpResponse and must `http_response_free` it. Auto-prepends
//     `Content-Length` (computed from the body Vec) UNLESS a
//     `Transfer-Encoding` header is present (RFC 7230 §3.3.2 forbids
//     both at once).
//   * Convenience helpers (`response_text` etc.) all return a fresh
//     OWNED HttpResponse; caller frees as usual.
//   * The chunked-streaming helpers BORROW the TcpConn and the chunk
//     bytes; nothing is moved. The transition Connection: close is
//     not implied — caller manages keep-alive separately.
//
// Notes on inherited language gaps:
//
//   * Multi-field structs can't ride `! T E` Ok arms. `response_*`
//     constructors return HttpResponse directly (it's a pure
//     allocation, no failure mode). Streaming helpers DO use
//     `! v NetErr` because `v` (i64-fits) and `NetErr` (enum) both
//     ride the encoding fine.
//   * `vec_get [Header]` miscompiles for multi-field Header. Iteration
//     over headers uses `vec_data` + `*Header` direct-pointer access.

$ `stdlib/std/net.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/ext/http.nu`
$ `stdlib/ext/json.nu`

// ── HttpResponse struct + lifecycle ───────────────────────────────────

: HttpResponse {
    i status
    ( Vec Header ) headers
    ( Vec u ) body
}

@ response_new i status → HttpResponse {
    ^ @ HttpResponse {
        status
        ( vec_new [Header] )
        ( vec_new [u] )
    }
}

@ http_response_free HttpResponse r → v {
    ( vec_free_with [Header] . r headers \ Header h → v { ( header_free h ) } )
    ( vec_free [u] . r body )
}

// ── Header / body mutators ────────────────────────────────────────────

// Set-or-replace: walks the existing headers, frees the first entry
// whose name matches `name` case-insensitively, and writes the new
// (name, value) pair into that slot. If nothing matches, the new
// header is appended at the end. Insertion order is preserved for
// other headers — only the matching slot is touched.
@ response_set_header HttpResponse r s name s value → v {
    : i n ( vec_len [Header] . r headers )
    : *Header hdata ( vec_data [Header] . r headers )
    : ~ i k 0
    : ~ b found F
    ~ & ! found < k n {
        : Header h . hdata k
        ? ( __header_name_eq_ci . h name name ) {
            ( header_free h )
            ( vec_set [Header] . r headers k ( header_new name value ) )
            = found T
        } {}
        = k + k 1
    }
    ? ! found {
        ( vec_push [Header] . r headers ( header_new name value ) )
    } {}
}

// Strict-append: pushes a fresh header line without scanning for
// duplicates. Required for headers that the HTTP spec permits (or
// requires) to repeat — `Set-Cookie` (one entry per cookie) and
// `WWW-Authenticate` (one entry per supported scheme) are the
// canonical cases.
@ response_add_header HttpResponse r s name s value → v {
    ( vec_push [Header] . r headers ( header_new name value ) )
}

// Replace the body with a copy of `text`. Existing body bytes are
// dropped first via `vec_clear` (releases length but keeps cap).
@ response_set_body_str HttpResponse r s text → v {
    ( vec_clear [u] . r body )
    ( bytes_extend_str . r body text )
}

// Replace the body with a copy of `bytes`. Source vector is BORROWED;
// this performs a bytewise copy via vec_extend.
@ response_set_body_bytes HttpResponse r ( Vec u ) bytes → v {
    ( vec_clear [u] . r body )
    ( vec_extend [u] . r body bytes )
}

// JSON convenience: serialises `j`, copies into the body, and sets
// `Content-Type: application/json; charset=utf-8` IF no Content-Type
// header has been pinned yet (case-insensitive scan). Caller still
// owns `j` — we never consume it.
@ response_set_body_json HttpResponse r Json j → v {
    : String s ( json_stringify j )
    ( vec_clear [u] . r body )
    ( bytes_extend_str . r body ( string_data s ) )
    ( string_free s )
    ? ( __has_header_ci . r headers `Content-Type` ) {} {
        ( response_set_header r `Content-Type` `application/json; charset=utf-8` )
    }
}

// ── Convenience builders ──────────────────────────────────────────────

@ response_text i status s text → HttpResponse {
    : HttpResponse r ( response_new status )
    ( response_set_header r `Content-Type` `text/plain; charset=utf-8` )
    ( response_set_body_str r text )
    ^ r
}

@ response_json i status Json j → HttpResponse {
    : HttpResponse r ( response_new status )
    ( response_set_body_json r j )
    ^ r
}

// 30x redirect. Default to 302; the caller passes whatever variant
// (301 / 303 / 307 / 308) is appropriate.
@ response_redirect i status s location → HttpResponse {
    : HttpResponse r ( response_new status )
    ( response_set_header r `Location` location )
    ( response_set_header r `Content-Length` `0` )
    ^ r
}

// 204 / 304 / etc — body-less response. Sets Content-Length: 0
// explicitly so dumb clients don't hang waiting for a body.
@ response_status_only i status → HttpResponse {
    : HttpResponse r ( response_new status )
    ( response_set_header r `Content-Length` `0` )
    ^ r
}

@ response_error i status s msg → HttpResponse {
    ^ ( response_text status msg )
}

// ── Serialisation ─────────────────────────────────────────────────────
// Build the on-the-wire byte sequence for `r`. The output is fully
// owned — caller frees with `( vec_free [u] out )`. Content-Length is
// auto-prepended unless the response carries a Transfer-Encoding
// header (RFC 7230 §3.3.2). Headers are emitted in insertion order.
// Append `str`'s bytes to `out`, dropping any CR (13) / LF (10). Header
// field names and values are emitted through this so a value reflected
// from untrusted input (a redirect Location, an echoed header, …) cannot
// inject `\r\n<injected-header>` and split the response (CWE-113). RFC
// 9110 §5.5 forbids CR/LF in field values anyway, so stripping them is
// lossless for any well-formed header.
@ __push_header_no_crlf ( Vec u ) out s str → v {
    : i n ( nurl_str_len str )
    : ~ i k 0
    ~ < k n {
        : i c & 255 ( nurl_str_get str k )
        ? | == c 13 == c 10 {} { ( vec_push [u] out # u c ) }
        = k + k 1
    }
}

@ response_serialize HttpResponse r → ( Vec u ) {
    : ( Vec u ) out ( vec_with_cap [u] + 64 ( vec_len [u] . r body ) )

    // ── Status line: "HTTP/1.1 <code> <reason>\r\n" ──
    ( bytes_extend_str out `HTTP/1.1 ` )
    ( bytes_push_int out . r status )
    ( bytes_extend_str out ` ` )
    ( bytes_extend_str out ( status_reason . r status ) )
    ( bytes_extend_str out `\r\n` )

    // ── Header lines ──
    : i hcount ( vec_len [Header] . r headers )
    : *Header hdata ( vec_data [Header] . r headers )
    : ~ i k 0
    ~ < k hcount {
        : Header h . hdata k
        ( __push_header_no_crlf out ( string_data . h name ) )
        ( bytes_extend_str out `: ` )
        ( __push_header_no_crlf out ( string_data . h value ) )
        ( bytes_extend_str out `\r\n` )
        = k + k 1
    }

    // ── Auto-Content-Length (unless TE was set) ──
    : b has_te ( __has_header_ci . r headers `Transfer-Encoding` )
    : b has_cl ( __has_header_ci . r headers `Content-Length` )
    ? & ! has_te ! has_cl {
        ( bytes_extend_str out `Content-Length: ` )
        ( bytes_push_int out ( vec_len [u] . r body ) )
        ( bytes_extend_str out `\r\n` )
    } {}

    // ── Blank line + body ──
    ( bytes_extend_str out `\r\n` )
    // memcpy fast path — generic `vec_extend [u]` does a per-element
    // copy that's the dominant cost for large response bodies
    // (e.g. 330 KB base64 wasm payload). Replaced 2026-05-27 after
    // profiling nurlapi /build_wasm showed ~2.5 s of the 3 s total
    // wall-time was spent in this single byte-by-byte loop.
    ( bytes_extend_bytes out . r body )

    ^ out
}

// Case-insensitive header presence check. Direct *Header iteration —
// see http_request.nu's note re. the `vec_get [Header]` miscompile.
@ __has_header_ci ( Vec Header ) hs s name → b {
    : i n ( vec_len [Header] hs )
    : *Header hdata ( vec_data [Header] hs )
    : ~ i k 0
    ~ < k n {
        : Header h . hdata k
        ? ( __header_name_eq_ci . h name name ) { ^ T } {}
        = k + k 1
    }
    ^ F
}

// Case-insensitive ASCII compare between an owned String and a
// NUL-terminated raw `s`. Mirrors `__string_eq_ci` in http_request.nu;
// kept inline here so this module doesn't depend on http_request.
@ __header_name_eq_ci String name s raw → b {
    : i la ( string_len name )
    : i lb ( nurl_str_len raw )
    ? != la lb { ^ F } {}
    : ~ i k 0
    ~ < k la {
        : ~ i ca ( string_get name k )
        : ~ i cb ( nurl_str_get raw k )
        ? & >= ca 65 <= ca 90 { = ca + ca 32 } {}
        ? & >= cb 65 <= cb 90 { = cb + cb 32 } {}
        ? != ca cb { ^ F } {}
        = k + k 1
    }
    ^ T
}

// ── Status reason phrases (RFC 7231 §6) ──────────────────────────────

// Returned as a borrowed raw `s` — callers MUST NOT free. Covers the
// common 1xx/2xx/3xx/4xx/5xx codes; unknown codes get a generic
// "Unknown" placeholder so the wire bytes stay parseable.
@ status_reason i code → s {
    ? == code 100 { ^ `Continue` } {}
    ? == code 101 { ^ `Switching Protocols` } {}
    ? == code 200 { ^ `OK` } {}
    ? == code 201 { ^ `Created` } {}
    ? == code 202 { ^ `Accepted` } {}
    ? == code 204 { ^ `No Content` } {}
    ? == code 205 { ^ `Reset Content` } {}
    ? == code 206 { ^ `Partial Content` } {}
    ? == code 301 { ^ `Moved Permanently` } {}
    ? == code 302 { ^ `Found` } {}
    ? == code 303 { ^ `See Other` } {}
    ? == code 304 { ^ `Not Modified` } {}
    ? == code 307 { ^ `Temporary Redirect` } {}
    ? == code 308 { ^ `Permanent Redirect` } {}
    ? == code 400 { ^ `Bad Request` } {}
    ? == code 401 { ^ `Unauthorized` } {}
    ? == code 403 { ^ `Forbidden` } {}
    ? == code 404 { ^ `Not Found` } {}
    ? == code 405 { ^ `Method Not Allowed` } {}
    ? == code 406 { ^ `Not Acceptable` } {}
    ? == code 408 { ^ `Request Timeout` } {}
    ? == code 409 { ^ `Conflict` } {}
    ? == code 410 { ^ `Gone` } {}
    ? == code 411 { ^ `Length Required` } {}
    ? == code 413 { ^ `Payload Too Large` } {}
    ? == code 414 { ^ `URI Too Long` } {}
    ? == code 415 { ^ `Unsupported Media Type` } {}
    ? == code 418 { ^ `I'm a teapot` } {}
    ? == code 422 { ^ `Unprocessable Entity` } {}
    ? == code 429 { ^ `Too Many Requests` } {}
    ? == code 431 { ^ `Request Header Fields Too Large` } {}
    ? == code 500 { ^ `Internal Server Error` } {}
    ? == code 501 { ^ `Not Implemented` } {}
    ? == code 502 { ^ `Bad Gateway` } {}
    ? == code 503 { ^ `Service Unavailable` } {}
    ? == code 504 { ^ `Gateway Timeout` } {}
    ? == code 505 { ^ `HTTP Version Not Supported` } {}
    ^ `Unknown`
}

// ── Chunked streaming over a live TcpConn (Phase 3.3) ─────────────────
//
// These helpers are required for SSE / MCP HTTP transport. Layering:
//
//   ( response_begin_chunked conn 200 hs )
//     → emits the status line, every header in `hs`, and forces
//       `Transfer-Encoding: chunked\r\n\r\n` (regardless of what the
//       caller's headers contain). After this returns, the wire is in
//       chunk-frame state.
//   ( response_write_chunk conn bytes )*
//     → emits `<hex-len>\r\n<bytes>\r\n`. Empty `bytes` Vecs are
//       silently skipped — sending a zero-length chunk would terminate
//       the response prematurely.
//   ( response_end_chunked conn )
//     → emits the terminator `0\r\n\r\n`. After this, no further
//       `response_write_chunk` calls are valid on `conn` for THIS
//       response.

@ response_begin_chunked TcpConn c i status ( Vec Header ) hs → !v NetErr {
    : ( Vec u ) head ( vec_with_cap [u] 128 )
    ( bytes_extend_str head `HTTP/1.1 ` )
    ( bytes_push_int head status )
    ( bytes_extend_str head ` ` )
    ( bytes_extend_str head ( status_reason status ) )
    ( bytes_extend_str head `\r\n` )

    : i hcount ( vec_len [Header] hs )
    : *Header hdata ( vec_data [Header] hs )
    : ~ i k 0
    ~ < k hcount {
        : Header h . hdata k
        : s nm ( string_data . h name )
        // Suppress any caller-supplied Transfer-Encoding / Content-Length
        // — we always force chunked, never both.
        : b is_te != 0 ( nurl_str_eq nm `Transfer-Encoding` )
        : b is_cl != 0 ( nurl_str_eq nm `Content-Length` )
        ? & ! is_te ! is_cl {
            ( __push_header_no_crlf head nm )
            ( bytes_extend_str head `: ` )
            ( __push_header_no_crlf head ( string_data . h value ) )
            ( bytes_extend_str head `\r\n` )
        } {}
        = k + k 1
    }

    ( bytes_extend_str head `Transfer-Encoding: chunked\r\n\r\n` )
    : !v NetErr wr ( tcp_write_all c head )
    ( vec_free [u] head )
    ^ wr
}

@ response_write_chunk TcpConn c ( Vec u ) chunk → !v NetErr {
    : i n ( vec_len [u] chunk )
    ? <= n 0 { ^ @ !v NetErr { T 0 } } {}

    : ( Vec u ) frame ( vec_with_cap [u] + n 16 )
    ( __append_hex_size frame n )
    ( bytes_extend_str frame `\r\n` )
    ( vec_extend [u] frame chunk )
    ( bytes_extend_str frame `\r\n` )
    : !v NetErr wr ( tcp_write_all c frame )
    ( vec_free [u] frame )
    ^ wr
}

@ response_end_chunked TcpConn c → !v NetErr {
    ^ ( tcp_write_str c `0\r\n\r\n` )
}

// Format `n` (>=0) as lowercase hex without leading zeros and append
// onto `out`. Special-cases 0 → "0".
@ __append_hex_size ( Vec u ) out i n → v {
    ? <= n 0 {
        ( vec_push [u] out # u 48 )  // '0'
    } {
        // Walk MSB → LSB by extracting each nibble. 64-bit values fit in
        // 16 hex digits. `started` skips leading zero nibbles.
        : ~ b started F
        : ~ i shift 60
        ~ >= shift 0 {
            : i nib & 15 / n ( __pow2 shift )
            ? | started != nib 0 {
                = started T
                ? < nib 10 { ( vec_push [u] out # u + 48 nib ) } {
                    ( vec_push [u] out # u + 87 nib ) }
            } {}
            = shift - shift 4
        }
    }
}

// Cheap 2^n (n in [0..63]) — `<<` exists but spelling is `<` `<` here
// is wrong; use a multiplication-loop fallback. Only hit by hex
// formatting (≤16 iterations).
@ __pow2 i n → i {
    : ~ i v 1
    : ~ i k 0
    ~ < k n {
        = v * v 2
        = k + k 1
    }
    ^ v
}
