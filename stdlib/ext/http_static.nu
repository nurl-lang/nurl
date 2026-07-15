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
//   * Reads `req.path` and strips the leading '/' (request paths are
//     always absolute on the wire).
//   * Rejects any path containing a `..` segment with 403 Forbidden —
//     classic path-traversal defence (the alternative, resolving via
//     `realpath` and checking the prefix, would require a runtime call
//     and adds nothing for typical use).
//   * Joins `dir` and the cleaned path via `path_join`. If `dir` is
//     empty the request path is taken as-is (relative to CWD).
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
//   * No symlink containment check. If the configured `dir` contains
//     a symlink that points outside, the link is followed. Operators
//     who don't trust the directory layout should pre-resolve `dir`
//     and avoid mounting paths from untrusted sources.
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
        : ~ i a ( nurl_str_get ext k )
        : i b ( nurl_str_get lit k )
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
            : i c ( nurl_str_get path k )
            ? | == c 47 == c 92 { = at_sep T } {}
        }
        ? at_sep {
            : i seg_len - k seg_start
            ? == seg_len 2 {
                ? & == ( nurl_str_get path seg_start ) 46 == ( nurl_str_get path + seg_start 1 ) 46 {
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

// Build the relative request tail: strip ALL leading separators so the
// result can never be an absolute path. Stripping only ONE separator
// (the old behaviour) left "//etc/passwd" → "/etc/passwd", which
// path_join treats as an absolute `b` and returns verbatim — discarding
// `dir` and serving an arbitrary file outside the static root. Stripping
// every leading '/' and '\\' guarantees the tail is relative, so the
// path_join result always stays under `dir`. (A Windows drive-letter
// tail like "C:/.." survives separator-stripping and is rejected
// separately by serve_static's path_is_absolute guard.)
@ __static_rel_tail s path → String {
    : i pn ( nurl_str_len path )
    : ~ i start 0
    ~ & < start pn ( __is_sep_byte ( nurl_str_get path start ) ) {
        = start + start 1
    }
    : String out ( string_with_cap - pn start )
    : ~ i k start
    ~ < k pn {
        ( string_push_char out ( nurl_str_get path k ) )
        = k + k 1
    }
    ^ out
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
    // Resolve to a guaranteed-relative tail FIRST (strips every leading
    // separator), then run the traversal defences on that tail — so a
    // "//etc/passwd" or "/C:/secret" can never escape `dir`, even when
    // `dir` is empty.
    : String rel ( __static_rel_tail ( string_data . req path ) )
    : s rels ( string_data rel )
    // Reject any ".." segment, and reject a tail that is still absolute
    // after separator-stripping (a Windows drive-letter form, which
    // path_join would otherwise honour and serve outside `dir`).
    ? | ( _has_dotdot_segment rels ) ( path_is_absolute rels ) {
        ( string_free rel )
        ^ ( response_text 403 `forbidden\n` )
    } {}

    // Empty tail ("/" or all-separators) → directory index.
    : ~ String full ( path_join dir `index.html` )
    ? > ( string_len rel ) 0 {
        ( string_free full )
        = full ( path_join dir rels )
    } {}
    ( string_free rel )

    // Refuse to serve a directory entry directly (e.g. someone requested
    // `/static/css/`). file_exists returns F for directories under POSIX
    // semantics? No — it returns T. Use file_size instead: directories
    // produce IoErr; that doubles as a not-found check.
    : !i IoErr sz ( file_size ( string_data full ) )
    ?? sz {
        T _ → {}
        F _ → {
            ( string_free full )
            ^ ( response_text 404 `not found\n` )
        }
    }

    : !( Vec u ) IoErr rd ( read_file_bytes ( string_data full ) )
    ?? rd {
        T body → {
            : String ext ( path_extension ( string_data full ) )
            : s mime ( mime_for_ext ( string_data ext ) )
            ( string_free ext )
            ( string_free full )
            : HttpResponse r ( response_new 200 )
            ( response_set_header r `Content-Type` mime )
            ( response_set_body_bytes r body )
            ( vec_free [u] body )
            ^ r
        }
        F _ → {
            ( string_free full )
            ^ ( response_text 404 `not found\n` )
        }
    }
}
