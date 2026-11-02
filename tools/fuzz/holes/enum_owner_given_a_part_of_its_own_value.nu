// enum_owner_given_a_part_of_its_own_value: agora #437 — `= o ( kid o )`, kid handing back `( vec_at v 0 )` out of o's own Br: a part of the old value
// Closed: where a lend may be a PART of the old value (the callee hands back more than whole parameters), a result that is not the old value itself is copied, so the old value goes by its flag and the binding owns its copy (agora #437).
// main: heap-use-after-free since github#1537 (its parent leaked).
// map: §7.6 | A2 | runs-clean | - | agora #437: `= o ( kid o )`, kid handing back `( vec_at v 0 )` out of o's own Br: a part of the old value
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`

: | Tr {
    Leaf String
    Br ( Vec Tr )
}

@ kid Tr t → Tr {
    ?? t {
        Br v → { ^ ( vec_at [Tr] v 0 ) }
        Leaf s → { ^ t }
    }
}

@ main → i {
    : ( Vec Tr ) ks ( vec_new [Tr] )
    ( vec_push [Tr] ks @ Tr { Leaf ( string_from `the leaf string, long enough for the heap` ) } )
    : ~ Tr o @ Tr { Br ks }
    = o ( kid o )
    ?? o {
        Leaf s → { ( nurl_println ( string_data s ) ) }
        Br v → { ( nurl_println_int ( vec_len [Tr] v ) ) }
    }
    ^ 0
}
