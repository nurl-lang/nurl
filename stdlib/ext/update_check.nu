// stdlib/ext/update_check.nu — a best-effort "a newer toolchain is out" notice.
//
//   ( update_check_notice current )   → v
//
// `current` is this build's version (nurl_version). The check is:
//   * silent and non-fatal — it never blocks the command, never changes its
//     exit code, and prints at most one line to stderr;
//   * cached — the network is touched at most once per day ($NURL_HOME/
//     .update-check records the last check and the version it saw);
//   * opt-out — set $NURL_NO_UPDATE_CHECK to disable it entirely;
//   * quiet where a notice would be noise — skipped in CI ($CI), when stderr
//     is not a terminal (pipes, scripts), and on a dev/dirty build (a version
//     that is not a clean release tag).
//
// The version oracle is GitHub's releases/latest for nurl-lang/nurl — the same
// source the installer resolves "latest" from: the tag its redirect names,
// and the REST API (with a User-Agent, which GitHub requires) only when the
// redirect names none — read once a day. nurlc can adopt the same notice
// by calling update_check_notice( nurl_version ) at startup.

$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/path.nu`
$ `stdlib/std/time.nu`
$ `stdlib/std/term.nu`
$ `stdlib/ext/env.nu`
$ `stdlib/ext/json.nu`
$ `stdlib/ext/semver.nu`
$ `stdlib/ext/http_cli.nu`
$ `stdlib/core/slice.nu`

// one day, in seconds
: i __UC_TTL 86400

// strip a single leading 'v' — "v0.24.0" → "0.24.0"
@ __uc_strip_v s ver → String {
    : ( Slice u ) ver_v ( slice_of_str ver )
    ? & > ( nurl_str_len ver ) 0 == ( slice_byte ver_v 0 ) 118 {
        : String out ( string_new )
        : ~ i k 1
        ~ < k ( nurl_str_len ver ) {
            ( string_push_char out ( slice_byte ver_v k ) )
            = k + k 1
        }
        ^ out
    } {}
    ^ ( string_from ver )
}

// a clean release tag has no '-' (a dev build is "vX-<n>-g<sha>[-dirty]")
@ __uc_is_release s ver → b {
    : i n ( nurl_str_len ver )
    : ~ i k 0
    ~ < k n {
        ? == ( nurl_str_at ver n k ) 45 { ^ F } {}
        = k + k 1
    }
    ^ T
}

// $NURL_HOME/.update-check, else ~/.nurl/.update-check
@ __uc_cache_path → String {
    : ~ String base ( string_new )
    ?? ( env_get `NURL_HOME` ) {
        T v → { = base v }
        F → {
            : String home ( env_var_or `HOME` `.` )
            = base ( path_join ( string_data home ) `.nurl` )
        }
    }
    : String p ( path_join ( string_data base ) `.update-check` )
    ^ p
}

// true when `latest` is a strictly greater release than `current`
@ __uc_newer s latest s current → b {
    : String ls ( __uc_strip_v latest )
    : String cs ( __uc_strip_v current )
    : ~ b gt F
    ?? ( semver_parse ( string_data ls ) ) {
        T lv → {
            ?? ( semver_parse ( string_data cs ) ) {
                T cv → {
                    = gt ( semver_gt lv cv )
                }
                F _ → {}
            }
        }
        F _ → {}
    }
    ^ gt
}

// The tag a release URL names: `…/releases/tag/<tag>` → <tag>, up to the
// first `/`, `?` or `#`. None unless it reads as a version (`v` and a digit).
@ __uc_tag_of_url s url → ?String {
    : i n ( nurl_str_len url )
    : s needle `/releases/tag/`
    : i m ( nurl_str_len needle )
    : ~ i at -1
    : ~ i k 0
    ~ & < at 0 <= + k m n {
        : ~ b same T
        : ~ i j 0
        ~ & same < j m {
            ? != ( nurl_str_at url n + k j ) ( nurl_str_at needle m j ) { = same F } {}
            = j + j 1
        }
        ? same { = at + k m } {}
        = k + k 1
    }
    ? < at 0 { ^ @ ?String { F } } {}
    : ~ i e at
    : ~ b go T
    ~ & go < e n {
        : i c ( nurl_str_at url n e )
        ? | | == c 47 == c 63 == c 35 { = go F } { = e + e 1 }
    }
    ? < - e at 2 { ^ @ ?String { F } } {}
    ? != ( nurl_str_at url n at ) 118 { ^ @ ?String { F } } {}
    : i d ( nurl_str_at url n + at 1 )
    ? | < d 48 > d 57 { ^ @ ?String { F } } {}
    : String tag ( string_with_cap + - e at 1 )
    : ~ i q at
    ~ < q e {
        ( string_push_char tag ( nurl_str_at url n q ) )
        = q + q 1
    }
    ^ @ ?String { T tag }
}

// The newest release's tag from the GitHub REST API (None on any failure,
// a 403 included: 60 unauthenticated requests an hour per IP).
@ __uc_fetch_latest_api → ?String {
    : String hb ( string_new )
    ( string_push_str hb `User-Agent: nurl-update-check\r\nAccept: application/vnd.github+json\r\n` )
    : !HttpcResp HttpcErr rr ( httpc_request `GET` `https://api.github.com/repos/nurl-lang/nurl/releases/latest` `` ( string_data hb ) )
    ?? rr {
        T resp → {
            : ~ ? String out @ ?String { F }
            ? == ( httpc_status resp ) 200 {
                : !Json JsonError pj ( json_parse ( httpc_body_str resp ) )
                ?? pj {
                    T j → {
                        ?? ( json_obj_get j `tag_name` ) {
                            T tj → { = out @ ?String { T ( string_from ( json_str_data tj ) ) } }
                            F → {}
                        }
                    }
                    F _ → {}
                }
            } {}
            ^ out
        }
        F _ → { ^ @ ?String { F } }
    }
}

// The latest release tag (None on any failure). github.com's
// releases/latest redirect names it in its Location
// (…/releases/tag/vX.Y.Z), and that page is not under the REST API's rate
// limit, which answers 403 to every request past 60 an hour from one IP:
// CI runners, cloud sandboxes and NAT gateways share theirs (Agora #218).
// The API is the fallback, asked once.
@ __uc_fetch_latest → ?String {
    ?? ( httpc_redirect_location `https://github.com/nurl-lang/nurl/releases/latest` ) {
        T loc → {
            ?? ( __uc_tag_of_url ( string_data loc ) ) {
                T tag → { ^ @ ?String { T tag } }
                F → {}
            }
        }
        F → {}
    }
    ^ ( __uc_fetch_latest_api )
}

// write { "checked": <secs>, "latest": "<ver-or-dash>" }
@ __uc_write_cache s path i secs s latest → v {
    : Json j ( json_obj_new )
    : b _1 ( json_obj_set j `checked` ( json_int secs ) )
    : b _2 ( json_obj_set j `latest` ( json_str_lit latest ) )
    : String txt ( json_stringify j )
    ?? ( write_file path ( string_data txt ) ) { T _ → {} F _ → {} }
}

// the cache read result: was the probe fresh (within the TTL), and the
// latest version it recorded ("" when absent / stale / a failed probe).
: UcCache {
    b fresh
    String latest
}

@ __uc_read_cache s path i now → UcCache {
    : ~ b fresh F
    : ~ String latest ( string_new )
    ?? ( read_file path ) {
        T txt → {
            : !Json JsonError pj ( json_parse ( string_data txt ) )
            ?? pj {
                T j → {
                    : ~ i checked 0
                    ?? ( json_obj_get j `checked` ) {
                        T cj → { ?? ( json_num_as_i cj ) { T v → { = checked v } F → {} } }
                        F → {}
                    }
                    ? & > checked 0 < - now checked __UC_TTL {
                        = fresh T
                        ?? ( json_obj_get j `latest` ) {
                            T lj → {
                                : s ld ( json_str_data lj )
                                ? != ( nurl_str_eq ld `-` ) 0 {} { = latest ( string_from ld ) }
                            }
                            F → {}
                        }
                    } {}
                }
                F _ → {}
            }
        }
        F → {}
    }
    ^ @ UcCache { fresh latest }
}

@ __uc_notice s latest s current → v {
    : String m ( string_from `\nA newer NURL toolchain is available: ` )
    ( string_push_str m latest )
    ( string_push_str m ` (you have ` )
    ( string_push_str m current )
    ( string_push_str m `).\n  update:  nurl upgrade\n` )
    ( nurl_eprint ( string_data m ) )
}

// ── public helpers ───────────────────────────────────────────────────
//
// The notice above is the passive half of the story; `nurl upgrade`
// (stdlib/ext/toolchain.nu) is the active one and needs the same three
// primitives — probe, release-tag test, compare. They are exported here
// rather than duplicated so both halves always agree on what "newer"
// means.

// Probe GitHub for the newest release tag, IGNORING the once-a-day cache.
// None when the network / API is unavailable. Owned String on Some.
@ update_check_latest → ?String {
    ^ ( __uc_fetch_latest )
}

// Is `ver` a clean release tag (vX.Y.Z), as opposed to a dev build
// (vX.Y.Z-<n>-g<sha>[-dirty])? Upgrading only makes sense for the former.
@ update_check_is_release s ver → b {
    ^ ( __uc_is_release ver )
}

// Strictly-greater release comparison, tolerant of a leading 'v'.
@ update_check_newer s latest s current → b {
    ^ ( __uc_newer latest current )
}

// Drop the cached probe. Called right after a successful upgrade so the
// next command re-probes instead of repeating a notice for the version
// the user just installed.
@ update_check_forget → v {
    : String cp ( __uc_cache_path )
    ? ( file_exists ( string_data cp ) ) {
        ?? ( file_delete ( string_data cp ) ) { T _ → {} F _ → {} }
    } {}
}

@ update_check_notice s current → v {
    // opt-out and noise guards
    ?? ( env_get `NURL_NO_UPDATE_CHECK` ) { T v → { ^ } F → {} }
    ?? ( env_get `CI` ) { T v → { ^ } F → {} }
    ? ( __uc_is_release current ) {} { ^ }
    ? ( term_is_tty 2 ) {} { ^ }

    : i now ( now_seconds )
    : String cp ( __uc_cache_path )
    : UcCache c ( __uc_read_cache ( string_data cp ) now )
    : ~ String latest ( string_from ( string_data . c latest ) )
    : b fresh . c fresh

    ? fresh {} {
        // one probe per day; record the outcome either way so a persistent
        // failure does not re-probe on every run
        ?? ( __uc_fetch_latest ) {
            T v → {
                = latest v
                ( __uc_write_cache ( string_data cp ) now ( string_data latest ) )
            }
            F → { ( __uc_write_cache ( string_data cp ) now `-` ) }
        }
    }

    ? > ( string_len latest ) 0 {
        ? ( __uc_newer ( string_data latest ) current ) {
            ( __uc_notice ( string_data latest ) current )
        } {}
    } {}
}
