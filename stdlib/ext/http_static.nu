// stdlib/ext/http_static.nu — HTTP server Phase 7 conveniences:
// MIME-type lookup + static-file serving on top of `http_response.nu`
// + `std/fs.nu`. Pure NURL — no runtime/compiler additions.
//
// Two layers:
//
//   ( mime_for_ext s ext )                 → s            BORROWED literal
//   ( serve_static s dir HttpRequest req ) → HttpResponse OWNED
//
// `mime_for_ext` looks up a Content-Type for a filename extension. The
// argument is the raw extension (no leading '.'); the return value is a
// pointer to a static literal so the caller does NOT free it. Unknown
// extensions resolve to `application/octet-stream` (the safe default
// per RFC 7231 §3.1.1.5).
//
// `serve_static` is the canonical static-file handler:
//
//   * Percent-decodes `req.path` (RFC 3986 §2.1 — "%20" is a space,
//     "%2e%2e" is ".."; '+' stays '+', it is only special in a query)
//     and strips every leading separator. A malformed escape or a NUL
//     byte → 400 Bad Request.
//   * Rejects a decoded path with a `..` segment or a drive letter
//     (`path_rel_ok`) with 403 Forbidden, and answers 404 for any
//     segment that starts with '.' — ".git", ".env", ".htpasswd" are
//     never content — except ".well-known" (RFC 8615).
//   * Joins `dir` and the cleaned path via `path_join`. If `dir` is
//     empty the request path is taken as-is (relative to CWD).
//   * Requires the file, with every symlink resolved, to lie inside
//     `dir` with every symlink resolved (`path_within`): a link in the
//     served tree that points at /etc is a 404, not a way out.
//   * Reads the file via `read_file_bytes` — missing / unreadable →
//     404 Not Found.
//   * Detects the extension via `path_extension` and sets
//     `Content-Type` from `mime_for_ext`.
//   * Sets the body from the OWNED file bytes (the bytes Vec is moved
//     into the response — no extra copy).
//
// Limitations (deferred to Phase 8 hardening):
//
//   * No conditional GET (If-Modified-Since / ETag).
//   * No Range support — the whole file is served in one body.
//   * Files are read fully into memory before sending. Phase 8 adds a
//     chunked-streaming variant for large files.

$ `stdlib/ext/http_request.nu`
$ `stdlib/ext/http_response.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/path.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

// ── mime_for_ext ─────────────────────────────────────────────────────
//
// Caller passes the extension WITHOUT a leading dot, in any case. The
// matcher folds to lowercase. Result is a borrowed `s` literal — the
// caller never frees it.

@ __ext_eq_ci s ext s lit → b {
    : i n ( nurl_str_len ext )
    : i m ( nurl_str_len lit )
    ? != n m { ^ F } {}
    : ~ i k 0
    ~ < k n {
        : ~ i a ( nurl_str_at ext n k )
        : i b ( nurl_str_at lit m k )
        ? & >= a 65 <= a 90 { = a + a 32 } {}
        ? != a b { ^ F } {}
        = k + k 1
    }
    ^ T
}

@ mime_for_ext s ext → s {
    : i n ( nurl_str_len ext )
    ? == n 0 { ^ `application/octet-stream` } {}
    // Text formats
    ? ( __ext_eq_ci ext `html` ) { ^ `text/html; charset=utf-8` } {}
    ? ( __ext_eq_ci ext `htm` ) { ^ `text/html; charset=utf-8` } {}
    ? ( __ext_eq_ci ext `css` ) { ^ `text/css; charset=utf-8` } {}
    ? ( __ext_eq_ci ext `js` ) { ^ `application/javascript; charset=utf-8` } {}
    ? ( __ext_eq_ci ext `mjs` ) { ^ `application/javascript; charset=utf-8` } {}
    ? ( __ext_eq_ci ext `json` ) { ^ `application/json; charset=utf-8` } {}
    ? ( __ext_eq_ci ext `xml` ) { ^ `application/xml; charset=utf-8` } {}
    ? ( __ext_eq_ci ext `txt` ) { ^ `text/plain; charset=utf-8` } {}
    ? ( __ext_eq_ci ext `md` ) { ^ `text/markdown; charset=utf-8` } {}
    ? ( __ext_eq_ci ext `csv` ) { ^ `text/csv; charset=utf-8` } {}
    // Images
    ? ( __ext_eq_ci ext `png` ) { ^ `image/png` } {}
    ? ( __ext_eq_ci ext `jpg` ) { ^ `image/jpeg` } {}
    ? ( __ext_eq_ci ext `jpeg` ) { ^ `image/jpeg` } {}
    ? ( __ext_eq_ci ext `gif` ) { ^ `image/gif` } {}
    ? ( __ext_eq_ci ext `svg` ) { ^ `image/svg+xml` } {}
    ? ( __ext_eq_ci ext `ico` ) { ^ `image/x-icon` } {}
    ? ( __ext_eq_ci ext `webp` ) { ^ `image/webp` } {}
    ? ( __ext_eq_ci ext `bmp` ) { ^ `image/bmp` } {}
    // Fonts
    ? ( __ext_eq_ci ext `woff` ) { ^ `font/woff` } {}
    ? ( __ext_eq_ci ext `woff2` ) { ^ `font/woff2` } {}
    ? ( __ext_eq_ci ext `ttf` ) { ^ `font/ttf` } {}
    ? ( __ext_eq_ci ext `otf` ) { ^ `font/otf` } {}
    // Audio / video
    ? ( __ext_eq_ci ext `mp3` ) { ^ `audio/mpeg` } {}
    ? ( __ext_eq_ci ext `wav` ) { ^ `audio/wav` } {}
    ? ( __ext_eq_ci ext `ogg` ) { ^ `audio/ogg` } {}
    ? ( __ext_eq_ci ext `mp4` ) { ^ `video/mp4` } {}
    ? ( __ext_eq_ci ext `webm` ) { ^ `video/webm` } {}
    // Documents / archives
    ? ( __ext_eq_ci ext `pdf` ) { ^ `application/pdf` } {}
    ? ( __ext_eq_ci ext `zip` ) { ^ `application/zip` } {}
    ? ( __ext_eq_ci ext `gz` ) { ^ `application/gzip` } {}
    ? ( __ext_eq_ci ext `wasm` ) { ^ `application/wasm` } {}
    ^ `application/octet-stream`
}

// ── Path-traversal check ──────────────────────────────────────────────
//
// Walks `path` segment-by-segment (split on '/' or '\\') and rejects
// the path if any segment is exactly "..". Empty segments and "." are
// allowed (collapsed to nothing, which `path_normalize` would also do).
// Operates on raw bytes — no allocation. Fast path for the common case.

@ _has_dotdot_segment s path → b {
    : i n ( nurl_str_len path )
    : ~ i seg_start 0
    : ~ i k 0
    : ~ b found F
    ~ & ! found <= k n {
        : ~ b at_sep F
        ? == k n { = at_sep T } {
            : i c ( nurl_str_at path n k )
            ? | == c 47 == c 92 { = at_sep T } {}
        }
        ? at_sep {
            : i seg_len - k seg_start
            ? == seg_len 2 {
                ? & == ( nurl_str_at path n seg_start ) 46 == ( nurl_str_at path n + seg_start 1 ) 46 {
                    = found T
                } {}
            } {}
            = seg_start + k 1
        } {}
        = k + k 1
    }
    ^ found
}

@ __is_sep_byte i c → b {
    ? == c 47 { ^ T } {}
    ? == c 92 { ^ T } {}
    ^ F
}

// Decode the request path into a guaranteed-relative tail: resolve
// every %XX escape, then drop ALL leading separators so the result can
// never be an absolute path. Stripping only ONE separator (the old
// behaviour) left "//etc/passwd" → "/etc/passwd", which path_join treats
// as an absolute `b` and returns verbatim — discarding `dir`. Decoding
// comes first because the filesystem sees the decoded bytes: checking
// "%2e%2e" and then opening ".." is the classic way past a traversal
// guard. `ok` is F for a malformed escape or a NUL anywhere (the
// filesystem would stop at the NUL and open a different name than the
// one checked). A drive-letter tail like "C:/.." survives
// separator-stripping and is rejected by serve_static's path_rel_ok.
: StaticTail {
    String rel
    b ok
}

@ __static_hex i c → i {
    ? & >= c 48 <= c 57 { ^ - c 48 } {}
    ? & >= c 65 <= c 70 { ^ - c 55 } {}
    ? & >= c 97 <= c 102 { ^ - c 87 } {}
    ^ -1
}

@ __static_rel_tail s path → StaticTail {
    : i pn ( nurl_str_len path )
    : String out ( string_with_cap pn )
    : ~ b ok T
    : ~ i k 0
    ~ & ok < k pn {
        : ~ i c ( nurl_str_at path pn k )
        ? == c 37 {
            ? <= + k 2 - pn 1 {
                : i hi ( __static_hex ( nurl_str_at path pn + k 1 ) )
                : i lo ( __static_hex ( nurl_str_at path pn + k 2 ) )
                ? & >= hi 0 >= lo 0 { = c + * hi 16 lo = k + k 2 } { = ok F }
            } { = ok F }
        } {}
        ? == c 0 { = ok F } {}
        // Leading separators — raw or decoded — never reach `out`.
        ? | > ( string_len out ) 0 ! ( __is_sep_byte c ) { ( string_push_char out c ) } {}
        = k + k 1
    }
    ^ @ StaticTail { out ok }
}

// Some segment starts with '.', other than a leading ".well-known".
// '.' and '..' segments are caught here too, but ".." is decided first
// (403) by path_rel_ok; this one answers 404 so a probe cannot tell a
// hidden file from a missing one.
@ __static_hidden s rel → b {
    : i n ( nurl_str_len rel )
    : ~ i k 0
    ~ < k n {
        // k is the start of a segment.
        ? == ( nurl_str_at rel n k ) 46 {
            : ~ b wk F
            ? == k 0 {
                ? >= n 11 {
                    ? == 0 # i ( strncmp rel `.well-known` 11 ) {
                        ? == n 11 { = wk T } { = wk ( __is_sep_byte ( nurl_str_at rel n 11 ) ) }
                    } {}
                } {}
            } {}
            ? ! wk { ^ T } {}
        } {}
        ~ & < k n ! ( __is_sep_byte ( nurl_str_at rel n k ) ) { = k + k 1 }
        = k + k 1
    }
    ^ F
}

// ── serve_static ─────────────────────────────────────────────────────
//
// Path resolution:
//
//   * Strip ALL leading separators from the request path to obtain a
//     guaranteed-relative tail (see __static_rel_tail).
//   * Empty tail ("/" or all-separators) → serve `dir/index.html`.
//   * Reject (403) any '..' segment, or a tail that is still absolute
//     (a drive-letter form like "C:/..") after separator-stripping.
//   * Join the tail with `dir` (empty `dir` means CWD-relative) and read
//     the file; read_file_bytes / file_size failure → 404.
//
// The body Vec is OWNED by the response after `response_set_body_bytes`
// copies it; we then free the original buffer to avoid double ownership.

@ serve_static s dir HttpRequest req → HttpResponse {
    // Decode to a guaranteed-relative tail FIRST (every escape resolved,
    // every leading separator stripped), then run the traversal defences
    // on exactly the bytes the filesystem will see.
    : StaticTail tail ( __static_rel_tail ( string_data . req path ) )
    ? ! . tail ok { ^ ( response_text 400 `bad request\n` ) } {}
    : s rels ( string_data . tail rel )
    ? ! ( path_rel_ok rels ) { ^ ( response_text 403 `forbidden\n` ) } {}
    ? ( __static_hidden rels ) { ^ ( response_text 404 `not found\n` ) } {}

    // Empty tail ("/" or all-separators) → directory index.
    : ~ String full ( path_join dir `index.html` )
    ? > ( string_len . tail rel ) 0 {
        = full ( path_join dir rels )
    } {}

    // The lexical checks above keep the NAME under `dir`; a symlink in
    // the served tree can still lead out. Resolve both and compare. An
    // empty `dir` is the working directory.
    : ~ s root dir
    ? == 0 ( nurl_str_len dir ) { = root `.` } {}
    ? ! ( path_within root ( string_data full ) ) {
        ^ ( response_text 404 `not found\n` )
    } {}

    // Refuse to serve a directory entry directly (e.g. someone requested
    // `/static/css/`). file_exists returns F for directories under POSIX
    // semantics? No — it returns T. Use file_size instead: directories
    // produce IoErr; that doubles as a not-found check.
    : !i IoErr sz ( file_size ( string_data full ) )
    ?? sz {
        T _ → {}
        F _ → {
            ^ ( response_text 404 `not found\n` )
        }
    }

    : !( Vec u ) IoErr rd ( read_file_bytes ( string_data full ) )
    ?? rd {
        T body → {
            : String ext ( path_extension ( string_data full ) )
            : s mime ( mime_for_ext ( string_data ext ) )
            : HttpResponse r ( response_new 200 )
            ( response_set_header r `Content-Type` mime )
            ( response_set_body_bytes r body )
            ^ r
        }
        F _ → {
            ^ ( response_text 404 `not found\n` )
        }
    }
}
