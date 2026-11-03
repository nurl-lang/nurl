// box_owner_given_itself_or_another_by_a_pick: agora #456 — a local `( Box String )` owner, `= o ( pick o x k )`, k 0 then 1
// Closed: an `inout` or local owner of a library handle that is one pointer (a Box, an Rc or Arc control block, a map) given a call that may lend another value is told it by that pointer: a lend of another value is copied in (a Box or map deep, an Rc or Arc as a share) and the old value released; its own value stays (agora #456).
// main: heap-use-after-free (base 79e99d18).
// map: §7.6 | A2 | runs-clean | - | agora #456: a local `( Box String )` owner, `= o ( pick o x k )`, k 0 then 1
$ `stdlib/core/string.nu`
$ `stdlib/core/box.nu`

@ pick ( Box String ) a ( Box String ) b i k → ( Box String ) { ? == k 0 { ^ a } {} ^ b }

@ run i k → v {
    : ~ ( Box String ) o ( box_new [String] ( string_from `a fresh string long enough for the heap, one` ) )
    : ( Box String ) x ( box_new [String] ( string_from `a fresh string long enough for the heap, two` ) )
    = o ( pick o x k )
    ( nurl_println ( string_data ( box_get [String] o ) ) )
    ( nurl_println ( string_data ( box_get [String] x ) ) )
}

@ main → i {
    ( run 0 )
    ( run 1 )
    ^ 0
}
