// stdlib/ext/http_cli.nu — HTTP client backed by the system `curl` BINARY
//
// This is a deliberate, dependency-free alternative to ext/http.nu (which
// links libcurl). nurlpkg uses it so the package manager has ZERO
// third-party shared-library dependencies — it links only libc. The
// install one-liner already requires the `curl` executable
// (`curl -fsSL …/install.sh | sh`), so depending on the binary adds no
// new requirement, while NOT linking libcurl means nurlpkg can no longer
// be wedged by a missing libcurl/libssl/libcrypto on a fresh box.
//
// It exposes exactly the subset of ext/http.nu's surface that nurlpkg
// (ext/pkg_fetch.nu + ext/pkg_publish.nu) consumes, with identical type
// and function names so those modules import this instead of ext/http.nu
// with no other change. A file must NOT import both this module and
// ext/http.nu (the `HttpcResp` / `HttpcErr` names would collide in NURL's
// flat namespace) — nurlpkg's graph imports only this one.
//
// API (drop-in subset):
//   ( httpc_get          s url )                                  → !HttpcResp HttpcErr
//   ( httpc_request      s method s url s body s headers_blob )   → !HttpcResp HttpcErr
//   ( httpc_request_bytes s method s url ( Vec u ) body s headers_blob ) → !HttpcResp HttpcErr
//   ( httpc_status       HttpcResp r )                             → i
//   ( httpc_body_str     HttpcResp r )                             → s   borrowed, NUL-terminated
//   ( httpc_body_bytes   HttpcResp r )                             → ( Vec u )  owned copy
//   ( httpc_resp_free     HttpcResp r )                             → v
//
// Transport: each request shells out to `curl`. The response BODY is
// captured to a temp file via `-o` (so binary tarballs round-trip intact
// — capturing through a pipe would truncate at the first NUL), and the
// HTTP status is read from stdout via `-w %{http_code}`. A request body
// (publish tarball) is written to a temp file and sent with
// `--data-binary @file` so its embedded NULs survive too.
//
// headers_blob format matches ext/http.nu: "Name: Value\r\n" segments
// concatenated; each becomes one curl `-H` argument.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/process.nu`
$ `stdlib/ext/env.nu`

// HttpcErr tags — mirror ext/http.nu so callers' match arms are identical.
: | HttpcErr { HttpcConnect HttpcTimeout HttpcTls HttpcDns HttpcInvalidUrl HttpcOther }

// HttpcResp carries the status, the true body length `blen`, and the body
// bytes with one extra trailing NUL (so httpc_body_str can hand back a
// NUL-terminated `s` view). The wrapper owns `body`; callers MUST call
// `httpc_resp_free` exactly once on the Ok path (NURL does not auto-drop
// struct fields), matching ext/http.nu's manual ownership model.
: HttpcResp { i status i blen ( Vec u ) body }

// ── Temp directory ──────────────────────────────────────────────────
// $TMPDIR if set and non-empty, else /tmp.
@ __httpc_tmpdir → String {
    ?? ( env_get `TMPDIR` ) {
        T d → {
            ? > ( string_len d ) 0 { ^ d } {}
            ( string_free d )
            ^ ( string_from `/tmp` )
        }
        F _ → ^ ( string_from `/tmp` )
    }
}

// Copy bytes [a, b) of `str` into a fresh owned String.
@ __httpc_substr s str i a i b → String {
    : String out ( string_with_cap + - b a 1 )
    : ~ i k a
    ~ < k b {
        ( string_push_char out ( nurl_str_get str k ) )
        = k + k 1
    }
    ^ out
}

// Split a "Name: Value\r\n"… headers blob into `-H <segment>` argument
// pairs. Each segment is a fresh owned String pushed onto `hold` (which
// the caller frees after the spawn) and its data pointer onto `a`.
@ __httpc_push_headers s blob ( Vec s ) a ( Vec String ) hold → v {
    : i n ( nurl_str_len blob )
    : ~ i start 0
    : ~ i i 0
    ~ < i n {
        ? & == ( nurl_str_get blob i ) 13 & < + i 1 n == ( nurl_str_get blob + i 1 ) 10 {
            ? > i start {
                : String seg ( __httpc_substr blob start i )
                ( vec_push [s] a `-H` )
                ( vec_push [s] a ( string_data seg ) )
                ( vec_push [String] hold seg )
            } {}
            = i + i 2
            = start i
        } {
            = i + i 1
        }
    }
    // Trailing segment with no closing CRLF.
    ? > n start {
        : String seg ( __httpc_substr blob start n )
        ( vec_push [s] a `-H` )
        ( vec_push [s] a ( string_data seg ) )
        ( vec_push [String] hold seg )
    } {}
}

// ── Core: run one curl request ──────────────────────────────────────
// `reqfile` is "" for no body, else a path whose contents are POSTed
// with --data-binary. Returns the parsed HttpcResp or a transport error.
@ __httpc_exec s method s url s reqfile s headers_blob → !HttpcResp HttpcErr {
    : String tdir ( __httpc_tmpdir )
    : !String IoErr rf ( fs_tempfile ( string_data tdir ) `nurlpkg-resp-` )
    ( string_free tdir )
    ?? rf {
        F _ → ^ @ !HttpcResp HttpcErr { F # HttpcErr HttpcOther }
        T respfile → {
            : ( Vec s ) a ( vec_new [s] )
            : ( Vec String ) hold ( vec_new [String] )
            ( vec_push [s] a `-s` )
            ( vec_push [s] a `-S` )
            ( vec_push [s] a `-L` )
            ( vec_push [s] a `--connect-timeout` )
            ( vec_push [s] a `10` )
            ( vec_push [s] a `--max-time` )
            ( vec_push [s] a `300` )
            ( vec_push [s] a `-o` )
            ( vec_push [s] a ( string_data respfile ) )
            ( vec_push [s] a `-w` )
            ( vec_push [s] a `%{http_code}` )
            ( vec_push [s] a `-X` )
            ( vec_push [s] a method )
            ( __httpc_push_headers headers_blob a hold )

            // Body: --data-binary @<reqfile>. The "@path" arg must outlive
            // the spawn, so park it in `atarg`.
            : ~ String atarg ( string_new )
            ? > ( nurl_str_len reqfile ) 0 {
                ( vec_push [s] a `--data-binary` )
                ( string_free atarg )
                = atarg ( string_with_cap + ( nurl_str_len reqfile ) 2 )
                ( string_push_char atarg 64 )  // '@'
                ( string_push_str atarg reqfile )
                ( vec_push [s] a ( string_data atarg ) )
            } {}
            ( vec_push [s] a url )

            : ~ i status 0
            : ~ i ok 0
            : ~ i ec 0
            ?? ( process_run `curl` a `` ) {
                F _ → { = ec -1 }
                T out → {
                    = ec ( output_exit_code out )
                    ? == ec 0 {
                        = ok 1
                        = status ( nurl_str_to_int ( output_stdout out ) )
                    } {}
                    ( output_free out )
                }
            }
            ( vec_free [s] a )
            ( string_free atarg )
            ( vec_free_with [String] hold \ String hs → v { ( string_free hs ) } )

            ? == ok 0 {
                ( unlink ( string_data respfile ) )
                ( string_free respfile )
                ? == ec 6 { ^ @ !HttpcResp HttpcErr { F # HttpcErr HttpcDns } } {}
                ? == ec 7 { ^ @ !HttpcResp HttpcErr { F # HttpcErr HttpcConnect } } {}
                ? == ec 28 { ^ @ !HttpcResp HttpcErr { F # HttpcErr HttpcTimeout } } {}
                ? | == ec 35 == ec 60 { ^ @ !HttpcResp HttpcErr { F # HttpcErr HttpcTls } } {}
                ^ @ !HttpcResp HttpcErr { F # HttpcErr HttpcOther }
            } {}

            // Read the captured body, append a NUL for httpc_body_str.
            : ~ ( Vec u ) body ( vec_new [u] )
            : ~ i blen 0
            ?? ( read_file_bytes ( string_data respfile ) ) {
                T b → {
                    = blen ( vec_len [u] b )
                    ( vec_free [u] body )
                    = body b
                }
                F _ → {}
            }
            ( vec_push [u] body 0 )
            ( unlink ( string_data respfile ) )
            ( string_free respfile )

            : HttpcResp r @ HttpcResp { status blen body }
            ^ @ !HttpcResp HttpcErr { T r }
        }
    }
}

// Write `body` to a temp file, run the request, then unlink the temp.
@ __httpc_with_body s method s url ( Vec u ) body s headers_blob → !HttpcResp HttpcErr {
    : String tdir ( __httpc_tmpdir )
    : !String IoErr bf ( fs_tempfile ( string_data tdir ) `nurlpkg-body-` )
    ( string_free tdir )
    ?? bf {
        F _ → ^ @ !HttpcResp HttpcErr { F # HttpcErr HttpcOther }
        T bodyfile → {
            : ~ i wok 1
            ?? ( write_file_bytes ( string_data bodyfile ) body ) {
                F _ → { = wok 0 }
                T _ → {}
            }
            ? == wok 0 {
                ( unlink ( string_data bodyfile ) )
                ( string_free bodyfile )
                ^ @ !HttpcResp HttpcErr { F # HttpcErr HttpcOther }
            } {}
            : !HttpcResp HttpcErr res ( __httpc_exec method url ( string_data bodyfile ) headers_blob )
            ( unlink ( string_data bodyfile ) )
            ( string_free bodyfile )
            ^ res
        }
    }
}

// ── Public API ──────────────────────────────────────────────────────

@ httpc_get s url → !HttpcResp HttpcErr {
    ^ ( __httpc_exec `GET` url `` `` )
}

@ httpc_request s method s url s body s headers_blob → !HttpcResp HttpcErr {
    ? == ( nurl_str_len body ) 0 {
        ^ ( __httpc_exec method url `` headers_blob )
    } {}
    // Non-empty text body: stage it through a temp file so the byte path
    // and the text path are identical on the wire.
    : String tdir ( __httpc_tmpdir )
    : !String IoErr bf ( fs_tempfile ( string_data tdir ) `nurlpkg-body-` )
    ( string_free tdir )
    ?? bf {
        F _ → ^ @ !HttpcResp HttpcErr { F # HttpcErr HttpcOther }
        T bodyfile → {
            : ~ i wok 1
            ?? ( write_file ( string_data bodyfile ) body ) {
                F _ → { = wok 0 }
                T _ → {}
            }
            ? == wok 0 {
                ( unlink ( string_data bodyfile ) )
                ( string_free bodyfile )
                ^ @ !HttpcResp HttpcErr { F # HttpcErr HttpcOther }
            } {}
            : !HttpcResp HttpcErr res ( __httpc_exec method url ( string_data bodyfile ) headers_blob )
            ( unlink ( string_data bodyfile ) )
            ( string_free bodyfile )
            ^ res
        }
    }
}

@ httpc_request_bytes s method s url ( Vec u ) body s headers_blob → !HttpcResp HttpcErr {
    ^ ( __httpc_with_body method url body headers_blob )
}

// ── Accessors (mirror ext/http.nu) ──────────────────────────────────

@ httpc_status HttpcResp r → i {
    ^ . r status
}

// Borrowed, NUL-terminated view of the body. Used by text callers
// (registry index / search JSON); copy it (e.g. string_from) before the
// matching httpc_resp_free.
@ httpc_body_str HttpcResp r → s {
    ^ # s ( vec_data [u] . r body )
}

// Owned, length-accurate copy of the body (excludes the trailing NUL).
// Preserves embedded NULs — required for binary downloads (tarballs).
// Caller frees with ( vec_free [u] … ).
@ httpc_body_bytes HttpcResp r → ( Vec u ) {
    : i blen . r blen
    : ( Vec u ) out ( vec_with_cap [u] ? > blen 0 blen 1 )
    : *u src ( vec_data [u] . r body )
    : ~ i k 0
    ~ < k blen {
        ( vec_push [u] out . src k )
        = k + k 1
    }
    ^ out
}

@ httpc_resp_free HttpcResp r → v {
    ( vec_free [u] . r body )
}
