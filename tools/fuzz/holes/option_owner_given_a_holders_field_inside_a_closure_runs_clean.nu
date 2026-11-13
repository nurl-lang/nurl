// option_owner_given_a_holders_field_inside_a_closure_runs_clean: `= o ( geta h )` inside a closure, `h` a captured struct whose option field the call lends.
// Guard for agora #378: a lend out of another captured owner's field replaces o's value and leaves h's field to h.
// map: §7.6 | A2 | runs-clean | - | agora #378 guard: an owner given a captured holder's field inside a closure
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: H { ? String a i n }

@ geta H h → ?String { ^ . h a }

@ main → i {
    : ~ H h @ H { @ ?String { T ( string_from `the holder string, long enough for the heap allocation` ) } 1 }
    : ~ ? String o @ ?String { T ( string_from `the owner string, long enough for the heap allocation` ) }
    : ~ ( @ v ) f \ → v { = o ( geta h ) }
    ( f )
    ?? o { T s → { ( nurl_println ( string_data s ) ) } F → {} }
    ?? . h a { T s → { ( nurl_println ( string_data s ) ) } F → {} }
    ^ 0
}
