// inout_box_given_a_lend_of_another_parameter: agora #456 — `@ put inout ( Box String ) o ( Box String ) other → v { = o ( idbox other ) }`
// Closed: an `inout` or local owner of a library handle that is one pointer (a Box, an Rc or Arc control block, a map) given a call that may lend another value is told it by that pointer: a lend of another value is copied in (a Box or map deep, an Rc or Arc as a share) and the old value released; its own value stays (agora #456).
// main: heap-use-after-free (base 79e99d18).
// map: §7.6 | A2 | runs-clean | - | agora #456: `@ put inout ( Box String ) o ( Box String ) other → v { = o ( idbox other ) }`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/box.nu`

@ make → String { ^ ( string_from `a fresh string long enough for the heap, one` ) }

@ make2 → String { ^ ( string_from `a fresh string long enough for the heap, two` ) }

@ idbox ( Box String ) b → ( Box String ) { ^ b }

@ put inout ( Box String ) o ( Box String ) other → v { = o ( idbox other ) }

@ main → i {
    : ~ ( Box String ) a ( box_new [String] ( make ) )
    : ( Box String ) x ( box_new [String] ( make2 ) )
    ( put a x )
    ( nurl_println ( string_data ( box_get [String] a ) ) )
    ( nurl_println ( string_data ( box_get [String] x ) ) )
    ^ 0
}
