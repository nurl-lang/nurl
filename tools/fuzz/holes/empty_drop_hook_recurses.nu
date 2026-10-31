// empty_drop_hook_recurses: a library handle whose drop hook does nothing of its own (`@ H_drop sink H h → v {}`, the hook an Arc-backed handle needs) dropped its `sink` receiver at the end of the hook — through the handle's drop glue, which calls the hook again. At -O0 the recursion overflows the stack; at -O2 the tail calls become a loop and the program never ends.
// Closed: a drop hook is its receiver's destructor, so the receiver is not dropped again by it; the fields go afterwards by drop glue (an Arc field releases its share).
// main (before this PR): SEGV (stack overflow) at -O0, a hang at -O2.
// map: §7.6 | A2 | runs-clean | h190 | empty drop hook drops its sink receiver via drop glue, recursing forever
$ `stdlib/std/arc.nu`

: HImpl { i n }

: H { ( Arc HImpl ) a }

@ H_share H h → H { ^ @ H { ( arc_clone [HImpl] . h a ) } }

@ H_drop sink H h → v {}

@ main → i {
    : ~ i acc 0
    : ~ i k 0
    ~ < k 1000 {
        : H a @ H { ( arc_new [HImpl] @ HImpl { k } ) }
        : H b ( H_share a )
        = acc + acc . ( arc_get [HImpl] . b a ) n
        = k + k 1
    }
    ( nurl_println_int acc )
    ^ 0
}
