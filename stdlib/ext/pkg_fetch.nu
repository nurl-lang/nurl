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
//   ( pkg_fetch_index registry name )                       → !RegIndex RegistryFetchErr
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
$ `stdlib/ext/registry_fetch.nu`
$ `stdlib/ext/registry_trust.nu`
$ `stdlib/ext/lockfile.nu`
$ `stdlib/ext/manifest.nu`

: | PkgFetchErr {
    PkgHttp  // non-200 status or transport failure
    PkgEmpty  // empty tarball body
    PkgChecksumMismatch  // downloaded bytes don't match the recorded sha256
    PkgBadSig  // missing or invalid registry signature (fail-closed)
    PkgDecompress  // gzip_decompress failed
    PkgUnpack  // tar_unpack failed (bad/unsafe archive, I/O)
    PkgBadIdentity  // URL/index/archive does not identify the requested package
    PkgUntrustedRegistry  // no signing key configured for this registry
    PkgTrustConfig  // malformed or unreadable explicit trust configuration
    PkgToolchain  // package requires a newer compiler/stdlib/runtime
}

@ pkg_err_name PkgFetchErr e → s {
    ^ ?? e {
        PkgHttp → `PkgHttp`
        PkgEmpty → `PkgEmpty`
        PkgChecksumMismatch → `PkgChecksumMismatch`
        PkgBadSig → `PkgBadSig`
        PkgDecompress → `PkgDecompress`
        PkgUnpack → `PkgUnpack`
        PkgBadIdentity → `PkgBadIdentity`
        PkgUntrustedRegistry → `PkgUntrustedRegistry`
        PkgTrustConfig → `PkgTrustConfig`
        PkgToolchain → `PkgToolchain: upgrade NURL to satisfy package.nurl-version`
    }
}

// dest + '/' + name
@ __pkg_join s dest s name → String {
    : String out ( string_with_cap + + ( nurl_str_len dest ) ( nurl_str_len name ) 2 )
    ( string_push_str out dest )
    ( string_push_char out 47 )
    ( string_push_str out name )
    ^ out
}

// A successful response is decoded once and bound to the requested identity.
// Library code returns errors without printing; callers decide how to report.
@ pkg_fetch_index s registry s name → !RegIndex RegistryFetchErr {
    ? ! ( registry_name_valid name ) { ^ @ !RegIndex RegistryFetchErr { F RegistryBadIdentity } } {}
    : String url ( registry_index_url registry name )
    : !HttpcResp HttpcErr response ( httpc_get ( string_data url ) )
    ( string_free url )
    ?? response {
        F error → { ^ @ !RegIndex RegistryFetchErr { F @ RegistryFetchErr { RegistryTransport error } } }
        T resp → {
            : i status ( httpc_status resp )
            ? != status 200 {
                ( httpc_resp_free resp )
                ? == status 404 { ^ @ !RegIndex RegistryFetchErr { F RegistryNotFound } } {}
                ^ @ !RegIndex RegistryFetchErr { F @ RegistryFetchErr { RegistryHttp status } }
            } {}
            : String text ( string_from_bytes # *u ( httpc_body_str resp ) . resp blen )
            ( httpc_resp_free resp )
            : !RegIndex RegistryFetchErr result ( registry_index_decode name text )
            ( string_free text )
            ^ result
        }
    }
}

// Fetch <tarball_url>.minisig and verify it over the tarball bytes with the
// pinned registry key. MANDATORY + fail-closed: a missing signature, a
// transport failure, or a bad signature all return F. `gz` is the exact
// .tar.gz bytes the registry signed (legacy 'Ed' minisign: raw Ed25519).
@ __pkg_verify_sig s registry s name s version ( Vec u ) gz s pubkey → b {
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
                : String sl ( _ms_line2 ( string_data sigbody ) )
                = ok ( minisign_verify_b64 gz pubkey ( string_data sl ) )
                ( string_free sl )
                ( string_free sigbody )
            } {}
            ( httpc_resp_free sresp )
            ^ ok
        }
    }
}

// Download <registry>/pkgs/<name>/<name>-<version>.tar.gz, verify its
// SHA-256 against the required `checksum`, verify
// the registry's minisign signature (mandatory, fail-closed), gunzip, and
// tar_unpack into <dest>/<name>. Returns 0 on success.
@ pkg_install_one s registry s name s version s checksum s dest → !i PkgFetchErr {
    ^ ( pkg_install_one_for_toolchain registry name version checksum dest ( nurl_version ) )
}

// Explicit target version for tools selecting a separately installed compiler.
@ pkg_install_one_for_toolchain s registry s name s version s checksum s dest s toolchain → !i PkgFetchErr {
    ?? ( registry_trust_load ) {
        F _ → { ^ @ !i PkgFetchErr { F PkgTrustConfig } }
        T trust → {
            : LockPkg pkg ( lock_pkg_new name version `registry+` checksum )
            ( string_push_str . pkg source registry )
            : !i PkgFetchErr result ( pkg_install_locked_for_toolchain trust pkg dest toolchain )
            ( lock_pkg_free pkg )
            ( registry_trust_free trust )
            ^ result
        }
    }
}

// Download origin, signing key and lock source are the same identity.
// Load trust once per batch and borrow it for every package.
@ pkg_install_locked RegistryTrust trust LockPkg pkg s dest → !i PkgFetchErr {
    ^ ( pkg_install_locked_for_toolchain trust pkg dest ( nurl_version ) )
}

@ pkg_install_locked_for_toolchain RegistryTrust trust LockPkg pkg s dest s toolchain → !i PkgFetchErr {
    ? ! ( registry_name_valid ( string_data . pkg name ) ) { ^ @ !i PkgFetchErr { F PkgBadIdentity } } {}
    ?? ( semver_parse ( string_data . pkg version ) ) {
        F _ → { ^ @ !i PkgFetchErr { F PkgBadIdentity } }
        T parsed → { ( semver_free parsed ) }
    }
    ?? ( registry_from_source ( string_data . pkg source ) ) {
        F empty → { ( string_free empty ) ^ @ !i PkgFetchErr { F PkgBadIdentity } }
        T registry → {
            : s key ( registry_trust_key trust ( string_data registry ) )
            ? == ( nurl_str_len key ) 0 {
                ( string_free registry )
                ^ @ !i PkgFetchErr { F PkgUntrustedRegistry }
            } {}
            : !i PkgFetchErr result ( __pkg_install_verified ( string_data registry )
            ( string_data . pkg name ) ( string_data . pkg version )
            ( string_data . pkg checksum ) dest key toolchain )
            ( string_free registry )
            ^ result
        }
    }
}

@ __pkg_archive_identity ( Vec TarEntry ) entries s name s version s toolchain → !v PkgFetchErr {
    : ~ b compatible T
    : ~ i manifests 0
    : ~ b valid F
    : i n ( vec_len [TarEntry] entries )
    : ~ i k 0
    ~ < k n {
        ?? ( vec_get [TarEntry] entries k ) {
            T entry → {
                : String path ( path_normalize ( string_data . entry path ) )
                ? != 0 ( nurl_str_eq ( string_data path ) `nurl.toml` ) {
                    = manifests + manifests 1
                    : String text ( bytes_to_str . entry data )
                    ? & | == . entry typeflag 48 == . entry typeflag 0
                    == ( string_len text ) ( nurl_str_len ( string_data text ) ) {
                        ?? ( manifest_parse ( string_data text ) `nurl.toml` ) {
                            T manifest → {
                                = valid & != 0 ( nurl_str_eq ( string_data . manifest name ) name )
                                != 0 ( nurl_str_eq ( string_data . manifest version ) version )
                                = compatible ( manifest_supports_toolchain manifest toolchain )
                                ( manifest_free manifest )
                            }
                            F _ → {}
                        }
                    } {}
                    ( string_free text )
                } {}
                ( string_free path )
            }
            F _ → {}
        }
        = k + k 1
    }
    ? | != manifests 1 ! valid { ^ @ !v PkgFetchErr { F PkgBadIdentity } } {}
    ? ! compatible { ^ @ !v PkgFetchErr { F PkgToolchain } } {}
    ^ @ !v PkgFetchErr { T 0 }
}

@ __pkg_install_verified s registry s name s version s checksum s dest s pubkey s toolchain → !i PkgFetchErr {
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

            // Integrity: an empty or malformed expected hash cannot match.
            : ( Vec u ) digest ( sha256_pure gz )
            : String hex ( bytes_to_hex digest )
            : i ok ( nurl_str_eq ( string_data hex ) checksum )
            ( vec_free [u] digest )
            ( string_free hex )
            ? == ok 0 {
                ( vec_free [u] gz )
                ^ @ !i PkgFetchErr { F # PkgFetchErr PkgChecksumMismatch }
            } {}

            // Authenticity: the registry signs every tarball with its Ed25519
            // project key. Verification is mandatory and fail-closed — no
            // signature, no install (even when the checksum matched).
            ? ( __pkg_verify_sig registry name version gz pubkey ) {} {
                ( vec_free [u] gz )
                ^ @ !i PkgFetchErr { F # PkgFetchErr PkgBadSig }
            }

            : !( Vec u ) CompressErr dr ( gzip_decompress gz )
            ( vec_free [u] gz )
            ?? dr {
                F _ → ^ @ !i PkgFetchErr { F # PkgFetchErr PkgDecompress }
                T raw → {
                    : !( Vec TarEntry ) TarErr parsed ( tar_parse raw )
                    ( vec_free [u] raw )
                    ?? parsed {
                        F _ → { ^ @ !i PkgFetchErr { F PkgUnpack } }
                        T entries → {
                            ?? ( __pkg_archive_identity entries name version toolchain ) {
                                F error → {
                                    ( tar_entries_free entries )
                                    ^ @ !i PkgFetchErr { F error }
                                }
                                T _ → {}
                            }
                            : String destdir ( __pkg_join dest name )
                            : !i TarErr result ( tar_unpack_entries entries ( string_data destdir ) )
                            ( string_free destdir )
                            ( tar_entries_free entries )
                            ?? result {
                                F _ → { ^ @ !i PkgFetchErr { F PkgUnpack } }
                                T _ → { ^ @ !i PkgFetchErr { T 0 } }
                            }
                        }
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
