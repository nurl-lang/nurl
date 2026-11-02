// enum_owner_given_a_part_of_itself_or_another_argument: agora #437 — `= o ( kid_or o other k )`: a part of o's old value on one run, another argument's value on the other
// Closed: where a lend may be a PART of the old value (the callee hands back more than whole parameters), a result that is not the old value itself is copied, so the old value goes by its flag and the binding owns its copy (agora #437).
// main: heap-use-after-free.
// map: §7.6 | A2 | runs-clean | - | agora #437: `= o ( kid_or o other k )`: a part of o's old value on one run, another argument's value on the other
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`

: | Tr {
    Leaf String
    Br ( Vec Tr )
}

@ kid_or Tr t Tr u i k → Tr {
    ? == k 1 { ^ u } {}
    ?? t {
        Br v → { ^ ( vec_at [Tr] v 0 ) }
        Leaf s → { ^ t }
    }
}

@ show Tr t → v {
    ?? t {
        Leaf s → { ( nurl_println ( string_data s ) ) }
        Br v → { ( nurl_println_int ( vec_len [Tr] v ) ) }
    }
}

@ run i k → v {
    : ( Vec Tr ) ks ( vec_new [Tr] )
    ( vec_push [Tr] ks @ Tr { Leaf ( string_from `the leaf string, long enough for the heap` ) } )
    : Tr other @ Tr { Leaf ( string_from `another leaf string, long enough for the heap` ) }
    : ~ Tr o @ Tr { Br ks }
    = o ( kid_or o other k )
    ( show o )
    ( show other )
}

@ main → i {
    ( run 0 )
    ( run 1 )
    ^ 0
}
