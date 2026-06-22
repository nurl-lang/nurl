// stdlib/ext/pkg_fetch.nu — registry fetch + verified install (I/O side).
//
// The pieces that turn a resolved `LockPkg` into files on disk, talking to
// a registry whose read path is plain static HTTP (R2 + CDN):
//
//   GET  <registry>/index/<name>.json            → the package index
//   GET  <registry>/pkgs/<name>/<name>-<v>.tar.gz → the tarball
//
// `pkg_install_one` downloads the tarball, verifies its SHA-256 against the
// checksum the index/lockfile recorded, gunzips it, and `tar_unpack`s it
// (path-safe) into `<dest>/<name>`. This composes the whole pure-NURL
// package stack: http (binary body) + hash + compress + tar.
//
// API:
//   ( pkg_fetch_index registry name )                       → String  ("" on miss)
//   ( pkg_install_one registry name version checksum dest )  → ! i PkgFetchErr  (0 = ok)
//   ( pkg_err_name e )                                       → s

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/hash_sha256.nu`
$ `stdlib/ext/http.nu`
$ `stdlib/ext/compress.nu`
$ `stdlib/ext/tar.nu`
$ `stdlib/ext/registry_index.nu`

: | PkgFetchErr {
    PkgHttp  // non-200 status or transport failure
    PkgEmpty  // empty tarball body
    PkgChecksumMismatch  // downloaded bytes don't match the recorded sha256
    PkgDecompress  // gzip_decompress failed
    PkgUnpack  // tar_unpack failed (bad/unsafe archive, I/O)
}

@ pkg_err_name PkgFetchErr e → s {
    ^ ?? e {
        PkgHttp → `PkgHttp`
        PkgEmpty → `PkgEmpty`
        PkgChecksumMismatch → `PkgChecksumMismatch`
        PkgDecompress → `PkgDecompress`
        PkgUnpack → `PkgUnpack`
    }
}

// <registry>/index/<name>.json  (single '/' separator ensured)
@ __pkg_index_url s registry s name → String {
    : String out ( string_with_cap 80 )
    ( string_push_str out registry )
    : i rn ( nurl_str_len registry )
    ? > rn 0 { ? != ( nurl_str_get registry - rn 1 ) 47 { ( string_push_char out 47 ) } {} } {}
    ( string_push_str out `index/` )
    ( string_push_str out name )
    ( string_push_str out `.json` )
    ^ out
}

// dest + '/' + name
@ __pkg_join s dest s name → String {
    : String out ( string_with_cap + + ( nurl_str_len dest ) ( nurl_str_len name ) 2 )
    ( string_push_str out dest )
    ( string_push_char out 47 )
    ( string_push_str out name )
    ^ out
}

// GET the index JSON; returns the body, or "" on any non-200 / transport
// failure (the resolver treats "" as not-found).
@ pkg_fetch_index s registry s name → String {
    : String url ( __pkg_index_url registry name )
    : !Response HttpErr rr ( http_get ( string_data url ) )
    ( string_free url )
    ?? rr {
        T resp → {
            : ~ String out ( string_new )
            ? == ( http_status resp ) 200 {
                ( string_free out )
                = out ( string_from ( http_body_str resp ) )
            } {}
            ( response_free resp )
            ^ out
        }
        F → ^ ( string_new )
    }
}

// Download <registry>/pkgs/<name>/<name>-<version>.tar.gz, verify its
// SHA-256 against `checksum` (skipped only when `checksum` is empty),
// gunzip, and tar_unpack into <dest>/<name>. Returns 0 on success.
@ pkg_install_one s registry s name s version s checksum s dest → !i PkgFetchErr {
    : String url ( regindex_tarball_url registry name version )
    : !Response HttpErr rr ( http_get ( string_data url ) )
    ( string_free url )
    ?? rr {
        F _ → ^ @ !i PkgFetchErr { F # PkgFetchErr PkgHttp }
        T resp → {
            ? != ( http_status resp ) 200 {
                ( response_free resp )
                ^ @ !i PkgFetchErr { F # PkgFetchErr PkgHttp }
            } {}
            : ( Vec u ) gz ( http_body_bytes resp )
            ( response_free resp )
            ? == ( vec_len [u] gz ) 0 {
                ( vec_free [u] gz )
                ^ @ !i PkgFetchErr { F # PkgFetchErr PkgEmpty }
            } {}

            // Integrity: sha256 over the downloaded .tar.gz bytes.
            ? > ( nurl_str_len checksum ) 0 {
                : ( Vec u ) digest ( sha256_pure gz )
                : String hex ( bytes_to_hex digest )
                : i ok ( nurl_str_eq ( string_data hex ) checksum )
                ( vec_free [u] digest )
                ( string_free hex )
                ? == ok 0 {
                    ( vec_free [u] gz )
                    ^ @ !i PkgFetchErr { F # PkgFetchErr PkgChecksumMismatch }
                } {}
            } {}

            : !( Vec u ) CompressErr dr ( gzip_decompress gz )
            ( vec_free [u] gz )
            ?? dr {
                F _ → ^ @ !i PkgFetchErr { F # PkgFetchErr PkgDecompress }
                T raw → {
                    : String destdir ( __pkg_join dest name )
                    : !i TarErr ur ( tar_unpack raw ( string_data destdir ) )
                    ( vec_free [u] raw )
                    ( string_free destdir )
                    ?? ur {
                        F _ → ^ @ !i PkgFetchErr { F # PkgFetchErr PkgUnpack }
                        T _ → ^ @ !i PkgFetchErr { T 0 }
                    }
                }
            }
        }
    }
}

// ── Search (read side) ────────────────────────────────────────────────

// GET <registry>/api/v1/search?q=<query> → the JSON body, or "" on
// non-200 / transport failure. Caller parses the {"results":[...]} JSON.
@ pkg_search s registry s query → String {
    : String url ( string_with_cap 80 )
    ( string_push_str url registry )
    : i rn ( nurl_str_len registry )
    ? > rn 0 { ? != ( nurl_str_get registry - rn 1 ) 47 { ( string_push_char url 47 ) } {} } {}
    ( string_push_str url `api/v1/search?q=` )
    ( string_push_str url query )
    : !Response HttpErr rr ( http_get ( string_data url ) )
    ( string_free url )
    ?? rr {
        T resp → {
            : ~ String out ( string_new )
            ? == ( http_status resp ) 200 {
                ( string_free out )
                = out ( string_from ( http_body_str resp ) )
            } {}
            ( response_free resp )
            ^ out
        }
        F → ^ ( string_new )
    }
}
