// stdlib/ext/registry_index.nu — registry package index (read side).
//
// A registry serves, per package, a static JSON index document at
// `<registry>/index/<name>.json`. nurlpkg fetches it, picks the highest
// version satisfying a semver requirement, then downloads the tarball at
// the name/version path `<registry>/pkgs/<name>/<name>-<ver>.tar.gz`
// and verifies its SHA-256 against the `checksum` recorded here. Because
// indexes change as versions are published or yanked, they must be refreshed;
// published archive contents remain immutable.
//
// Index schema (`<registry>/index/<name>.json`):
//
//   {
//     "name": "foo",
//     "versions": [
//       {
//         "version": "1.2.3",
//         "checksum": "<hex sha256 of foo-1.2.3.tar.gz>",
//         "yanked": false,
//         "deps": [ { "name": "bar", "req": "^0.3" } ]
//       }
//     ]
//   }
//
// The tarball URL is derived from name+version, so the index carries no
// URLs. The resolver adds the registry origin to (name, version, checksum).
//
// API:
//   ( regindex_parse json )        → ! RegIndex RegIndexErr
//   ( regindex_select idx req )    → i   highest non-yanked version index
//                                        satisfying `req`, or -1
//   ( regindex_free idx )          → v
//   ( regindex_err_name e )        → s

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/ext/json.nu`
$ `stdlib/ext/semver.nu`

: IdxDep {
    String name
    String req  // semver requirement
}

: IdxVersion {
    String version
    String checksum  // hex sha256 of the tarball
    b yanked
    ( Vec IdxDep ) deps
}

: RegIndex {
    String name
    ( Vec IdxVersion ) versions
}

: | RegIndexErr {
    RegIdxParseFailed  // not valid JSON
    RegIdxBadShape  // JSON parsed but isn't an index object
}

@ regindex_err_name RegIndexErr e → s {
    ^ ?? e {
        RegIdxParseFailed → `RegIdxParseFailed`
        RegIdxBadShape → `RegIdxBadShape`
    }
}

// ── Lifecycle ─────────────────────────────────────────────────────────

@ idxdep_free sink IdxDep d → v {
    ( string_free . d name )
    ( string_free . d req )
}

@ idxversion_free sink IdxVersion v → v {
    ( string_free . v version )
    ( string_free . v checksum )
    : i n ( vec_len [IdxDep] . v deps )
    : ~ i k 0
    ~ < k n {
        : ?IdxDep dk ( vec_get [IdxDep] . v deps k )
        ?? dk { T d → ( idxdep_free d ) F → {} }
        = k + k 1
    }
    ( vec_free [IdxDep] . v deps )
}

@ regindex_free sink RegIndex idx → v {
    ( string_free . idx name )
    : i n ( vec_len [IdxVersion] . idx versions )
    : ~ i k 0
    ~ < k n {
        : ?IdxVersion vk ( vec_get [IdxVersion] . idx versions k )
        ?? vk { T v → ( idxversion_free v ) F → {} }
        = k + k 1
    }
    ( vec_free [IdxVersion] . idx versions )
}

// ── JSON field helpers ────────────────────────────────────────────────

// Owned String from a string-typed field; empty when absent / wrong type.
@ __ridx_str Json obj s key → String {
    : ?Json f ( json_obj_get obj key )
    ?? f {
        T fj → ^ ( string_from ( json_as_str fj ) )
        F → ^ ( string_new )
    }
}

@ __ridx_bool Json obj s key → b {
    : ?Json f ( json_obj_get obj key )
    ?? f {
        T fj → ^ ( json_as_bool fj )
        F → ^ F
    }
}

@ __ridx_version Json vj → IdxVersion {
    : String version ( __ridx_str vj `version` )
    : String checksum ( __ridx_str vj `checksum` )
    : b yanked ( __ridx_bool vj `yanked` )
    : ( Vec IdxDep ) deps ( vec_new [IdxDep] )
    : ?Json da ( json_obj_get vj `deps` )
    ?? da {
        T darr → {
            : i n ( json_arr_len darr )
            : ~ i k 0
            ~ < k n {
                : ?Json dobj ( json_arr_get darr k )
                ?? dobj {
                    T dj → {
                        : String dn ( __ridx_str dj `name` )
                        : String dr ( __ridx_str dj `req` )
                        ( vec_push [IdxDep] deps @ IdxDep { dn dr } )
                    }
                    F → {}
                }
                = k + k 1
            }
        }
        F → {}
    }
    ^ @ IdxVersion { version checksum yanked deps }
}

// Validate the wire shape before projecting strings through the C-string
// APIs below. JSON strings can contain NUL; accepting a truncated name,
// requirement or checksum would silently change the selected identity.
@ __ridx_text_field Json obj s key → b {
    ?? ( json_obj_get obj key ) {
        T field → { ?? field {
                JStr text → { ^ & > ( string_len text ) 0 == ( string_len text ) ( nurl_str_len ( string_data text ) ) }
                _ → { ^ F }
            } }
        F _ → { ^ F }
    }
}

@ __ridx_deps_shape Json array → b {
    ?? array {
        JArr deps → {
            : i n ( vec_len [Json] deps )
            : *Json data ( vec_data [Json] deps )
            : ~ i k 0
            ~ < k n {
                : Json dep . data k
                ? ! & ( json_is_obj dep ) & ( __ridx_text_field dep `name` ) ( __ridx_text_field dep `req` ) { ^ F } {}
                = k + k 1
            }
            ^ T
        }
        _ → { ^ F }
    }
}

@ __ridx_version_shape Json version → b {
    ? ! & ( json_is_obj version ) & ( __ridx_text_field version `version` ) ( __ridx_text_field version `checksum` ) { ^ F } {}
    ?? ( json_obj_get version `yanked` ) {
        T yanked → { ? ! ( json_is_bool yanked ) { ^ F } {} }
        F _ → {}
    }
    ?? ( json_obj_get version `deps` ) {
        T deps → { ^ ( __ridx_deps_shape deps ) }
        F _ → { ^ T }
    }
}

@ __ridx_shape Json root → b {
    ? ! & ( json_is_obj root ) ( __ridx_text_field root `name` ) { ^ F } {}
    ?? ( json_obj_get root `versions` ) {
        T versions → { ?? versions {
                JArr entries → {
                    : i n ( vec_len [Json] entries )
                    : *Json data ( vec_data [Json] entries )
                    : ~ i k 0
                    ~ < k n {
                        ? ! ( __ridx_version_shape . data k ) { ^ F } {}
                        = k + k 1
                    }
                    ^ T
                }
                _ → { ^ F }
            } }
        F _ → { ^ F }
    }
}

// ── Parse ─────────────────────────────────────────────────────────────

@ regindex_parse s src → !RegIndex RegIndexErr {
    : !Json JsonError jr ( json_parse src )
    ?? jr {
        F _ → ^ @ !RegIndex RegIndexErr { F # RegIndexErr RegIdxParseFailed }
        T root → {
            ? ! ( __ridx_shape root ) {
                ( json_free root )
                ^ @ !RegIndex RegIndexErr { F RegIdxBadShape }
            } {}
            : String name ( __ridx_str root `name` )
            : ( Vec IdxVersion ) versions ( vec_new [IdxVersion] )
            : ?Json va ( json_obj_get root `versions` )
            ?? va {
                T varr → {
                    : i n ( json_arr_len varr )
                    : ~ i k 0
                    ~ < k n {
                        : ?Json vobj ( json_arr_get varr k )
                        ?? vobj {
                            T vj → ( vec_push [IdxVersion] versions ( __ridx_version vj ) )
                            F → {}
                        }
                        = k + k 1
                    }
                }
                F → {}
            }
            ( json_free root )
            ^ @ !RegIndex RegIndexErr { T @ RegIndex { name versions } }
        }
    }
}

// ── Version selection ─────────────────────────────────────────────────

// Index of the highest non-yanked version satisfying `req`, or -1.
@ regindex_select RegIndex idx s req → i {
    : !VersionReq SemverErr rr ( semver_req_parse req )
    : ~ i best -1
    ?? rr {
        F _ → { = best -1 }
        T r → {
            : i n ( vec_len [IdxVersion] . idx versions )
            : ~ i k 0
            ~ < k n {
                : ?IdxVersion vo ( vec_get [IdxVersion] . idx versions k )
                ?? vo {
                    T iv → {
                        ? ! . iv yanked {
                            : !Semver SemverErr cp ( semver_parse ( string_data . iv version ) )
                            ?? cp {
                                T cv → {
                                    ? ( semver_req_matches r cv ) {
                                        ? < best 0 {
                                            = best k
                                        } {
                                            : ?IdxVersion bo ( vec_get [IdxVersion] . idx versions best )
                                            ?? bo {
                                                T biv → {
                                                    : !Semver SemverErr bp ( semver_parse ( string_data . biv version ) )
                                                    ?? bp {
                                                        T bv → { ? ( semver_gt cv bv ) { = best k } {} ( semver_free bv ) }
                                                        F → {}
                                                    }
                                                }
                                                F → {}
                                            }
                                        }
                                    } {}
                                    ( semver_free cv )
                                }
                                F → {}
                            }
                        } {}
                    }
                    F → {}
                }
                = k + k 1
            }
            ( semver_req_free r )
        }
    }
    ^ best
}

// Convenience: the content-addressed tarball URL for (registry, name, ver):
//   <registry>/pkgs/<name>/<name>-<version>.tar.gz
// `registry` may or may not end in '/'; a single separator is ensured.
@ regindex_tarball_url s registry s name s version → String {
    : String out ( string_with_cap 96 )
    ( string_push_str out registry )
    : i rn ( nurl_str_len registry )
    ? > rn 0 {
        ? != ( nurl_str_get registry - rn 1 ) 47 { ( string_push_char out 47 ) } {}
    } {}
    ( string_push_str out `pkgs/` )
    ( string_push_str out name )
    ( string_push_char out 47 )
    ( string_push_str out name )
    ( string_push_char out 45 )
    ( string_push_str out version )
    ( string_push_str out `.tar.gz` )
    ^ out
}
