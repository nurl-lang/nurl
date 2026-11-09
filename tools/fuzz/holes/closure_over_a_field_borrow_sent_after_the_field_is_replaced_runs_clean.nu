// closure_over_a_field_borrow_sent_after_the_field_is_replaced_runs_clean: agora #483 — a closure over a field borrow (`: String n . p name`) is handed to a thread after the struct's field was given a new value: the borrow took the old value over
// The shape the fix must keep: a field's viewer that takes its old value over holds what the closure's copy names (agora #483).
// main 21a0fb5: runs clean.
// map: §2.11 | A2 | runs-clean | - | agora #483: a closure over a field borrow sent after the field is replaced
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/thread.nu`

: P { String name i n }

@ main → i {
    : ~ P p @ P { ( string_from `the first name, long enough for the heap` ) 1 }
    : String n . p name
    : ( @ v ) body \ → v { ( nurl_println ( string_data n ) ) }
    = . p name ( string_from `a second name, long enough for the heap too` )
    ?? ( thread_spawn body ) { T th → { ( thread_join th ) } F _ → {} }
    ^ 0
}
