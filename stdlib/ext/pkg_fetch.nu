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
$ `stdlib/std/minisign.nu`
$ `stdlib/ext/env.nu`
$ `stdlib/ext/http_cli.nu`
$ `stdlib/ext/compress.nu`
$ `stdlib/ext/tar.nu`
$ `stdlib/ext/registry_index.nu`

: | PkgFetchErr {
    PkgHttp  // non-200 status or transport failure
    PkgEmpty  // empty tarball body
    PkgChecksumMismatch  // downloaded bytes don't match the recorded sha256
    PkgBadSig  // missing or invalid registry signature (fail-closed)
    PkgDecompress  // gzip_decompress failed
    PkgUnpack  // tar_unpack failed (bad/unsafe archive, I/O)
}

@ pkg_err_name PkgFetchErr e → s {
    ^ ?? e {
        PkgHttp → `PkgHttp`
        PkgEmpty → `PkgEmpty`
        PkgChecksumMismatch → `PkgChecksumMismatch`
        PkgBadSig → `PkgBadSig`
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
    : !HttpcResp HttpcErr rr ( httpc_get ( string_data url ) )
    ( string_free url )
    ?? rr {
        T resp → {
            : ~ String out ( string_new )
            ? == ( httpc_status resp ) 200 {
                ( string_free out )
                = out ( string_from ( httpc_body_str resp ) )
            } {}
            ( httpc_resp_free resp )
            ^ out
        }
        F → ^ ( string_new )
    }
}

// Pinned registry signing key (minisign public key — the base64 payload line,
// no comment header). The registry signs every published tarball with the
// matching Ed25519 secret; pinning the public key here means a compromised
// R2/CDN can't substitute tarball bytes without also forging this key. This
// is the trust anchor the pure-NURL minisign verifier checks against.
//
// $NURL_REGISTRY_PUBKEY overrides it — required when pointing nurlpkg at a
// self-hosted registry (with $NURL_REGISTRY), and used by the e2e test. It is
// a trust anchor, so treat it like a CA pin: only set it to a key you control.
@ __pkg_reg_pubkey → String {
    : ?String ev ( env_get `NURL_REGISTRY_PUBKEY` )
    ^ ?? ev {
        T v → v
        F → ( string_from `RWTGgah04Ft7n6+UNxc/MKT4eMViHBo4DLgKryJVbv9ZwedeQWpmmPq5` )
    }
}

// Fetch <tarball_url>.minisig and verify it over the tarball bytes with the
// pinned registry key. MANDATORY + fail-closed: a missing signature, a
// transport failure, or a bad signature all return F. `gz` is the exact
// .tar.gz bytes the registry signed (legacy 'Ed' minisign: raw Ed25519).
@ __pkg_verify_sig s registry s name s version ( Vec u ) gz → b {
    : String sigurl ( regindex_tarball_url registry name version )
    ( string_push_str sigurl `.minisig` )
    : !HttpcResp HttpcErr sr ( httpc_get ( string_data sigurl ) )
    ( string_free sigurl )
    ^ ?? sr {
        F _ → F
        T sresp → {
            : ~ b ok F
            ? == ( httpc_status sresp ) 200 {
                : String sigbody ( string_from ( httpc_body_str sresp ) )
                : String sl ( __ms_line2 ( string_data sigbody ) )
                : String pubkey ( __pkg_reg_pubkey )
                = ok ( minisign_verify_b64 gz ( string_data pubkey ) ( string_data sl ) )
                ( string_free pubkey )
                ( string_free sl )
                ( string_free sigbody )
            } {}
            ( httpc_resp_free sresp )
            ^ ok
        }
    }
}

// Download <registry>/pkgs/<name>/<name>-<version>.tar.gz, verify its
// SHA-256 against `checksum` (skipped only when `checksum` is empty), verify
// the registry's minisign signature (mandatory, fail-closed), gunzip, and
// tar_unpack into <dest>/<name>. Returns 0 on success.
@ pkg_install_one s registry s name s version s checksum s dest → !i PkgFetchErr {
    : String url ( regindex_tarball_url registry name version )
    : !HttpcResp HttpcErr rr ( httpc_get ( string_data url ) )
    ( string_free url )
    ?? rr {
        F _ → ^ @ !i PkgFetchErr { F # PkgFetchErr PkgHttp }
        T resp → {
            ? != ( httpc_status resp ) 200 {
                ( httpc_resp_free resp )
                ^ @ !i PkgFetchErr { F # PkgFetchErr PkgHttp }
            } {}
            : ( Vec u ) gz ( httpc_body_bytes resp )
            ( httpc_resp_free resp )
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

            // Authenticity: the registry signs every tarball with its Ed25519
            // project key. Verification is mandatory and fail-closed — no
            // signature, no install (even when the checksum matched).
            ? ( __pkg_verify_sig registry name version gz ) {} {
                ( vec_free [u] gz )
                ^ @ !i PkgFetchErr { F # PkgFetchErr PkgBadSig }
            }

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
    : !HttpcResp HttpcErr rr ( httpc_get ( string_data url ) )
    ( string_free url )
    ?? rr {
        T resp → {
            : ~ String out ( string_new )
            ? == ( httpc_status resp ) 200 {
                ( string_free out )
                = out ( string_from ( httpc_body_str resp ) )
            } {}
            ( httpc_resp_free resp )
            ^ out
        }
        F → ^ ( string_new )
    }
}
