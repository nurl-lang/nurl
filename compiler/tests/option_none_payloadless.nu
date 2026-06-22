// Payload-less None construction: `@ ?T { F }` leaves the payload slot
// out of the literal entirely. gen_agg_lit seeds the aggregate with
// `zeroinitializer` (not `undef`), so the absent payload reads as a
// NULL handle — safe for every defensive runtime read (nurl_peek,
// string_free, vec_free are all NULL-safe no-ops) and allocation-free.
//
// Locks the fix for the None-placeholder leak class: 42 stdlib/tool
// sites used to write `@ ?String { F ( string_new ) }`, leaking the
// placeholder on every None (e.g. 4 Strings per HTTP request via
// header_get misses alone).
$ `stdlib/core/string.nu`

: Pt { i x i y }

@ none_str → ?String { ^ @ ?String { F } }

@ some_str → ?String { ^ @ ?String { T ( string_from `payload` ) } }

@ none_vec → ?( Vec u ) { ^ @ ?( Vec u ) { F } }

@ none_int → ?i { ^ @ ?i { F } }

@ none_struct → ?Pt { ^ @ ?Pt { F } }

// A None that crosses a call boundary, gets stored in a mutable
// binding, and is overwritten by a Some — the lifecycle header_get
// callers exercise.
@ main → i {
    : ?String a ( none_str )
    ?? a { T s → { ( string_free s ) ( nurl_print `BUG some\n` ) } F _ → { ( nurl_print `none str ok\n` ) } }

    : ?String b ( some_str )
    ?? b { T s → { ( nurl_print ( string_data s ) ) ( nurl_print `\n` ) ( string_free s ) } F _ → { ( nurl_print `BUG none\n` ) } }

    : ?( Vec u ) c ( none_vec )
    ?? c { T v → { ( vec_free [u] v ) ( nurl_print `BUG some vec\n` ) } F _ → { ( nurl_print `none vec ok\n` ) } }

    : ?i d ( none_int )
    ?? d { T n → { ( nurl_print ( nurl_str_int n ) ) } F _ → { ( nurl_print `none int ok\n` ) } }

    : ?Pt e ( none_struct )
    ?? e { T p → { ( nurl_print ( nurl_str_int . p x ) ) } F _ → { ( nurl_print `none struct ok\n` ) } }

    // Mutable option binding: starts None (payload-less), later Some.
    : ~ ? String m @ ?String { F }
    ?? m { T s → { ( string_free s ) ( nurl_print `BUG pre\n` ) } F _ → { ( nurl_print `mut none ok\n` ) } }
    = m @ ?String { T ( string_from `replaced` ) }
    ?? m { T s → { ( nurl_print ( string_data s ) ) ( nurl_print `\n` ) ( string_free s ) } F _ → { ( nurl_print `BUG post\n` ) } }

    ^ 0
}
