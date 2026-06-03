// semver_basic.nu — offline acceptance test for stdlib/ext/semver.nu.
//
// Coverage:
//   1. parse + to_string round-trip (core, prerelease, build).
//   2. precedence — the canonical semver.org §11 ordering, incl. the
//      prerelease rules (numeric < alphanumeric, fewer < more identifiers,
//      prerelease < release).
//   3. requirement ranges — ^, ~, =, >=, <, wildcard, bare (= caret).
//   4. semver_req_max_satisfying picks the highest matching version.
//   5. parse errors.

$ `stdlib/ext/semver.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ pb s label b v → v {
    ( nurl_print label )
    ? v { ( nurl_print `=T\n` ) } { ( nurl_print `=F\n` ) }
}

@ pi s label i v → v {
    ( nurl_print label )
    ( nurl_print_int v )
}

// cmp sign of two version strings, as -1/0/1.
@ cmp s a s b → i {
    : !Semver SemverErr ra ( semver_parse a )
    : !Semver SemverErr rb ( semver_parse b )
    : ~ i out 0
    ?? ra {
        T va → {
            ?? rb {
                T vb → { = out ( semver_compare va vb ) ( semver_free vb ) }
                F → {}
            }
            ( semver_free va )
        }
        F → {}
    }
    ^ out
}

// does version `vs` satisfy requirement `req`?
@ sat s req s vs → b {
    : !VersionReq SemverErr rr ( semver_req_parse req )
    : !Semver SemverErr rv ( semver_parse vs )
    : ~ b out F
    ?? rr {
        T r → {
            ?? rv {
                T v → { = out ( semver_req_matches r v ) ( semver_free v ) }
                F → {}
            }
            ( semver_req_free r )
        }
        F → {}
    }
    ^ out
}

@ main → i {
    // ── 1. parse + round-trip ────────────────────────────────────
    ( nurl_print `── round-trip ──\n` )
    : !Semver SemverErr r1 ( semver_parse `1.2.3-alpha.1+build.7` )
    ?? r1 {
        T v → {
            ( pi `major=` . v major ) ( nurl_print `\n` )
            ( pi `minor=` . v minor ) ( nurl_print `\n` )
            ( pi `patch=` . v patch ) ( nurl_print `\n` )
            ( nurl_print `pre=` ) ( nurl_print ( string_data . v prerelease ) ) ( nurl_print `\n` )
            ( nurl_print `build=` ) ( nurl_print ( string_data . v build ) ) ( nurl_print `\n` )
            : String s ( semver_to_string v )
            ( nurl_print `render=` ) ( nurl_print ( string_data s ) ) ( nurl_print `\n` )
            ( string_free s )
            ( semver_free v )
        }
        F e → ( nurl_print ( semver_err_name e ) )
    }

    // ── 2. precedence (semver.org §11) ───────────────────────────
    ( nurl_print `── precedence ──\n` )
    ( pi `c_1.0.0_lt_2.0.0=` ( cmp `1.0.0` `2.0.0` ) ) ( nurl_print `\n` )
    ( pi `c_2.1.0_lt_2.1.1=` ( cmp `2.1.0` `2.1.1` ) ) ( nurl_print `\n` )
    ( pi `c_eq=` ( cmp `1.2.3` `1.2.3` ) ) ( nurl_print `\n` )
    ( pi `c_pre_lt_release=` ( cmp `1.0.0-alpha` `1.0.0` ) ) ( nurl_print `\n` )
    ( pi `c_alpha_lt_alpha.1=` ( cmp `1.0.0-alpha` `1.0.0-alpha.1` ) ) ( nurl_print `\n` )
    ( pi `c_alpha.1_lt_alpha.beta=` ( cmp `1.0.0-alpha.1` `1.0.0-alpha.beta` ) ) ( nurl_print `\n` )
    ( pi `c_beta.2_lt_beta.11=` ( cmp `1.0.0-beta.2` `1.0.0-beta.11` ) ) ( nurl_print `\n` )
    ( pi `c_rc.1_lt_release=` ( cmp `1.0.0-rc.1` `1.0.0` ) ) ( nurl_print `\n` )
    ( pi `c_build_ignored=` ( cmp `1.0.0+a` `1.0.0+b` ) ) ( nurl_print `\n` )

    // ── 3. requirement ranges ────────────────────────────────────
    ( nurl_print `── ranges ──\n` )
    ( pb `caret_1.2.3__1.2.3` ( sat `^1.2.3` `1.2.3` ) )
    ( pb `caret_1.2.3__1.9.9` ( sat `^1.2.3` `1.9.9` ) )
    ( pb `caret_1.2.3__2.0.0` ( sat `^1.2.3` `2.0.0` ) )
    ( pb `caret_1.2.3__1.2.2` ( sat `^1.2.3` `1.2.2` ) )
    ( pb `caret_0.2.3__0.2.9` ( sat `^0.2.3` `0.2.9` ) )
    ( pb `caret_0.2.3__0.3.0` ( sat `^0.2.3` `0.3.0` ) )
    ( pb `tilde_1.2.3__1.2.9` ( sat `~1.2.3` `1.2.9` ) )
    ( pb `tilde_1.2.3__1.3.0` ( sat `~1.2.3` `1.3.0` ) )
    ( pb `exact_1.2.3__1.2.3` ( sat `=1.2.3` `1.2.3` ) )
    ( pb `exact_1.2.3__1.2.4` ( sat `=1.2.3` `1.2.4` ) )
    ( pb `gte_1.0.0__1.0.0` ( sat `>=1.0.0` `1.0.0` ) )
    ( pb `gt_1.0.0__1.0.0` ( sat `>1.0.0` `1.0.0` ) )
    ( pb `lt_2.0.0__1.9.9` ( sat `<2.0.0` `1.9.9` ) )
    ( pb `lt_2.0.0__2.0.0` ( sat `<2.0.0` `2.0.0` ) )
    ( pb `wild_1star__1.5.0` ( sat `1.*` `1.5.0` ) )
    ( pb `wild_1star__2.0.0` ( sat `1.*` `2.0.0` ) )
    ( pb `any__9.9.9` ( sat `*` `9.9.9` ) )
    ( pb `bare_1.2.3__1.8.0` ( sat `1.2.3` `1.8.0` ) )
    ( pb `bare_1.2.3__2.0.0` ( sat `1.2.3` `2.0.0` ) )

    // ── 4. max_satisfying ────────────────────────────────────────
    ( nurl_print `── max_satisfying ──\n` )
    : ( Vec Semver ) vs ( vec_new [Semver] )
    : !Semver SemverErr a ( semver_parse `1.2.0` )  ?? a { T x → ( vec_push [Semver] vs x ) F → {} }
    : !Semver SemverErr b ( semver_parse `1.4.2` )  ?? b { T x → ( vec_push [Semver] vs x ) F → {} }
    : !Semver SemverErr c ( semver_parse `1.4.9` )  ?? c { T x → ( vec_push [Semver] vs x ) F → {} }
    : !Semver SemverErr d ( semver_parse `2.0.0` )  ?? d { T x → ( vec_push [Semver] vs x ) F → {} }
    : !VersionReq SemverErr rq ( semver_req_parse `^1.2.0` )
    ?? rq {
        T r → {
            : ?Semver best ( semver_req_max_satisfying r vs )
            ?? best {
                T w → {
                    : String ws ( semver_to_string w )
                    ( nurl_print `max_caret_1.2.0=` ) ( nurl_print ( string_data ws ) ) ( nurl_print `\n` )
                    ( string_free ws )
                    ( semver_free w )
                }
                F → ( nurl_print `max=none\n` )
            }
            ( semver_req_free r )
        }
        F → {}
    }
    : i nvs ( vec_len [Semver] vs )
    : ~ i fk 0
    ~ < fk nvs { : ?Semver t ( vec_get [Semver] vs fk ) ?? t { T x → ( semver_free x ) F → {} } = fk + fk 1 }
    ( vec_free [Semver] vs )

    // ── 5. parse errors ──────────────────────────────────────────
    ( nurl_print `── errors ──\n` )
    : !Semver SemverErr e1 ( semver_parse `` )
    ?? e1 { T x → { ( nurl_print `empty=OK(bug)\n` ) ( semver_free x ) } F er → { ( nurl_print `empty=` ) ( nurl_print ( semver_err_name er ) ) ( nurl_print `\n` ) } }
    : !Semver SemverErr e2 ( semver_parse `1` )
    ?? e2 { T x → { ( nurl_print `one=OK(bug)\n` ) ( semver_free x ) } F er → { ( nurl_print `one=` ) ( nurl_print ( semver_err_name er ) ) ( nurl_print `\n` ) } }
    : !Semver SemverErr e3 ( semver_parse `1.2` )
    ?? e3 { T x → { ( nurl_print `two=OK(bug)\n` ) ( semver_free x ) } F er → { ( nurl_print `two=` ) ( nurl_print ( semver_err_name er ) ) ( nurl_print `\n` ) } }
    : !Semver SemverErr e4 ( semver_parse `1.x.0` )
    ?? e4 { T x → { ( nurl_print `xcore=OK(bug)\n` ) ( semver_free x ) } F er → { ( nurl_print `xcore=` ) ( nurl_print ( semver_err_name er ) ) ( nurl_print `\n` ) } }
    ( nurl_print `done\n` )
    ^ 0
}
