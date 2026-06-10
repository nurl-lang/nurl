// stdlib/ext/semver.nu — Semantic Versioning 2.0.0 + version requirements.
//
// Pure NURL. Two halves:
//
//   1. Versions — parse / compare / render a `MAJOR.MINOR.PATCH` with the
//      optional `-prerelease` and `+build` suffixes (semver.org §2, §9, §10),
//      with full precedence ordering including the prerelease rules (§11).
//
//   2. Requirements — parse a constraint (`^1.2.3`, `~1.2`, `>=1.0`,
//      `<2.0.0`, `=1.2.3`, `1.*`, `*`, or a bare `1.2.3`) into a half-open
//      range and test versions against it. `semver_req_max_satisfying`
//      picks the highest matching version — the resolution primitive the
//      registry-backed package manager needs (ROADMAP §4).
//
// Constraint dialect is **Cargo-shaped** (the package manager is
// cargo-shaped): a BARE `1.2.3` means `^1.2.3` (caret), not exact. Use
// `=1.2.3` for an exact pin.
//
// Surface:
//   ( semver_parse text )            → ! Semver SemverErr
//   ( semver_to_string v )           → String
//   ( semver_compare a b )           → i      (-1 / 0 / 1, build ignored)
//   ( semver_eq a b ) / _lt / _gt    → b
//   ( semver_free v )                → v
//   ( semver_req_parse text )        → ! VersionReq SemverErr
//   ( semver_req_matches r v )       → b
//   ( semver_req_max_satisfying r versions ) → ? Semver   (borrows; clones the winner)
//   ( semver_req_free r )            → v
//
// v1 simplification: requirement matching is pure precedence-based range
// containment. Cargo additionally constrains how prerelease versions match
// (a prerelease only satisfies a comparator that itself names a prerelease
// with the same core); we do not special-case that yet — a prerelease that
// falls inside the derived [lo, hi) range matches. Document a dependency on
// prerelease versions accordingly.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

// ── Types ─────────────────────────────────────────────────────────────

: Semver {
    i major
    i minor
    i patch
    String prerelease   // without the leading '-'; empty when absent
    String build        // without the leading '+'; empty when absent
}

: VersionReq {
    i has_lo
    Semver lo
    i lo_incl
    i has_hi
    Semver hi
    i hi_incl
}

: | SemverErr {
    SvEmpty         // empty input
    SvBadFormat     // structural garbage / extra core component
    SvMissingMinor  // core had no minor
    SvMissingPatch  // core had no patch
    SvBadNumber     // a numeric field was empty or non-numeric
    SvBadReq        // unparseable requirement operator / version
}

@ semver_err_name SemverErr e → s {
    ^ ?? e {
        SvEmpty → `SvEmpty`
        SvBadFormat → `SvBadFormat`
        SvMissingMinor → `SvMissingMinor`
        SvMissingPatch → `SvMissingPatch`
        SvBadNumber → `SvBadNumber`
        SvBadReq → `SvBadReq`
    }
}

@ semver_free Semver v → v {
    ( string_free . v prerelease )
    ( string_free . v build )
}

// Build a Semver with no prerelease / build (used for range bounds).
@ __sv_make i maj i min i pat → Semver {
    ^ @ Semver { maj min pat ( string_new ) ( string_new ) }
}

// ── Small scanning helpers (operate on raw `s`) ───────────────────────

// Index of byte `ch` in text[from, end), or -1.
@ __sv_index s text i from i end i ch → i {
    : ~ i k from
    ~ < k end {
        ? == ( nurl_str_get text k ) ch { ^ k } {}
        = k + k 1
    }
    ^ -1
}

// Copy text[from, to) into a fresh String.
@ __sv_substr s text i from i to → String {
    : String out ( string_new )
    : ~ i k from
    ~ < k to {
        ( string_push_char out ( nurl_str_get text k ) )
        = k + k 1
    }
    ^ out
}

// Parse text[from, to) as a non-negative decimal integer. Empty range or
// any non-digit → SvBadNumber.
@ __sv_parse_uint s text i from i to → !i SemverErr {
    ? >= from to { ^ @ !i SemverErr { F # SemverErr SvBadNumber } } {}
    : ~ i r 0
    : ~ i k from
    : ~ i bad 0
    ~ < k to {
        : i c ( nurl_str_get text k )
        ? & >= c 48 <= c 57 {
            = r + * r 10 - c 48
        } {
            = bad 1
            = k to
        }
        = k + k 1
    }
    ? != bad 0 { ^ @ !i SemverErr { F # SemverErr SvBadNumber } } {}
    ^ @ !i SemverErr { T r }
}

// ── Version parsing ───────────────────────────────────────────────────

@ semver_parse s text → !Semver SemverErr {
    : i n ( nurl_str_len text )
    ? == n 0 { ^ @ !Semver SemverErr { F # SemverErr SvEmpty } } {}

    // Split off +build first, then -prerelease, leaving the numeric core.
    : i plus ( __sv_index text 0 n 43 )        // '+'
    : i pr_end ? >= plus 0 plus n
    : i dash ( __sv_index text 0 pr_end 45 )   // '-' (prerelease) before build
    : i core_end ? >= dash 0 dash pr_end

    // Core: major.minor.patch
    : i d1 ( __sv_index text 0 core_end 46 )   // '.'
    ? < d1 0 { ^ @ !Semver SemverErr { F # SemverErr SvMissingMinor } } {}
    : i d2 ( __sv_index text + d1 1 core_end 46 )
    ? < d2 0 { ^ @ !Semver SemverErr { F # SemverErr SvMissingPatch } } {}

    : i major \ ( __sv_parse_uint text 0 d1 )
    : i minor \ ( __sv_parse_uint text + d1 1 d2 )
    : i patch \ ( __sv_parse_uint text + d2 1 core_end )

    : String pre ? >= dash 0 ( __sv_substr text + dash 1 pr_end ) ( string_new )
    : String bld ? >= plus 0 ( __sv_substr text + plus 1 n ) ( string_new )

    // A trailing '-' or '+' with nothing after it is malformed.
    ? & >= dash 0 == ( string_len pre ) 0 {
        ( string_free pre )
        ( string_free bld )
        ^ @ !Semver SemverErr { F # SemverErr SvBadFormat }
    } {}

    ^ @ !Semver SemverErr { T @ Semver { major minor patch pre bld } }
}

@ semver_to_string Semver v → String {
    : String out ( string_with_cap 24 )
    ( string_push_int out . v major )
    ( string_push_char out 46 )
    ( string_push_int out . v minor )
    ( string_push_char out 46 )
    ( string_push_int out . v patch )
    ? > ( string_len . v prerelease ) 0 {
        ( string_push_char out 45 )
        ( string_push_str out ( string_data . v prerelease ) )
    } {}
    ? > ( string_len . v build ) 0 {
        ( string_push_char out 43 )
        ( string_push_str out ( string_data . v build ) )
    } {}
    ^ out
}

@ semver_clone Semver v → Semver {
    ^ @ Semver {
        . v major . v minor . v patch
        ( string_from ( string_data . v prerelease ) )
        ( string_from ( string_data . v build ) )
    }
}

// ── Comparison ────────────────────────────────────────────────────────

@ __sv_all_digits s a → i {
    : i n ( nurl_str_len a )
    ? == n 0 { ^ 0 } {}
    : ~ i k 0
    ~ < k n {
        : i c ( nurl_str_get a k )
        ? | < c 48 > c 57 { ^ 0 } {}
        = k + k 1
    }
    ^ 1
}

@ __sv_to_int s a → i {
    : i n ( nurl_str_len a )
    : ~ i r 0
    : ~ i k 0
    ~ < k n {
        = r + * r 10 - ( nurl_str_get a k ) 48
        = k + k 1
    }
    ^ r
}

@ __sv_strcmp s a s b → i {
    : i an ( nurl_str_len a )
    : i bn ( nurl_str_len b )
    : i m ? < an bn an bn
    : ~ i k 0
    ~ < k m {
        : i ca ( nurl_str_get a k )
        : i cb ( nurl_str_get b k )
        ? < ca cb { ^ -1 } {}
        ? > ca cb { ^ 1 } {}
        = k + k 1
    }
    ? < an bn { ^ -1 } {}
    ? > an bn { ^ 1 } {}
    ^ 0
}

// Compare one prerelease identifier (semver §11.4.1-3): numeric < alpha;
// two numerics compare numerically; two alphas compare ASCII-lexically.
@ __sv_cmp_ident s a s b → i {
    : i an ( __sv_all_digits a )
    : i bn ( __sv_all_digits b )
    ? & != an 0 != bn 0 {
        : i av ( __sv_to_int a )
        : i bv ( __sv_to_int b )
        ? < av bv { ^ -1 } {}
        ? > av bv { ^ 1 } {}
        ^ 0
    } {}
    ? != an 0 { ^ -1 } {}    // numeric has lower precedence
    ? != bn 0 { ^ 1 } {}
    ^ ( __sv_strcmp a b )
}

// Compare two prerelease strings (without the leading '-'). A non-empty
// prerelease has LOWER precedence than an empty one (§11.3).
@ __sv_cmp_pre s a s b → i {
    : i ae ( nurl_str_len a )
    : i be ( nurl_str_len b )
    ? & == ae 0 == be 0 { ^ 0 } {}
    ? == ae 0 { ^ 1 } {}
    ? == be 0 { ^ -1 } {}

    : String sa ( string_from a )
    : String sb ( string_from b )
    : ( Vec String ) ia ( string_split sa `.` )
    : ( Vec String ) ib ( string_split sb `.` )
    : i na ( vec_len [String] ia )
    : i nb ( vec_len [String] ib )
    : i m ? < na nb na nb
    : ~ i res 0
    : ~ i k 0
    ~ & == res 0 < k m {
        : ?String xao ( vec_get [String] ia k )
        : ?String xbo ( vec_get [String] ib k )
        : s xa ?? xao { T s → ( string_data s ) F → `` }
        : s xb ?? xbo { T s → ( string_data s ) F → `` }
        = res ( __sv_cmp_ident xa xb )
        = k + k 1
    }
    ? == res 0 {
        ? < na nb { = res -1 } { ? > na nb { = res 1 } {} }
    } {}

    : i fa 0
    : ~ i kk 0
    ~ < kk na { : ?String t ( vec_get [String] ia kk ) ?? t { T s → ( string_free s ) F → {} } = kk + kk 1 }
    : ~ i jj 0
    ~ < jj nb { : ?String t ( vec_get [String] ib jj ) ?? t { T s → ( string_free s ) F → {} } = jj + jj 1 }
    ( vec_free [String] ia )
    ( vec_free [String] ib )
    ( string_free sa )
    ( string_free sb )
    ^ res
}

@ semver_compare Semver a Semver b → i {
    ? < . a major . b major { ^ -1 } {}
    ? > . a major . b major { ^ 1 } {}
    ? < . a minor . b minor { ^ -1 } {}
    ? > . a minor . b minor { ^ 1 } {}
    ? < . a patch . b patch { ^ -1 } {}
    ? > . a patch . b patch { ^ 1 } {}
    ^ ( __sv_cmp_pre ( string_data . a prerelease ) ( string_data . b prerelease ) )
}

@ semver_eq Semver a Semver b → b {
    ^ == ( semver_compare a b ) 0
}

@ semver_lt Semver a Semver b → b {
    ^ < ( semver_compare a b ) 0
}

@ semver_gt Semver a Semver b → b {
    ^ > ( semver_compare a b ) 0
}

// ── Requirement parsing ───────────────────────────────────────────────

// Parsed partial version `X[.Y[.Z]]` with optional trailing wildcard.
// `count` = numeric components before any wildcard (0 = "*").
: PartialVer {
    i major
    i minor
    i patch
    i count
}

@ __sv_is_wild i c → b {
    ^ | == c 42 | == c 120 == c 88    // '*' 'x' 'X'
}

// Parse a partial version starting at text[from, n). Returns a PartialVer;
// `count` 0 means a bare wildcard. Non-numeric, non-wildcard → count -1
// signals a parse error to the caller.
@ __sv_parse_partial s text i from i n → PartialVer {
    : ( Vec i ) parts ( vec_new [i] )
    : ~ i count 0
    : ~ i pos from
    : ~ i wild 0
    : ~ i err 0
    : ~ i more 1
    ~ & & == err 0 == wild 0 & == more 1 < pos n {
        : i dot ( __sv_index text pos n 46 )
        : i fieldend ? >= dot 0 dot n
        ? & == - fieldend pos 1 ( __sv_is_wild ( nurl_str_get text pos ) ) {
            = wild 1
        } {
            : !i SemverErr pv ( __sv_parse_uint text pos fieldend )
            ?? pv {
                T x → { ( vec_push [i] parts x ) = count + count 1 }
                F → { = err 1 }
            }
        }
        ? >= dot 0 { = pos + dot 1 } { = more 0 }
    }
    ? != err 0 {
        ( vec_free [i] parts )
        ^ @ PartialVer { 0 0 0 -1 }
    } {}
    : i p0 ?? ( vec_get [i] parts 0 ) { T x → x F → 0 }
    : i p1 ?? ( vec_get [i] parts 1 ) { T x → x F → 0 }
    : i p2 ?? ( vec_get [i] parts 2 ) { T x → x F → 0 }
    ( vec_free [i] parts )
    ^ @ PartialVer { p0 p1 p2 count }
}

// Caret upper bound (exclusive) for a partial of `count` numerics.
@ __sv_caret_hi PartialVer p → Semver {
    ? != . p major 0 { ^ ( __sv_make + . p major 1 0 0 ) } {}
    ? != . p minor 0 { ^ ( __sv_make 0 + . p minor 1 0 ) } {}
    ? >= . p count 3 { ^ ( __sv_make 0 0 + . p patch 1 ) } {}
    ? == . p count 2 { ^ ( __sv_make 0 1 0 ) } {}
    ^ ( __sv_make 1 0 0 )
}

// Tilde / wildcard upper bound: bump minor when >=2 components are pinned,
// else bump major.
@ __sv_tilde_hi PartialVer p → Semver {
    ? >= . p count 2 { ^ ( __sv_make . p major + . p minor 1 0 ) } {}
    ^ ( __sv_make + . p major 1 0 0 )
}

@ __sv_partial_lo PartialVer p → Semver {
    ^ ( __sv_make . p major . p minor . p patch )
}

@ __sv_any_req → VersionReq {
    ^ @ VersionReq { 0 ( __sv_make 0 0 0 ) 1 0 ( __sv_make 0 0 0 ) 0 }
}

@ semver_req_parse s text → !VersionReq SemverErr {
    : i n ( nurl_str_len text )
    // Skip leading spaces.
    : ~ i start 0
    ~ & < start n == ( nurl_str_get text start ) 32 { = start + start 1 }
    ? >= start n { ^ @ !VersionReq SemverErr { F # SemverErr SvBadReq } } {}

    : i c0 ( nurl_str_get text start )
    // Bare '*' (possibly with trailing spaces) → match anything.
    ? ( __sv_is_wild c0 ) {
        ^ @ !VersionReq SemverErr { T ( __sv_any_req ) }
    } {}

    // Operator prefix.
    : ~ i op 0          // 0 caret(default/bare/^), 1 ~, 2 =, 3 >, 4 >=, 5 <, 6 <=
    : ~ i vpos start
    ? == c0 94 { = op 0 = vpos + start 1 } {}                       // '^'
    ? == c0 126 { = op 1 = vpos + start 1 } {}                      // '~'
    ? == c0 61 { = op 2 = vpos + start 1 } {}                       // '='
    ? == c0 62 {
        ? & < + start 1 n == ( nurl_str_get text + start 1 ) 61 { = op 4 = vpos + start 2 } { = op 3 = vpos + start 1 }
    } {}                                                           // '>' / '>='
    ? == c0 60 {
        ? & < + start 1 n == ( nurl_str_get text + start 1 ) 61 { = op 6 = vpos + start 2 } { = op 5 = vpos + start 1 }
    } {}                                                           // '<' / '<='
    // Skip spaces after the operator.
    ~ & < vpos n == ( nurl_str_get text vpos ) 32 { = vpos + vpos 1 }

    : PartialVer p ( __sv_parse_partial text vpos n )
    ? < . p count 0 { ^ @ !VersionReq SemverErr { F # SemverErr SvBadReq } } {}
    // A bare wildcard reached here (e.g. "1.*") has count >= 1.
    ? == . p count 0 { ^ @ !VersionReq SemverErr { T ( __sv_any_req ) } } {}

    : Semver lo ( __sv_partial_lo p )

    // op 3/4 (> , >=): open upper bound.
    ? == op 3 { ^ @ !VersionReq SemverErr { T @ VersionReq { 1 lo 0 0 ( __sv_make 0 0 0 ) 0 } } } {}
    ? == op 4 { ^ @ !VersionReq SemverErr { T @ VersionReq { 1 lo 1 0 ( __sv_make 0 0 0 ) 0 } } } {}
    // op 5/6 (< , <=): open lower bound.
    ? == op 5 { ( semver_free lo ) ^ @ !VersionReq SemverErr { T @ VersionReq { 0 ( __sv_make 0 0 0 ) 1 1 ( __sv_partial_lo p ) 0 } } } {}
    ? == op 6 { ( semver_free lo ) ^ @ !VersionReq SemverErr { T @ VersionReq { 0 ( __sv_make 0 0 0 ) 1 1 ( __sv_partial_lo p ) 1 } } } {}

    // op 2 (=): exact when 3 components, else a partial range.
    ? == op 2 {
        ? >= . p count 3 {
            ^ @ !VersionReq SemverErr { T @ VersionReq { 1 lo 1 1 ( __sv_partial_lo p ) 1 } }
        } {}
        : Semver he ( __sv_tilde_hi p )
        ^ @ !VersionReq SemverErr { T @ VersionReq { 1 lo 1 1 he 0 } }
    } {}

    // op 1 (~): tilde range.
    ? == op 1 {
        : Semver ht ( __sv_tilde_hi p )
        ^ @ !VersionReq SemverErr { T @ VersionReq { 1 lo 1 1 ht 0 } }
    } {}

    // op 0 (caret / bare default).
    : Semver hc ( __sv_caret_hi p )
    ^ @ !VersionReq SemverErr { T @ VersionReq { 1 lo 1 1 hc 0 } }
}

@ semver_req_free VersionReq r → v {
    ( semver_free . r lo )
    ( semver_free . r hi )
}

@ semver_req_matches VersionReq r Semver v → b {
    ? != . r has_lo 0 {
        : i c ( semver_compare v . r lo )
        ? != . r lo_incl 0 {
            ? < c 0 { ^ F } {}
        } {
            ? <= c 0 { ^ F } {}
        }
    } {}
    ? != . r has_hi 0 {
        : i c ( semver_compare v . r hi )
        ? != . r hi_incl 0 {
            ? > c 0 { ^ F } {}
        } {
            ? >= c 0 { ^ F } {}
        }
    } {}
    ^ T
}

// Highest version in `versions` satisfying `r`, or None. Borrows the Vec
// and each element; the returned Semver is a fresh clone the caller owns.
@ semver_req_max_satisfying VersionReq r ( Vec Semver ) versions → ?Semver {
    : i n ( vec_len [Semver] versions )
    : ~ i best -1
    : ~ i k 0
    ~ < k n {
        : ?Semver vo ( vec_get [Semver] versions k )
        ?? vo {
            T v → {
                ? ( semver_req_matches r v ) {
                    ? < best 0 {
                        = best k
                    } {
                        : ?Semver bo ( vec_get [Semver] versions best )
                        ?? bo { T bv → { ? ( semver_gt v bv ) { = best k } {} } F → {} }
                    }
                } {}
            }
            F → {}
        }
        = k + k 1
    }
    ? < best 0 { ^ @ ?Semver { F } } {}
    : ?Semver wo ( vec_get [Semver] versions best )
    ?? wo {
        T w → ^ @ ?Semver { T ( semver_clone w ) }
        F → ^ @ ?Semver { F }
    }
}
