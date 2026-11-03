// inout_hashmap_given_a_lend_of_another_parameter: agora #456 — an `inout ( HashMap … )` given `( idm other )`
// Closed: an `inout` or local owner of a library handle that is one pointer (a Box, an Rc or Arc control block, a map) given a call that may lend another value is told it by that pointer: a lend of another value is copied in (a Box or map deep, an Rc or Arc as a share) and the old value released; its own value stays (agora #456).
// main: heap-use-after-free (base 79e99d18).
// map: §7.6 | A2 | runs-clean | - | agora #456: an `inout ( HashMap … )` given `( idm other )`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/box.nu`

@ make → String { ^ ( string_from `a fresh string long enough for the heap, one` ) }

@ make2 → String { ^ ( string_from `a fresh string long enough for the heap, two` ) }

$ `stdlib/std/hashmap.nu`

@ idm ( HashMap i i ) m → ( HashMap i i ) { ^ m }

@ put inout ( HashMap i i ) o ( HashMap i i ) other → v { = o ( idm other ) }

@ main → i {
    : ~ ( HashMap i i ) a ( map_new [i i] )
    : ( HashMap i i ) x ( map_new [i i] )
    ( put a x )
    ( nurl_println_int ( map_len [i i] a ) )
    ( nurl_println_int ( map_len [i i] x ) )
    ^ 0
}
