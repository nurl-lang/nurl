// stdlib/ext/resolver.nu — registry dependency resolution → lockfile.
//
// Given a manifest's registry dependencies and a way to fetch a package's
// index JSON, walk the transitive dependency graph, pick for each package
// name the highest version satisfying ALL of its accumulated requirements,
// and emit a `Vec[LockPkg]` ready for `lock_serialize`. The index fetcher is
// injected as a closure (`name → index-JSON String`, empty = not found) so
// the resolver is pure and offline-testable; nurlpkg wires it to an HTTP GET
// of `<registry>/index/<name>.json`.
//
// Resolution policy (greedy, single version per name):
//   * One version per package name (no multi-major coexistence / SAT solving).
//   * A name's version is the HIGHEST published, non-yanked version that
//     satisfies the INTERSECTION of every requirement placed on it — direct
//     or transitive. This is a fixpoint: select against the accumulated
//     constraints, rebuild the constraints from the selected versions' deps,
//     and repeat until the selection stops changing. So two requirements on
//     one name that a common version satisfies (`^1` from A and `>=1 <1.5`
//     from B → 1.4) resolve; only a genuinely empty intersection is a
//     ResolveConflict. (Contrast the old first-requirement-wins policy, which
//     locked A's `^1` at 1.9 and then spuriously conflicted on B.)
//   * It does NOT backtrack: it never revisits a *published-dependency* choice,
//     so a graph whose satisfiability hinges on a package exposing different
//     deps at different versions is out of scope (a full solver's job).
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
    ResolveNotFound  // a package has no index (fetch returned empty)
    ResolveBadIndex  // a fetched index didn't parse
    ResolveNoMatch  // no published version satisfies the requirement
    ResolveConflict  // two requirements on one name can't share a version
}

@ resolve_err_name ResolveErr e → s {
    ^ ?? e {
        ResolveNotFound → `ResolveNotFound`
        ResolveBadIndex → `ResolveBadIndex`
        ResolveNoMatch → `ResolveNoMatch`
        ResolveConflict → `ResolveConflict`
    }
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

// "registry+<reg>"
@ __reg_source s reg → String {
    : String out ( string_with_cap 48 )
    ( string_push_str out `registry+` )
    ( string_push_str out reg )
    ^ out
}

// ── Accumulated constraints for one package name ──────────────────────
// `reqs` is every requirement placed on `name` so far; `registry` is the
// registry it (and its own sub-deps) are fetched/sourced from, kept from the
// first time the name is seen.
: __NameReq { String name ( Vec String ) reqs String registry }

@ __nreq_free __NameReq nr → v {
    ( string_free . nr name )
    ( __strs_free . nr reqs )
    ( string_free . nr registry )
}

@ __nreqs_free ( Vec __NameReq ) cs → v {
    : i n ( vec_len [__NameReq] cs )
    : ~ i k 0
    ~ < k n {
        : ?__NameReq o ( vec_get [__NameReq] cs k )
        ?? o { T nr → ( __nreq_free nr ) F → {} }
        = k + k 1
    }
    ( vec_free [__NameReq] cs )
}

// Index of the __NameReq for `name`, or -1.
@ __nreq_find ( Vec __NameReq ) cs s name → i {
    : i n ( vec_len [__NameReq] cs )
    : ~ i k 0
    ~ < k n {
        : ?__NameReq o ( vec_get [__NameReq] cs k )
        ?? o { T nr → { ? != 0 ( nurl_str_eq ( string_data . nr name ) name ) { ^ k } {} } F → {} }
        = k + k 1
    }
    ^ -1
}

@ __reqs_has ( Vec String ) reqs s req → b {
    : i n ( vec_len [String] reqs )
    : ~ i k 0
    ~ < k n {
        : ?String o ( vec_get [String] reqs k )
        ?? o { T s → { ? != 0 ( nurl_str_eq ( string_data s ) req ) { ^ T } {} } F → {} }
        = k + k 1
    }
    ^ F
}

// Add (name, req, registry) to the constraint set, deduping reqs; the
// registry is kept from the first time a name is seen. (Vec is a shared
// boxed handle, so pushing to `. nr reqs` mutates the stored entry.)
@ __nreq_add ( Vec __NameReq ) cs s name s req s registry → v {
    : i i ( __nreq_find cs name )
    ? >= i 0 {
        : ?__NameReq o ( vec_get [__NameReq] cs i )
        ?? o {
            T nr → { ? ! ( __reqs_has . nr reqs req ) { ( vec_push [String] . nr reqs ( string_from req ) ) } {} }
            F → {}
        }
    } {
        : ( Vec String ) rs ( vec_new [String] )
        ( vec_push [String] rs ( string_from req ) )
        ( vec_push [__NameReq] cs @ __NameReq { ( string_from name ) rs ( string_from registry ) } )
    }
}

// Deep copy of a constraint set.
@ __nreqs_copy ( Vec __NameReq ) src → ( Vec __NameReq ) {
    : ( Vec __NameReq ) out ( vec_new [__NameReq] )
    : i n ( vec_len [__NameReq] src )
    : ~ i k 0
    ~ < k n {
        : ?__NameReq o ( vec_get [__NameReq] src k )
        ?? o {
            T nr → {
                : ( Vec String ) rs ( vec_new [String] )
                : i m ( vec_len [String] . nr reqs )
                : ~ i j 0
                ~ < j m {
                    : ?String so ( vec_get [String] . nr reqs j )
                    ?? so { T s → ( vec_push [String] rs ( string_from ( string_data s ) ) ) F → {} }
                    = j + j 1
                }
                ( vec_push [__NameReq] out @ __NameReq {
                    ( string_from ( string_data . nr name ) )
                    rs
                    ( string_from ( string_data . nr registry ) )
                } )
            }
            F → {}
        }
        = k + k 1
    }
    ^ out
}

// ── Fetched-index cache ───────────────────────────────────────────────
// status: 1 = parsed ok, 0 = not found (empty fetch), -1 = bad index.
: __IdxCache { String name i status RegIndex idx }

@ __empty_regindex → RegIndex {
    ^ @ RegIndex { ( string_new ) ( vec_new [IdxVersion] ) }
}

@ __cache_find ( Vec __IdxCache ) cache s name → i {
    : i n ( vec_len [__IdxCache] cache )
    : ~ i k 0
    ~ < k n {
        : ?__IdxCache o ( vec_get [__IdxCache] cache k )
        ?? o { T c → { ? != 0 ( nurl_str_eq ( string_data . c name ) name ) { ^ k } {} } F → {} }
        = k + k 1
    }
    ^ -1
}

// Ensure `name`'s index is cached; return its cache index. Fetches + parses
// on first request.
@ __cache_ensure ( Vec __IdxCache ) cache s name ( @ String s ) fetch → i {
    : i hit ( __cache_find cache name )
    ? >= hit 0 { ^ hit } {}
    : String json ( fetch name )
    ? == ( string_len json ) 0 {
        ( string_free json )
        ( vec_push [__IdxCache] cache @ __IdxCache { ( string_from name ) 0 ( __empty_regindex ) } )
        ^ - ( vec_len [__IdxCache] cache ) 1
    } {}
    : !RegIndex RegIndexErr ir ( regindex_parse ( string_data json ) )
    ( string_free json )
    ?? ir {
        T idx → ( vec_push [__IdxCache] cache @ __IdxCache { ( string_from name ) 1 idx } )
        F _ → ( vec_push [__IdxCache] cache @ __IdxCache { ( string_from name ) -1 ( __empty_regindex ) } )
    }
    ^ - ( vec_len [__IdxCache] cache ) 1
}

@ __cache_free ( Vec __IdxCache ) cache → v {
    : i n ( vec_len [__IdxCache] cache )
    : ~ i k 0
    ~ < k n {
        : ?__IdxCache o ( vec_get [__IdxCache] cache k )
        ?? o { T c → { ( string_free . c name ) ( regindex_free . c idx ) } F → {} }
        = k + k 1
    }
    ( vec_free [__IdxCache] cache )
}

// ── Version selection against a constraint set ────────────────────────

// True if `v` satisfies EVERY req in `reqs` (an unparseable req fails).
@ __matches_all ( Vec String ) reqs Semver v → b {
    : i n ( vec_len [String] reqs )
    : ~ i k 0
    : ~ b ok T
    ~ & ok < k n {
        : ?String so ( vec_get [String] reqs k )
        ?? so {
            T s → {
                : !VersionReq SemverErr rr ( semver_req_parse ( string_data s ) )
                ?? rr {
                    T r → { ? ! ( semver_req_matches r v ) { = ok F } {} ( semver_req_free r ) }
                    F → { = ok F }
                }
            }
            F → {}
        }
        = k + k 1
    }
    ^ ok
}

// Index of the highest non-yanked version satisfying ALL `reqs`, or -1.
@ __select_all RegIndex idx ( Vec String ) reqs → i {
    : ~ i best -1
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
                            ? ( __matches_all reqs cv ) {
                                ? < best 0 { = best k } {
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
    ^ best
}

// ── Constraint expansion from the current selection ───────────────────

// Raw version string locked for `name`, or `` if not selected.
@ __lock_version_of ( Vec LockPkg ) locked s name → s {
    : i n ( vec_len [LockPkg] locked )
    : ~ i k 0
    ~ < k n {
        : ?LockPkg o ( vec_get [LockPkg] locked k )
        ?? o { T p → { ? != 0 ( nurl_str_eq ( string_data . p name ) name ) { ^ ( string_data . p version ) } {} } F → {} }
        = k + k 1
    }
    ^ ``
}

// Add the deps of `idx`'s `ver` entry to `cs`, each inheriting `reg`.
@ __add_version_deps ( Vec __NameReq ) cs RegIndex idx s ver s reg → v {
    : i n ( vec_len [IdxVersion] . idx versions )
    : ~ i k 0
    ~ < k n {
        : ?IdxVersion vo ( vec_get [IdxVersion] . idx versions k )
        ?? vo {
            T iv → {
                ? != 0 ( nurl_str_eq ( string_data . iv version ) ver ) {
                    : i nd ( vec_len [IdxDep] . iv deps )
                    : ~ i j 0
                    ~ < j nd {
                        : ?IdxDep dopt ( vec_get [IdxDep] . iv deps j )
                        ?? dopt {
                            T dd → ( __nreq_add cs ( string_data . dd name ) ( string_data . dd req ) reg )
                            F → {}
                        }
                        = j + j 1
                    }
                } {}
            }
            F → {}
        }
        = k + k 1
    }
}

// Next round's constraints: the root set plus the deps of every currently
// selected version (each dep inheriting its parent's registry).
@ __expand_constraints ( Vec __NameReq ) rootcs ( Vec __NameReq ) cs ( Vec LockPkg ) locked ( Vec __IdxCache ) cache → ( Vec __NameReq ) {
    : ( Vec __NameReq ) out ( __nreqs_copy rootcs )
    : i n ( vec_len [__NameReq] cs )
    : ~ i k 0
    ~ < k n {
        : ?__NameReq o ( vec_get [__NameReq] cs k )
        ?? o {
            T nr → {
                : s nm ( string_data . nr name )
                : s reg ( string_data . nr registry )
                : s ver ( __lock_version_of locked nm )
                ? != 0 ( nurl_str_len ver ) {
                    : i ic ( __cache_find cache nm )
                    ? >= ic 0 {
                        : ?__IdxCache ico ( vec_get [__IdxCache] cache ic )
                        ?? ico {
                            T ce → { ? == . ce status 1 { ( __add_version_deps out . ce idx ver reg ) } {} }
                            F → {}
                        }
                    } {}
                } {}
            }
            F → {}
        }
        = k + k 1
    }
    ^ out
}

// Order-independent equality of two selections (name → version).
@ __lock_same ( Vec LockPkg ) a ( Vec LockPkg ) b → b {
    ? != ( vec_len [LockPkg] a ) ( vec_len [LockPkg] b ) { ^ F } {}
    : i n ( vec_len [LockPkg] a )
    : ~ i k 0
    : ~ b ok T
    ~ & ok < k n {
        : ?LockPkg o ( vec_get [LockPkg] a k )
        ?? o {
            T p → {
                : s bv ( __lock_version_of b ( string_data . p name ) )
                ? ! & != 0 ( nurl_str_len bv ) != 0 ( nurl_str_eq bv ( string_data . p version ) ) { = ok F } {}
            }
            F → {}
        }
        = k + k 1
    }
    ^ ok
}

@ resolve_registry ( Vec Dep ) roots s default_registry ( @ String s ) fetch → !( Vec LockPkg ) ResolveErr {
    : ( Vec __IdxCache ) cache ( vec_new [__IdxCache] )
    : ( Vec __NameReq ) rootcs ( vec_new [__NameReq] )

    // Seed the root registry requirements.
    : i nr ( vec_len [Dep] roots )
    : ~ i i 0
    ~ < i nr {
        : ?Dep dopt ( vec_get [Dep] roots i )
        ?? dopt {
            T d → {
                ? ( dep_is_registry d ) {
                    : s reg ? > ( string_len . d registry ) 0 ( string_data . d registry ) default_registry
                    ( __nreq_add rootcs ( string_data . d name ) ( string_data . d version ) reg )
                } {}
            }
            F → {}
        }
        = i + i 1
    }

    // Fixpoint: select against the accumulated constraints, rebuild the
    // constraints from the selection's deps, repeat until the selection is
    // stable. `round` bounds it against a pathological non-converging graph.
    : ~ ( Vec __NameReq ) cs ( __nreqs_copy rootcs )
    : ~ ( Vec LockPkg ) locked ( vec_new [LockPkg] )
    : ~ i failed 0
    : ~ ResolveErr ferr ResolveNotFound
    : ~ i round 0
    : ~ b done F
    ~ & ! done < round 256 {
        = round + round 1
        : ( Vec LockPkg ) newlocked ( vec_new [LockPkg] )
        : i cn ( vec_len [__NameReq] cs )
        : ~ i ci 0
        ~ & == failed 0 < ci cn {
            : ?__NameReq nro ( vec_get [__NameReq] cs ci )
            ?? nro {
                T nreq → {
                    : s nm ( string_data . nreq name )
                    : s reg ( string_data . nreq registry )
                    : i icx ( __cache_ensure cache nm fetch )
                    : ?__IdxCache ico ( vec_get [__IdxCache] cache icx )
                    ?? ico {
                        T ce → {
                            ? == . ce status 0 { = failed 1 = ferr ResolveNotFound } {
                                ? == . ce status -1 { = failed 1 = ferr ResolveBadIndex } {
                                    : i sel ( __select_all . ce idx . nreq reqs )
                                    ? < sel 0 {
                                        = failed 1
                                        = ferr ? > ( vec_len [String] . nreq reqs ) 1 ResolveConflict ResolveNoMatch
                                    } {
                                        : RegIndex cidx . ce idx
                                        : ?IdxVersion vopt ( vec_get [IdxVersion] . cidx versions sel )
                                        ?? vopt {
                                            T iv → ( vec_push [LockPkg] newlocked @ LockPkg {
                                                ( string_from nm )
                                                ( string_from ( string_data . iv version ) )
                                                ( __reg_source reg )
                                                ( string_from ( string_data . iv checksum ) )
                                            } )
                                            F → {}
                                        }
                                    }
                                }
                            }
                        }
                        F → {}
                    }
                    = ci + ci 1
                }
                F → {}
            }
        }

        ? != failed 0 {
            ( lockpkgs_free newlocked )
            = done T
        } {
            ? ( __lock_same newlocked locked ) {
                ( lockpkgs_free locked )
                = locked newlocked
                = done T
            } {
                : ( Vec __NameReq ) next_cs ( __expand_constraints rootcs cs newlocked cache )
                ( __nreqs_free cs )
                = cs next_cs
                ( lockpkgs_free locked )
                = locked newlocked
            }
        }
    }

    ( __nreqs_free cs )
    ( __nreqs_free rootcs )
    ( __cache_free cache )
    ? != failed 0 {
        ( lockpkgs_free locked )
        ^ @ !( Vec LockPkg ) ResolveErr { F ferr }
    } {}
    ^ @ !( Vec LockPkg ) ResolveErr { T locked }
}
