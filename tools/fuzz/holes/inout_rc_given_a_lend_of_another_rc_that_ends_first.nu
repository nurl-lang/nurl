// inout_rc_given_a_lend_of_another_rc_that_ends_first: agora #456 — an `inout ( Rc String )` given another Rc that ends in a block before the caller reads its own
// Closed: an `inout` or local owner of a library handle that is one pointer (a Box, an Rc or Arc control block, a map) given a call that may lend another value is told it by that pointer: a lend of another value is copied in (a Box or map deep, an Rc or Arc as a share) and the old value released; its own value stays (agora #456).
// main: heap-use-after-free (base 79e99d18).
// map: §7.6 | A2 | runs-clean | - | agora #456: an `inout ( Rc String )` given another Rc that ends in a block before the caller reads its own
$ `stdlib/core/string.nu`
$ `stdlib/std/rc.nu`

@ idr ( Rc String ) r → ( Rc String ) { ^ r }

@ put inout ( Rc String ) o ( Rc String ) other → v { = o ( idr other ) }

@ main → i {
    : ~ ( Rc String ) a ( rc_new [String] ( string_from `a fresh string long enough for the heap, one` ) )
    {
        : ( Rc String ) x ( rc_new [String] ( string_from `a fresh string long enough for the heap, two` ) )
        ( put a x )
    }
    ( nurl_println ( string_data ( rc_get [String] a ) ) )
    ^ 0
}
