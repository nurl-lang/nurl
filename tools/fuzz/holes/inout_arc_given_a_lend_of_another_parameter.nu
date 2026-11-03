// inout_arc_given_a_lend_of_another_parameter: agora #456 — an `inout ( Arc String )` given `( ida other )`
// Closed: an `inout` or local owner of a library handle that is one pointer (a Box, an Rc or Arc control block, a map) given a call that may lend another value is told it by that pointer: a lend of another value is copied in (a Box or map deep, an Rc or Arc as a share) and the old value released; its own value stays (agora #456).
// main: heap-use-after-free (base 79e99d18).
// map: §7.6 | A2 | runs-clean | - | agora #456: an `inout ( Arc String )` given `( ida other )`
$ `stdlib/core/string.nu`
$ `stdlib/std/arc.nu`

@ make → String { ^ ( string_from `a fresh string long enough for the heap, one` ) }

@ make2 → String { ^ ( string_from `a fresh string long enough for the heap, two` ) }

@ ida ( Arc String ) r → ( Arc String ) { ^ r }

@ put inout ( Arc String ) o ( Arc String ) other → v { = o ( ida other ) }

@ main → i {
    : ~ ( Arc String ) a ( arc_new [String] ( make ) )
    : ( Arc String ) x ( arc_new [String] ( make2 ) )
    ( put a x )
    ( nurl_println `ran` )
    ^ 0
}
