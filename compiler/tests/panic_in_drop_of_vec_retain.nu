// panic_in_drop_of_vec_retain.nu — `vec_retain` over elements whose
// destructor, or whose predicate, panics (Agora #624; formal/CLAIM.md, the
// drain).
//
// vec_retain judges every element first and drops the ones that go after
// that, the Vec already short: a destructor that panics leaves a Vec of
// exactly the kept elements, and the others still to go are dropped all
// the same, once each. Before, each one that went was dropped inside the
// loop, the Vec still at its old length: the panic's drain dropped the Vec
// over slots already given up (a null read in the destructor, a double
// free).
//
// While the predicate runs the Vec holds every element once, the kept ones
// so far in front: a predicate that panics leaves a Vec the drain can
// drop, and one a `recover` of its own can go on with. Before, the slots
// between the kept ones and the one being judged were given up or stale.
//
// `kind`: 0 goes, 1 stays, 2 goes and its destructor panics, 3 the
// predicate panics on it.

$ `stdlib/std/panic.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: ~ i g_drops 0

: ~ i g_ids 0

: ~ b g_quiet F

: Bomb { String tag i id i kind }

% Drop Bomb {
    @ drop Bomb b → v {
        = g_drops + g_drops 1
        = g_ids + g_ids . b id
        ? ! g_quiet { ( nurl_println ( nurl_str_cat `drop ` ( string_data . b tag ) ) ) } {}
        ? == . b kind 2 { ( panic ( nurl_str_cat `panic in drop ` ( string_data . b tag ) ) ) } {}
    }
}

@ add ( Vec Bomb ) v s tag i kind → v {
    ( vec_push [Bomb] v @ Bomb { ( string_from tag ) ( vec_len [Bomb] v ) kind } )
}

@ stays Bomb x → b {
    ? == . x kind 3 { ( panic ( nurl_str_cat `panic judging ` ( string_data . x tag ) ) ) } {}
    ^ == . x kind 1
}

@ tags ( Vec Bomb ) v → String {
    : ~ String out ( string_from `[` )
    : ~ i k 0
    ~ < k ( vec_len [Bomb] v ) {
        ? > k 0 { ( string_push_str out ` ` ) } {}
        ( string_push_str out ( string_data . ( vec_at [Bomb] v k ) tag ) )
        = k + k 1
    }
    ( string_push_str out `]` )
    ^ out
}

// Every element goes, and the third one's destructor panics: the fourth
// is still dropped, and the Vec the drain then drops is empty.
@ whole → v {
    : ~ ( Vec Bomb ) v ( vec_new [Bomb] )
    ( add v `r0` 0 )
    ( add v `r1` 0 )
    ( add v `r2` 2 )
    ( add v `r3` 0 )
    ( vec_retain [Bomb] v \ Bomb x → b { ^ ( stays x ) } )
    ( nurl_println `whole: not reached` )
}

// Two of the ones that go panic: the second inside the first one's drain.
// The kept ones are the Vec's, dropped with it once the others are gone.
@ two_bombs → v {
    : ~ ( Vec Bomb ) v ( vec_new [Bomb] )
    ( add v `k0` 1 )
    ( add v `k1` 1 )
    ( add v `r2` 2 )
    ( add v `r3` 2 )
    ( add v `r4` 0 )
    ( vec_retain [Bomb] v \ Bomb x → b { ^ ( stays x ) } )
    ( nurl_println `two_bombs: not reached` )
}

// The predicate panics on the fourth: nothing has been dropped, and the
// drain drops all five, once each.
@ judged → v {
    : ~ ( Vec Bomb ) v ( vec_new [Bomb] )
    ( add v `k0` 1 )
    ( add v `k1` 1 )
    ( add v `r2` 0 )
    ( add v `p3` 3 )
    ( add v `k4` 1 )
    ( vec_retain [Bomb] v \ Bomb x → b { ^ ( stays x ) } )
    ( nurl_println `judged: not reached` )
}

// A retain that panics inside a `recover` of its own leaves exactly the
// kept elements, in order, in a Vec the caller goes on with.
@ survives → v {
    : ~ ( Vec Bomb ) v ( vec_new [Bomb] )
    ( add v `k0` 1 )
    ( add v `r1` 2 )
    ( add v `k2` 1 )
    ( add v `k3` 1 )
    ( add v `r4` 0 )
    : !v PanicInfo r ( recover \ → v { ( vec_retain [Bomb] v \ Bomb x → b { ^ ( stays x ) } ) } )
    ?? r {
        T _ → { ( puts `no panic` ) }
        F e → { ( nurl_println ( nurl_str_cat `survives: recovered: ` ( string_data . e msg ) ) ) }
    }
    : String kept ( tags v )
    ( nurl_println ( nurl_str_cat `survives: kept ` ( string_data kept ) ) )
    ( add v `late` 1 )
    ( vec_retain [Bomb] v \ Bomb x → b { ^ != . x id 0 } )
    : String rest ( tags v )
    ( nurl_println ( nurl_str_cat `survives: then ` ( string_data rest ) ) )
}

// …and so does one whose predicate panics, with every element in it: the
// kept ones so far in front, the rest behind them, each dropped once at
// the end.
@ judged_survives → v {
    : ~ ( Vec Bomb ) v ( vec_new [Bomb] )
    ( add v `k0` 1 )
    ( add v `r1` 0 )
    ( add v `k2` 1 )
    ( add v `p3` 3 )
    ( add v `k4` 1 )
    ( add v `r5` 0 )
    : !v PanicInfo r ( recover \ → v { ( vec_retain [Bomb] v \ Bomb x → b { ^ ( stays x ) } ) } )
    ?? r {
        T _ → { ( puts `no panic` ) }
        F e → { ( nurl_println ( nurl_str_cat `judged_survives: recovered: ` ( string_data . e msg ) ) ) }
    }
    : String all ( tags v )
    ( nurl_println ( nurl_str_cat `judged_survives: holds ` ( string_data all ) ) )
}

// No panic: what a retain always did. The kept ones stay in order; the
// ones that go are dropped once each — counted, not printed: they are
// dropped in no order of their own (ids 0, 2, 3 and 6).
@ quiet → v {
    : ~ ( Vec Bomb ) v ( vec_new [Bomb] )
    ( add v `r0` 0 )
    ( add v `k1` 1 )
    ( add v `r2` 0 )
    ( add v `r3` 0 )
    ( add v `k4` 1 )
    ( add v `k5` 1 )
    ( add v `r6` 0 )
    = g_drops 0
    = g_ids 0
    = g_quiet T
    ( vec_retain [Bomb] v \ Bomb x → b { ^ ( stays x ) } )
    = g_quiet F
    ( nurl_println ( nurl_str_cat3 `quiet: dropped ` ( nurl_str_int g_drops ) ( nurl_str_cat ` ids ` ( nurl_str_int g_ids ) ) ) )
    : String kept ( tags v )
    ( nurl_println ( nurl_str_cat `quiet: kept ` ( string_data kept ) ) )
}

@ ints_str ( Vec i ) v → String {
    : ~ String out ( string_from `[` )
    : ~ i k 0
    ~ < k ( vec_len [i] v ) {
        ? > k 0 { ( string_push_str out ` ` ) } {}
        ( string_push_str out ( nurl_str_int ( vec_at [i] v k ) ) )
        = k + k 1
    }
    ( string_push_str out `]` )
    ^ out
}

// Elements that own nothing, and ones that own without a destructor.
@ plain → v {
    : ~ ( Vec i ) v ( vec_iota 0 10 )
    ( vec_retain [i] v \ i x → b { ^ != % x 3 0 } )
    : String a ( ints_str v )
    ( nurl_println ( nurl_str_cat `plain: ` ( string_data a ) ) )
    ( vec_retain [i] v \ i x → b { ^ T } )
    ( nurl_println ( nurl_str_cat `plain: all stay, len ` ( nurl_str_int ( vec_len [i] v ) ) ) )
    ( vec_retain [i] v \ i x → b { ^ > x 7 } )
    : String c ( ints_str v )
    ( nurl_println ( nurl_str_cat `plain: ` ( string_data c ) ) )
    ( vec_retain [i] v \ i x → b { ^ F } )
    ( nurl_println ( nurl_str_cat `plain: none stay, len ` ( nurl_str_int ( vec_len [i] v ) ) ) )
    ( vec_retain [i] v \ i x → b { ^ T } )
    ( nurl_println ( nurl_str_cat `plain: empty, len ` ( nurl_str_int ( vec_len [i] v ) ) ) )
    : ~ ( Vec String ) w ( vec_new [String] )
    ( vec_push [String] w ( string_from `one` ) )
    ( vec_push [String] w ( string_from `two` ) )
    ( vec_push [String] w ( string_from `three` ) )
    ( vec_push [String] w ( string_from `four` ) )
    ( vec_push [String] w ( string_from `five` ) )
    ( vec_retain [String] w \ String x → b { ^ == ( string_len x ) 4 } )
    ( nurl_println ( nurl_str_cat3 `plain: ` ( string_data ( vec_at [String] w 0 ) ) ( nurl_str_cat ` ` ( string_data ( vec_at [String] w 1 ) ) ) ) )
    ( nurl_println ( nurl_str_cat `plain: strings, len ` ( nurl_str_int ( vec_len [String] w ) ) ) )
}

@ run s name ( @ v ) f → v {
    : !v PanicInfo r ( recover f )
    ?? r {
        T _ → { ( nurl_println ( nurl_str_cat name `: no panic` ) ) }
        F e → { ( nurl_println ( nurl_str_cat3 name `: recovered: ` ( string_data . e msg ) ) ) }
    }
}

@ main → i {
    ( run `whole` \ → v { ( whole ) } )
    ( run `two_bombs` \ → v { ( two_bombs ) } )
    ( run `judged` \ → v { ( judged ) } )
    ( survives )
    ( judged_survives )
    ( quiet )
    ( plain )
    ^ 0
}
