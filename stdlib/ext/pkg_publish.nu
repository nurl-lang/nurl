// stdlib/ext/pkg_publish.nu — package + authenticated publish (write side).
//
// `pkg_pack` walks a project directory, packs the source files into a
// `.tar.gz` (the same format the install side fetches), and `pkg_publish`
// uploads it to the registry's write endpoint with a Bearer token:
//
//   POST <registry>/api/v1/publish
//   Authorization: Bearer <token>
//   X-Nurl-Package: <name>
//   X-Nurl-Version: <version>
//   X-Nurl-Deps: [{"name":"bar","req":"^0.3"}]   (registry deps; for the index)
//   Content-Type: application/gzip
//   <body = the .tar.gz bytes>
//
// The token is the caller's concern (CLI reads $NURL_TOKEN). The registry
// recomputes the tarball's SHA-256 server-side — it never trusts a
// client-supplied digest — and is responsible for name ownership +
// immutability (a version may not be overwritten).
//
// Packaging excludes installed deps and VCS/build noise: `deps`, `.git`,
// `nurl.lock`, `target`, `build`, and any dotfile/dotdir. Member paths use
// the 100-byte USTAR `name` field (PackTooLong otherwise).
//
// API:
//   ( pkg_pack root )                              → ! ( Vec u ) PackErr
//   ( pkg_publish registry token tarball name ver deps_json ) → ! i PublishErr (0 = ok)
//   ( pack_err_name e ) / ( publish_err_name e )    → s

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/ext/tar.nu`
$ `stdlib/ext/compress.nu`
$ `stdlib/ext/http.nu`

: | PackErr {
    PackReadFailed  // dir_list / read_file failed
    PackEmpty  // no files to pack
    PackTarFailed  // tar_create rejected a path (too long) / failed
    PackGzipFailed  // gzip_compress failed
}

: | PublishErr {
    PubNoToken  // empty auth token
    PubHttp  // transport failure
    PubAuth  // 401 / 403
    PubConflict  // 409 — version already published (immutability)
    PubRejected  // other non-2xx
}

@ pack_err_name PackErr e → s {
    ^ ?? e {
        PackReadFailed → `PackReadFailed`
        PackEmpty → `PackEmpty`
        PackTarFailed → `PackTarFailed`
        PackGzipFailed → `PackGzipFailed`
    }
}

@ publish_err_name PublishErr e → s {
    ^ ?? e {
        PubNoToken → `PubNoToken`
        PubHttp → `PubHttp`
        PubAuth → `PubAuth`
        PubConflict → `PubConflict`
        PubRejected → `PubRejected`
    }
}

// Names never packaged (installed deps, VCS, build output, dotfiles).
@ __pack_ignored s name → b {
    ? != 0 ( nurl_str_eq name `deps` ) { ^ T } {}
    ? != 0 ( nurl_str_eq name `nurl.lock` ) { ^ T } {}
    ? != 0 ( nurl_str_eq name `target` ) { ^ T } {}
    ? != 0 ( nurl_str_eq name `build` ) { ^ T } {}
    : i n ( nurl_str_len name )
    ? > n 0 { ? == ( nurl_str_get name 0 ) 46 { ^ T } {} } {}  // leading '.'
    ^ F
}

// Recursively collect files under `root`/`rel` into `out` as TarEntries
// keyed by their path relative to `root`. Returns 0 on success, 1 on I/O
// failure.
@ __pack_collect s root s rel ( Vec TarEntry ) out → i {
    : String dir ( string_from root )
    ? > ( nurl_str_len rel ) 0 {
        ( string_push_char dir 47 )
        ( string_push_str dir rel )
    } {}
    : !( Vec String ) IoErr lr ( dir_list ( string_data dir ) )
    : ~ i rc 0
    ?? lr {
        F _ → { = rc 1 }
        T entries → {
            : i n ( vec_len [String] entries )
            : ~ i k 0
            ~ < k n {
                : ?String eo ( vec_get [String] entries k )
                ?? eo {
                    T nm → {
                        : s nm_s ( string_data nm )
                        ? ! ( __pack_ignored nm_s ) {
                            : String relpath ( string_new )
                            ? > ( nurl_str_len rel ) 0 {
                                ( string_push_str relpath rel )
                                ( string_push_char relpath 47 )
                            } {}
                            ( string_push_str relpath nm_s )
                            : String full ( string_from root )
                            ( string_push_char full 47 )
                            ( string_push_str full ( string_data relpath ) )
                            : i t ( nurl_path_type ( string_data full ) )
                            ? == t 1 {
                                : !( Vec u ) IoErr fb ( read_file_bytes ( string_data full ) )
                                ?? fb {
                                    T bytes → ( vec_push [TarEntry] out ( tar_entry_file ( string_data relpath ) bytes ) )
                                    F _ → { = rc 1 }
                                }
                            } {
                                ? == t 2 {
                                    : i sub ( __pack_collect root ( string_data relpath ) out )
                                    ? != sub 0 { = rc 1 } {}
                                } {}
                            }
                            ( string_free relpath )
                            ( string_free full )
                        } {}
                        ( string_free nm )
                    }
                    F → {}
                }
                = k + k 1
            }
            ( vec_free [String] entries )
        }
    }
    ( string_free dir )
    ^ rc
}

@ pkg_pack s root → !( Vec u ) PackErr {
    : ( Vec TarEntry ) ents ( vec_new [TarEntry] )
    : i cr ( __pack_collect root `` ents )
    ? != cr 0 {
        ( tar_entries_free ents )
        ^ @ !( Vec u ) PackErr { F # PackErr PackReadFailed }
    } {}
    ? == ( vec_len [TarEntry] ents ) 0 {
        ( tar_entries_free ents )
        ^ @ !( Vec u ) PackErr { F # PackErr PackEmpty }
    } {}
    : !( Vec u ) TarErr tr ( tar_create ents )
    ( tar_entries_free ents )
    ?? tr {
        F _ → ^ @ !( Vec u ) PackErr { F # PackErr PackTarFailed }
        T arc → {
            : !( Vec u ) CompressErr gr ( gzip_compress arc )
            ( vec_free [u] arc )
            ?? gr {
                F _ → ^ @ !( Vec u ) PackErr { F # PackErr PackGzipFailed }
                T gz → ^ @ !( Vec u ) PackErr { T gz }
            }
        }
    }
}

// <registry>/api/v1/publish  (single '/' separator ensured)
@ __publish_url s registry → String {
    : String out ( string_with_cap 64 )
    ( string_push_str out registry )
    : i rn ( nurl_str_len registry )
    ? > rn 0 { ? != ( nurl_str_get registry - rn 1 ) 47 { ( string_push_char out 47 ) } {} } {}
    ( string_push_str out `api/v1/publish` )
    ^ out
}

// `deps_json` is a JSON array of { name, req } for this package's registry
// dependencies (built by the caller from the manifest), sent as
// X-Nurl-Deps so the registry records them in the index and transitive
// registry resolution works. Pass `[]` (or empty) for none.
@ pkg_publish s registry s token ( Vec u ) tarball s name s version s deps_json → !i PublishErr {
    ? == ( nurl_str_len token ) 0 { ^ @ !i PublishErr { F # PublishErr PubNoToken } } {}
    : String url ( __publish_url registry )
    : String hb ( string_with_cap 256 )
    ( string_push_str hb `Authorization: Bearer ` )
    ( string_push_str hb token )
    ( string_push_str hb `\r\n` )
    ( string_push_str hb `X-Nurl-Package: ` )
    ( string_push_str hb name )
    ( string_push_str hb `\r\n` )
    ( string_push_str hb `X-Nurl-Version: ` )
    ( string_push_str hb version )
    ( string_push_str hb `\r\n` )
    ? > ( nurl_str_len deps_json ) 0 {
        ( string_push_str hb `X-Nurl-Deps: ` )
        ( string_push_str hb deps_json )
        ( string_push_str hb `\r\n` )
    } {}
    ( string_push_str hb `Content-Type: application/gzip\r\n` )
    : !Response HttpErr rr ( http_request_bytes `POST` ( string_data url ) tarball ( string_data hb ) )
    ( string_free url )
    ( string_free hb )
    ?? rr {
        F _ → ^ @ !i PublishErr { F # PublishErr PubHttp }
        T resp → {
            : i st ( http_status resp )
            ( response_free resp )
            ? & >= st 200 < st 300 { ^ @ !i PublishErr { T 0 } } {}
            ? | == st 401 == st 403 { ^ @ !i PublishErr { F # PublishErr PubAuth } } {}
            ? == st 409 { ^ @ !i PublishErr { F # PublishErr PubConflict } } {}
            ^ @ !i PublishErr { F # PublishErr PubRejected }
        }
    }
}

// ── Yank / unyank / token revoke (authenticated, no body) ─────────────

@ __reg_api_url s registry s path → String {
    : String out ( string_with_cap 64 )
    ( string_push_str out registry )
    : i rn ( nurl_str_len registry )
    ? > rn 0 { ? != ( nurl_str_get registry - rn 1 ) 47 { ( string_push_char out 47 ) } {} } {}
    ( string_push_str out path )
    ^ out
}

@ __pub_status_map i st → !i PublishErr {
    ? & >= st 200 < st 300 { ^ @ !i PublishErr { T 0 } } {}
    ? | == st 401 == st 403 { ^ @ !i PublishErr { F # PublishErr PubAuth } } {}
    ? == st 409 { ^ @ !i PublishErr { F # PublishErr PubConflict } } {}
    ^ @ !i PublishErr { F # PublishErr PubRejected }
}

// POST <registry>/api/v1/revoke — deletes the presented token server-side.
@ pkg_revoke s registry s token → !i PublishErr {
    ? == ( nurl_str_len token ) 0 { ^ @ !i PublishErr { F # PublishErr PubNoToken } } {}
    : String url ( __reg_api_url registry `api/v1/revoke` )
    : String hb ( string_with_cap 96 )
    ( string_push_str hb `Authorization: Bearer ` )
    ( string_push_str hb token )
    ( string_push_str hb `\r\n` )
    : !Response HttpErr rr ( http_request `POST` ( string_data url ) `` ( string_data hb ) )
    ( string_free url )
    ( string_free hb )
    ?? rr {
        F _ → ^ @ !i PublishErr { F # PublishErr PubHttp }
        T resp → {
            : i st ( http_status resp )
            ( response_free resp )
            ^ ( __pub_status_map st )
        }
    }
}

// POST <registry>/api/v1/{yank,unyank} — owner-only; flips the version's
// yanked flag (the resolver then skips yanked versions). `yank` != 0 to
// yank, 0 to unyank.
@ pkg_yank s registry s token s name s version i yank → !i PublishErr {
    ? == ( nurl_str_len token ) 0 { ^ @ !i PublishErr { F # PublishErr PubNoToken } } {}
    : s ep ? != yank 0 `api/v1/yank` `api/v1/unyank`
    : String url ( __reg_api_url registry ep )
    : String hb ( string_with_cap 160 )
    ( string_push_str hb `Authorization: Bearer ` )
    ( string_push_str hb token )
    ( string_push_str hb `\r\n` )
    ( string_push_str hb `X-Nurl-Package: ` )
    ( string_push_str hb name )
    ( string_push_str hb `\r\n` )
    ( string_push_str hb `X-Nurl-Version: ` )
    ( string_push_str hb version )
    ( string_push_str hb `\r\n` )
    : !Response HttpErr rr ( http_request `POST` ( string_data url ) `` ( string_data hb ) )
    ( string_free url )
    ( string_free hb )
    ?? rr {
        F _ → ^ @ !i PublishErr { F # PublishErr PubHttp }
        T resp → {
            : i st ( http_status resp )
            ( response_free resp )
            ^ ( __pub_status_map st )
        }
    }
}
