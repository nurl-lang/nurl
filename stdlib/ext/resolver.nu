// stdlib/ext/resolver.nu — registry dependency resolution → lockfile.
//
// Given a manifest's registry dependencies and a way to fetch a package's
// index JSON, walk the transitive dependency graph (BFS), pick the
// highest version satisfying each requirement, and emit a `Vec[LockPkg]`
// ready for `lock_serialize`. The index fetcher is injected as a closure
// (`name → index-JSON String`, empty = not found) so the resolver is pure
// and offline-testable; nurlpkg wires it to an HTTP GET of
// `<registry>/index/<name>.json`.
//
// v1 resolution policy:
//   * One version per package name (no multi-version / SAT solving). The
//     first requirement to reach a name selects its version; a later
//     requirement on the same name must also be satisfied by that already
//     -chosen version, else ResolveConflict.
//   * Sub-dependencies are fetched from the same registry as their parent.
//   * Path dependencies among the roots are ignored here (nurlpkg installs
//     them via symlink); only registry deps are resolved.
//
// API:
//   ( resolve_registry roots default_registry fetch ) → ! ( Vec LockPkg ) ResolveErr
//   ( resolve_err_name e ) → s

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/ext/manifest.nu`
$ `stdlib/ext/lockfile.nu`
$ `stdlib/ext/registry_index.nu`
$ `stdlib/ext/semver.nu`

: | ResolveErr {
    ResolveNotFound    // a package has no index (fetch returned empty)
    ResolveBadIndex    // a fetched index didn't parse
    ResolveNoMatch     // no published version satisfies the requirement
    ResolveConflict    // two requirements on one name can't share a version
}

@ resolve_err_name ResolveErr e → s {
    ^ ?? e {
        ResolveNotFound → `ResolveNotFound`
        ResolveBadIndex → `ResolveBadIndex`
        ResolveNoMatch → `ResolveNoMatch`
        ResolveConflict → `ResolveConflict`
    }
}

: ResolveReq {
    String name
    String req
    String registry
}

@ __req_free ResolveReq r → v {
    ( string_free . r name )
    ( string_free . r req )
    ( string_free . r registry )
}

@ __reqs_free ( Vec ResolveReq ) q → v {
    : i n ( vec_len [ResolveReq] q )
    : ~ i k 0
    ~ < k n {
        : ?ResolveReq ro ( vec_get [ResolveReq] q k )
        ?? ro { T r → ( __req_free r ) F → {} }
        = k + k 1
    }
    ( vec_free [ResolveReq] q )
}

@ __strs_free ( Vec String ) v → v {
    : i n ( vec_len [String] v )
    : ~ i k 0
    ~ < k n {
        : ?String so ( vec_get [String] v k )
        ?? so { T s → ( string_free s ) F → {} }
        = k + k 1
    }
    ( vec_free [String] v )
}

@ __seen_has ( Vec String ) seen s name → b {
    : i n ( vec_len [String] seen )
    : ~ i k 0
    ~ < k n {
        : ?String so ( vec_get [String] seen k )
        ?? so { T s → { ? != 0 ( nurl_str_eq ( string_data s ) name ) { ^ T } {} } F → {} }
        = k + k 1
    }
    ^ F
}

// Raw version string locked for `name`, or `` if not locked.
@ __locked_version ( Vec LockPkg ) locked s name → s {
    : i n ( vec_len [LockPkg] locked )
    : ~ i k 0
    ~ < k n {
        : ?LockPkg po ( vec_get [LockPkg] locked k )
        ?? po { T p → { ? != 0 ( nurl_str_eq ( string_data . p name ) name ) { ^ ( string_data . p version ) } {} } F → {} }
        = k + k 1
    }
    ^ ``
}

// "registry+<reg>"
@ __reg_source s reg → String {
    : String out ( string_with_cap 48 )
    ( string_push_str out `registry+` )
    ( string_push_str out reg )
    ^ out
}

// Does the already-locked version of `name` satisfy `req`?
@ __already_ok ( Vec LockPkg ) locked s name s req → b {
    : s lv ( __locked_version locked name )
    ? == ( nurl_str_len lv ) 0 { ^ T } {}
    : !VersionReq SemverErr rr ( semver_req_parse req )
    : !Semver SemverErr vp ( semver_parse lv )
    : ~ b ok F
    ?? rr {
        T r → {
            ?? vp {
                T v → { = ok ( semver_req_matches r v ) ( semver_free v ) }
                F → {}
            }
            ( semver_req_free r )
        }
        F → {}
    }
    ^ ok
}

@ resolve_registry ( Vec Dep ) roots s default_registry ( @ String s ) fetch → !( Vec LockPkg ) ResolveErr {
    : ( Vec LockPkg ) locked ( vec_new [LockPkg] )
    : ( Vec String ) seen ( vec_new [String] )
    : ( Vec ResolveReq ) queue ( vec_new [ResolveReq] )

    // Seed the queue with the registry roots.
    : i nr ( vec_len [Dep] roots )
    : ~ i i 0
    ~ < i nr {
        : ?Dep dopt ( vec_get [Dep] roots i )
        ?? dopt {
            T d → {
                ? ( dep_is_registry d ) {
                    : s reg ? > ( string_len . d registry ) 0 ( string_data . d registry ) default_registry
                    ( vec_push [ResolveReq] queue @ ResolveReq {
                        ( string_from ( string_data . d name ) )
                        ( string_from ( string_data . d version ) )
                        ( string_from reg )
                    } )
                } {}
            }
            F → {}
        }
        = i + i 1
    }

    : ~ i qi 0
    : ~ i failed 0
    : ~ ResolveErr ferr ResolveNotFound
    ~ & == failed 0 < qi ( vec_len [ResolveReq] queue ) {
        : ?ResolveReq ropt ( vec_get [ResolveReq] queue qi )
        ?? ropt {
            T req → {
                : s nm ( string_data . req name )
                : s rq ( string_data . req req )
                : s reg ( string_data . req registry )
                ? ( __seen_has seen nm ) {
                    ? ! ( __already_ok locked nm rq ) { = failed 1 = ferr ResolveConflict } {}
                } {
                    : String json ( fetch nm )
                    ? == ( string_len json ) 0 {
                        ( string_free json )
                        = failed 1
                        = ferr ResolveNotFound
                    } {
                        : !RegIndex RegIndexErr ir ( regindex_parse ( string_data json ) )
                        ?? ir {
                            F _ → { = failed 1 = ferr ResolveBadIndex }
                            T idx → {
                                : i sel ( regindex_select idx rq )
                                ? < sel 0 {
                                    = failed 1
                                    = ferr ResolveNoMatch
                                } {
                                    : ?IdxVersion vopt ( vec_get [IdxVersion] . idx versions sel )
                                    ?? vopt {
                                        T iv → {
                                            ( vec_push [LockPkg] locked @ LockPkg {
                                                ( string_from nm )
                                                ( string_from ( string_data . iv version ) )
                                                ( __reg_source reg )
                                                ( string_from ( string_data . iv checksum ) )
                                            } )
                                            ( vec_push [String] seen ( string_from nm ) )
                                            : i nd ( vec_len [IdxDep] . iv deps )
                                            : ~ i j 0
                                            ~ < j nd {
                                                : ?IdxDep ddopt ( vec_get [IdxDep] . iv deps j )
                                                ?? ddopt {
                                                    T dd → ( vec_push [ResolveReq] queue @ ResolveReq {
                                                        ( string_from ( string_data . dd name ) )
                                                        ( string_from ( string_data . dd req ) )
                                                        ( string_from reg )
                                                    } )
                                                    F → {}
                                                }
                                                = j + j 1
                                            }
                                        }
                                        F → {}
                                    }
                                }
                                ( regindex_free idx )
                            }
                        }
                        ( string_free json )
                    }
                }
            }
            F → {}
        }
        = qi + qi 1
    }

    ( __reqs_free queue )
    ( __strs_free seen )
    ? != failed 0 {
        ( lockpkgs_free locked )
        ^ @ !( Vec LockPkg ) ResolveErr { F ferr }
    } {}
    ^ @ !( Vec LockPkg ) ResolveErr { T locked }
}
