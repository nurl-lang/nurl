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
// with no other change (ext/http.nu defines none of these names, so the
// two can be imported together); nurlpkg's graph imports only this one.
//
// API (drop-in subset):
//   ( httpc_get          s url )                                  → !HttpcResp HttpcErr
//   ( httpc_request      s method s url s body s headers_blob )   → !HttpcResp HttpcErr
//   ( httpc_redirect_location s url )                             → ?String  a redirect's Location, unfollowed
//   ( httpc_request_bytes s method s url ( Vec u ) body s headers_blob ) → !HttpcResp HttpcErr
//   ( httpc_status       HttpcResp r )                             → i
//   ( httpc_body_str     HttpcResp r )                             → s   borrowed, NUL-terminated
//   ( httpc_body_bytes   HttpcResp r )                             → ( Vec u )  owned copy
//   ( httpc_resp_free     HttpcResp r )                             → v   early release (optional)
//
// Transport: each request shells out to `curl`. The response BODY is
// captured to a temp file via `-o` (so binary tarballs round-trip intact
// — capturing through a pipe would truncate at the first NUL), and the
// HTTP status is read from stdout via `-w %{http_code}`. A request body
// (publish tarball) is written to a temp file and sent with
// `--data-binary @file` so its embedded NULs survive too.
//
// headers_blob format matches ext/http.nu: "Name: Value\r\n" segments
// concatenated. Non-secret headers become curl `-H` arguments; secret-bearing
// headers (Authorization, Cookie, Set-Cookie, Proxy-Authorization, X-Api-Key,
// X-Auth-Token, and any header whose name carries auth/token/secret/cookie/
// password/credential/key) are never placed in argv or on disk — they are
// piped to curl on stdin via `-K -`.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/process.nu`
$ `stdlib/ext/env.nu`
$ `stdlib/ext/http_cli_types.nu`
$ `stdlib/core/slice.nu`

// HttpcResp carries the status, the true body length `blen`, and the body
// bytes with one extra trailing NUL (so httpc_body_str can hand back a
// NUL-terminated `s` view). The wrapper owns `body` and is dropped with
// it by its owner (`httpc_resp_free` releases it early).
// The shared declaration lives in http_cli_types.nu.

// ── Temp directory ──────────────────────────────────────────────────
// Response files are staged in env_temp_dir (stdlib/ext/env.nu): the
// platform's own temp directory. A TMPDIR-or-/tmp guess once made every
// request on Windows die staging its response file, before curl was even
// spawned, and nurlpkg then reported the silence as "package not found in
// the registry".

// Copy bytes [a, b) of `str` into a fresh owned String.
@ __httpc_substr s str i a i b → String {
    : ( Slice u ) str_v ( slice_of_str str )
    : String out ( string_with_cap + - b a 1 )
    : ~ i k a
    ~ < k b {
        ( string_push_char out ( slice_byte str_v k ) )
        = k + k 1
    }
    ^ out
}

@ __httpc_ascii_lower i c → i {
    ? & >= c 65 <= c 90 { ^ + c 32 } {}
    ^ c
}

// Case-insensitive substring check over `str[start..end)` against lowercase `needle`.
@ __httpc_range_contains_ci s str i n i start i end s needle → b {
    : i m ( nurl_str_len needle )
    ? <= m 0 { ^ T } {}
    ? < - end start m { ^ F } {}
    : ~ i pos start
    : i limit - end m
    ~ <= pos limit {
        : ~ i j 0
        : ~ b ok T
        ~ & < j m ok {
            : i c1 ( __httpc_ascii_lower ( nurl_str_at str n + pos j ) )
            : i c2 ( nurl_str_at needle m j )
            ? != c1 c2 { = ok F } {}
            = j + j 1
        }
        ? ok { ^ T } {}
        = pos + pos 1
    }
    ^ F
}

// Central classifier for secret-bearing HTTP header lines ("Name: Value").
// Any header whose field name matches an authentication, cookie, token, key,
// secret, password or credential pattern (or a malformed line with no ':')
// is classified as secret so it is never placed in process argv or logs.
@ httpc_is_secret_header s seg → b {
    : i n ( nurl_str_len seg )
    : ~ i colon -1
    : ~ i i 0
    ~ & < i n < colon 0 {
        ? == ( nurl_str_at seg n i ) 58 { = colon i } {}
        = i + i 1
    }
    ? < colon 0 { ^ T } {}
    : ~ i a 0
    ~ & < a colon | == ( nurl_str_at seg n a ) 32 == ( nurl_str_at seg n a ) 9 {
        = a + a 1
    }
    : ~ i b colon
    ~ & > b a | == ( nurl_str_at seg n - b 1 ) 32 == ( nurl_str_at seg n - b 1 ) 9 {
        = b - b 1
    }
    ? <= b a { ^ T } {}
    ? ( __httpc_range_contains_ci seg n a b `auth` ) { ^ T } {}
    ? ( __httpc_range_contains_ci seg n a b `token` ) { ^ T } {}
    ? ( __httpc_range_contains_ci seg n a b `cookie` ) { ^ T } {}
    ? ( __httpc_range_contains_ci seg n a b `secret` ) { ^ T } {}
    ? ( __httpc_range_contains_ci seg n a b `password` ) { ^ T } {}
    ? ( __httpc_range_contains_ci seg n a b `credential` ) { ^ T } {}
    ? ( __httpc_range_contains_ci seg n a b `api-key` ) { ^ T } {}
    ? ( __httpc_range_contains_ci seg n a b `apikey` ) { ^ T } {}
    ^ F
}

// Redact secret-bearing header values in a "Name: Value\r\n" headers blob
// for safe diagnostics/logging. Non-secret headers are preserved verbatim;
// secret headers become "Name: <redacted>\r\n".
@ __httpc_redact_segment String out s seg → v {
    ? ! ( httpc_is_secret_header seg ) {
        ( string_push_str out seg )
        ( string_push_str out `\r\n` )
        ^
    } {}
    : i n ( nurl_str_len seg )
    : ~ i colon -1
    : ~ i i 0
    ~ & < i n < colon 0 {
        ? == ( nurl_str_at seg n i ) 58 { = colon i } {}
        = i + i 1
    }
    ? < colon 0 {
        ( string_push_str out `<redacted>\r\n` )
        ^
    } {}
    : String name ( __httpc_substr seg 0 + colon 1 )
    ( string_push_str out ( string_data name ) )
    ( string_push_str out ` <redacted>\r\n` )
}

@ httpc_redact_headers s blob → String {
    : i n ( nurl_str_len blob )
    : String out ( string_with_cap + n 16 )
    : ~ i start 0
    : ~ i i 0
    ~ < i n {
        ? & == ( nurl_str_at blob n i ) 13 & < + i 1 n == ( nurl_str_at blob n + i 1 ) 10 {
            ? > i start {
                : String seg ( __httpc_substr blob start i )
                ( __httpc_redact_segment out ( string_data seg ) )
            } {}
            = i + i 2
            = start i
        } {
            = i + i 1
        }
    }
    ? > n start {
        : String seg ( __httpc_substr blob start n )
        ( __httpc_redact_segment out ( string_data seg ) )
    } {}
    ^ out
}

// Append a `header = "..."` directive for curl `-K -` stdin config, escaping
// `\` and `"` and stripping any CR/LF bytes so a header value cannot break
// out of the quoted config line.
@ __httpc_append_cfg_header String cfg s seg → v {
    : i n ( nurl_str_len seg )
    ( string_push_str cfg `header = "` )
    : ~ i k 0
    ~ < k n {
        : i c ( nurl_str_at seg n k )
        ? | == c 10 == c 13 {} {
            ? | == c 34 == c 92 {
                ( string_push_char cfg 92 )
            } {}
            ( string_push_char cfg c )
        }
        = k + k 1
    }
    ( string_push_str cfg `"\n` )
}

@ __httpc_handle_header_seg String seg ( Vec s ) a ( Vec String ) hold String stdin_cfg → v {
    ? ( httpc_is_secret_header ( string_data seg ) ) {
        ( __httpc_append_cfg_header stdin_cfg ( string_data seg ) )
        ^
    } {}
    ( vec_push [s] a `-H` )
    ( vec_push [s] a ( string_data seg ) )
    ( vec_push [String] hold seg )
}

// Split a "Name: Value\r\n"… headers blob: non-secret segments become
// `-H <segment>` argument pairs on `a` (kept alive in `hold`); secret-bearing
// segments are written to `stdin_cfg` and fed to curl via `-K -` on stdin so
// they never appear in process argv or temporary files.
@ __httpc_push_headers s blob ( Vec s ) a ( Vec String ) hold String stdin_cfg → v {
    : i n ( nurl_str_len blob )
    : ~ i start 0
    : ~ i i 0
    ~ < i n {
        ? & == ( nurl_str_at blob n i ) 13 & < + i 1 n == ( nurl_str_at blob n + i 1 ) 10 {
            ? > i start {
                : String seg ( __httpc_substr blob start i )
                ( __httpc_handle_header_seg seg a hold stdin_cfg )
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
        ( __httpc_handle_header_seg seg a hold stdin_cfg )
    } {}
    ? > ( string_len stdin_cfg ) 0 {
        ( vec_push [s] a `-K` )
        ( vec_push [s] a `-` )
    } {}
}

// The default wall-clock cap on one request, in seconds. A caller that must
// not block that long (an interactive server calling out to a build service,
// say) passes its own with the *_timeout entry points.
@ httpc_default_max_time → i { ^ 300 }

// ── Core: run one curl request ──────────────────────────────────────
// `reqfile` is "" for no body, else a path whose contents are POSTed
// with --data-binary. `max_secs` caps the whole exchange. Returns the parsed
// HttpcResp or a transport error.
@ __httpc_exec s method s url s reqfile s headers_blob → !HttpcResp HttpcErr {
    ^ ( __httpc_exec_t method url reqfile headers_blob ( httpc_default_max_time ) 0 )
}

// Is `url` an http:// or https:// URL (scheme case-insensitive)? Anything
// else is refused before curl is run: a value starting with `-` would be
// one of curl's options (a manifest's `registry`), and curl speaks file://,
// gopher://, dict://, ldap://, scp://… as well (agora #166).
@ httpc_url_is_http s url → b {
    : i n ( nurl_str_len url )
    : ~ i k 0
    : ~ b ok T
    // "http" then an optional 's', then "://".
    : s http `http`
    ~ & < k 4 ok {
        ? | >= k n != ( __httpc_ascii_lower ( nurl_str_at url n k ) ) ( nurl_str_at http 4 k ) { = ok F } {}
        = k + k 1
    }
    ? ! ok { ^ F } {}
    ? & < k n == ( __httpc_ascii_lower ( nurl_str_at url n k ) ) 115 { = k + k 1 } {}
    ? > + k 3 n { ^ F } {}
    ^ & & == ( nurl_str_at url n k ) 58 == ( nurl_str_at url n + k 1 ) 47 == ( nurl_str_at url n + k 2 ) 47
}

// `max_bytes` > 0 caps the response body: curl stops past it
// (--max-filesize, exit 63), and a body that still arrives larger is
// refused before it is read into memory (agora #163). 0 = no cap.
@ __httpc_exec_t s method s url s reqfile s headers_blob i max_secs i max_bytes → !HttpcResp HttpcErr {
    ? ! ( httpc_url_is_http url ) { ^ @ !HttpcResp HttpcErr { F # HttpcErr HttpcOther } } {}
    : String tdir ( env_temp_dir )
    : !String IoErr rf ( fs_tempfile ( string_data tdir ) `nurlpkg-resp-` )
    ?? rf {
        F _ → ^ @ !HttpcResp HttpcErr { F # HttpcErr HttpcOther }
        T respfile → {
            : ( Vec s ) a ( vec_new [s] )
            : ( Vec String ) hold ( vec_new [String] )
            ( vec_push [s] a `-s` )
            ( vec_push [s] a `-S` )
            ( vec_push [s] a `-L` )
            // HTTP(S) only, redirects too, and no URL globbing (`[]` `{}`).
            ( vec_push [s] a `-g` )
            ( vec_push [s] a `--proto` )
            ( vec_push [s] a `=http,https` )
            ( vec_push [s] a `--proto-redir` )
            ( vec_push [s] a `=http,https` )
            ( vec_push [s] a `--connect-timeout` )
            ( vec_push [s] a `10` )
            ( vec_push [s] a `--max-time` )
            : String mts ( string_from ( nurl_str_int ? > max_secs 0 max_secs ( httpc_default_max_time ) ) )
            ( vec_push [s] a ( string_data mts ) )
            ( vec_push [String] hold mts )
            // Stall detection. --max-time alone is a poor deadline: a
            // connection that dies mid-transfer sat here for the full 300 s
            // before reporting anything, which reads as "nurlpkg hung". Abort
            // once the transfer has moved < 1 byte/s for 30 s — a genuinely
            // slow upload keeps its full --max-time, a dead one gives up in
            // half a minute. curl reports this as exit 28, same as a timeout.
            : String mfs ( string_from ( nurl_str_int max_bytes ) )
            ? > max_bytes 0 {
                ( vec_push [s] a `--max-filesize` )
                ( vec_push [s] a ( string_data mfs ) )
            } {}
            ( vec_push [String] hold mfs )
            ( vec_push [s] a `--speed-limit` )
            ( vec_push [s] a `1` )
            ( vec_push [s] a `--speed-time` )
            ( vec_push [s] a `30` )
            ( vec_push [s] a `-o` )
            ( vec_push [s] a ( string_data respfile ) )
            ( vec_push [s] a `-w` )
            ( vec_push [s] a `%{http_code}` )
            ( vec_push [s] a `-X` )
            ( vec_push [s] a method )
            : String stdin_cfg ( string_new )
            ( __httpc_push_headers headers_blob a hold stdin_cfg )

            // Body: --data-binary @<reqfile>. The "@path" arg must outlive
            // the spawn, so park it in `atarg`.
            : ~ String atarg ( string_new )
            ? > ( nurl_str_len reqfile ) 0 {
                ( vec_push [s] a `--data-binary` )
                = atarg ( string_with_cap + ( nurl_str_len reqfile ) 2 )
                ( string_push_char atarg 64 )  // '@'
                ( string_push_str atarg reqfile )
                ( vec_push [s] a ( string_data atarg ) )
            } {}
            // (`--`: the URL is never read as one of curl's options.)
            ( vec_push [s] a `--` )
            ( vec_push [s] a url )

            : ~ i status 0
            : ~ i ok 0
            : ~ i ec 0
            ?? ( process_run `curl` a ( string_data stdin_cfg ) ) {
                F _ → { = ec -1 }
                T out → {
                    = ec ( output_exit_code out )
                    ? == ec 0 {
                        = ok 1
                        = status ( nurl_str_to_int ( output_stdout out ) )
                    } {}
                }
            }

            ? == ok 0 {
                ( unlink ( string_data respfile ) )
                ? == ec 6 { ^ @ !HttpcResp HttpcErr { F # HttpcErr HttpcDns } } {}
                ? == ec 7 { ^ @ !HttpcResp HttpcErr { F # HttpcErr HttpcConnect } } {}
                ? == ec 28 { ^ @ !HttpcResp HttpcErr { F # HttpcErr HttpcTimeout } } {}
                ? | == ec 35 == ec 60 { ^ @ !HttpcResp HttpcErr { F # HttpcErr HttpcTls } } {}
                ^ @ !HttpcResp HttpcErr { F # HttpcErr HttpcOther }
            } {}

            // (A body past the cap curl could not see coming — no length
            // up front — is not read at all.)
            ? > max_bytes 0 {
                : i fsz ?? ( file_size ( string_data respfile ) ) { T z → z F _ → -1 }
                ? | < fsz 0 > fsz max_bytes {
                    ( unlink ( string_data respfile ) )
                    ^ @ !HttpcResp HttpcErr { F # HttpcErr HttpcOther }
                } {}
            } {}
            // Read the captured body, append a NUL for httpc_body_str.
            : ~ ( Vec u ) body ( vec_new [u] )
            : ~ i blen 0
            ?? ( read_file_bytes ( string_data respfile ) ) {
                T b → {
                    = blen ( vec_len [u] b )
                    = body b
                }
                F _ → {}
            }
            ( vec_push [u] body 0 )
            ( unlink ( string_data respfile ) )

            : HttpcResp r @ HttpcResp { status blen body }
            ^ @ !HttpcResp HttpcErr { T r }
        }
    }
}

// Write `body` to a temp file, run the request, then unlink the temp.
@ __httpc_with_body s method s url ( Vec u ) body s headers_blob → !HttpcResp HttpcErr {
    : String tdir ( env_temp_dir )
    : !String IoErr bf ( fs_tempfile ( string_data tdir ) `nurlpkg-body-` )
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
                ^ @ !HttpcResp HttpcErr { F # HttpcErr HttpcOther }
            } {}
            : !HttpcResp HttpcErr res ( __httpc_exec method url ( string_data bodyfile ) headers_blob )
            ( unlink ( string_data bodyfile ) )
            ^ res
        }
    }
}

// ── Public API ──────────────────────────────────────────────────────

@ httpc_get s url → !HttpcResp HttpcErr {
    ^ ( __httpc_exec `GET` url `` `` )
}

// GET with the response body capped at `max_bytes` (> 0): a larger one is
// HttpcOther, and never held in memory whole — a download from a server
// the caller does not control (a registry's tarball, agora #163).
@ httpc_get_max s url i max_bytes → !HttpcResp HttpcErr {
    ^ ( __httpc_exec_t `GET` url `` `` ( httpc_default_max_time ) max_bytes )
}

// Where `url` redirects to, without following it: one GET, its body
// discarded, and the redirect's `Location` (curl's %{redirect_url}).
// None when the answer is no redirect, or curl cannot run. `nurl upgrade`
// reads the newest release from GitHub's releases/latest redirect with it:
// that page is not under the REST API's rate limit (Agora #218).
@ httpc_redirect_location s url → ?String {
    ? ! ( httpc_url_is_http url ) { ^ @ ?String { F } } {}
    : String tdir ( env_temp_dir )
    : !String IoErr rf ( fs_tempfile ( string_data tdir ) `nurlpkg-resp-` )
    ?? rf {
        F _ → ^ @ ?String { F }
        T respfile → {
            : ( Vec s ) a ( vec_new [s] )
            ( vec_push [s] a `-s` )
            // HTTP(S) only, and no URL globbing (`[]` `{}`); no -L: the
            // redirect is the answer.
            ( vec_push [s] a `-g` )
            ( vec_push [s] a `--proto` )
            ( vec_push [s] a `=http,https` )
            ( vec_push [s] a `--connect-timeout` )
            ( vec_push [s] a `10` )
            ( vec_push [s] a `--max-time` )
            ( vec_push [s] a `30` )
            ( vec_push [s] a `-o` )
            ( vec_push [s] a ( string_data respfile ) )
            ( vec_push [s] a `-w` )
            ( vec_push [s] a `%{redirect_url}` )
            // (`--`: the URL is never read as one of curl's options.)
            ( vec_push [s] a `--` )
            ( vec_push [s] a url )
            : ~ ? String loc @ ?String { F }
            ?? ( process_run `curl` a `` ) {
                F _ → {}
                T out → {
                    ? & == ( output_exit_code out ) 0 > ( nurl_str_len ( output_stdout out ) ) 0 {
                        = loc @ ?String { T ( string_from ( output_stdout out ) ) }
                    } {}
                }
            }
            ( unlink ( string_data respfile ) )
            ^ loc
        }
    }
}

@ httpc_request s method s url s body s headers_blob → !HttpcResp HttpcErr {
    ^ ( httpc_request_timeout method url body headers_blob ( httpc_default_max_time ) )
}

// Same as httpc_request, with an explicit wall-clock cap in seconds. A server
// that calls an external service on a request path wants this: the default cap
// is long enough that a hung peer looks like a hang of your own program.
@ httpc_request_timeout s method s url s body s headers_blob i max_secs → !HttpcResp HttpcErr {
    ? == ( nurl_str_len body ) 0 {
        ^ ( __httpc_exec_t method url `` headers_blob max_secs 0 )
    } {}
    // Non-empty text body: stage it through a temp file so the byte path
    // and the text path are identical on the wire.
    : String tdir ( env_temp_dir )
    : !String IoErr bf ( fs_tempfile ( string_data tdir ) `nurlpkg-body-` )
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
                ^ @ !HttpcResp HttpcErr { F # HttpcErr HttpcOther }
            } {}
            : !HttpcResp HttpcErr res ( __httpc_exec_t method url ( string_data bodyfile ) headers_blob max_secs 0 )
            ( unlink ( string_data bodyfile ) )
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

@ httpc_resp_free sink HttpcResp r → v {}
