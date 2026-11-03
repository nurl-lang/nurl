// inout_box_given_itself_or_another_by_a_pick: agora #456 — `= o ( pick o other k )` over an `inout ( Box String )`, k 0, 1, 0
// Closed: an `inout` or local owner of a library handle that is one pointer (a Box, an Rc or Arc control block, a map) given a call that may lend another value is told it by that pointer: a lend of another value is copied in (a Box or map deep, an Rc or Arc as a share) and the old value released; its own value stays (agora #456).
// main: heap-use-after-free (base 79e99d18).
// map: §7.6 | A2 | runs-clean | - | agora #456: `= o ( pick o other k )` over an `inout ( Box String )`, k 0, 1, 0
$ `stdlib/core/string.nu`
$ `stdlib/core/box.nu`

@ pick ( Box String ) a ( Box String ) b i k → ( Box String ) { ? == k 0 { ^ a } {} ^ b }

@ put inout ( Box String ) o ( Box String ) other i k → v { = o ( pick o other k ) }

@ main → i {
    : ~ ( Box String ) a ( box_new [String] ( string_from `a fresh string long enough for the heap, one` ) )
    : ( Box String ) x ( box_new [String] ( string_from `a fresh string long enough for the heap, two` ) )
    ( put a x 0 )
    ( put a x 1 )
    ( put a x 0 )
    ( nurl_println ( string_data ( box_get [String] a ) ) )
    ( nurl_println ( string_data ( box_get [String] x ) ) )
    ^ 0
}
