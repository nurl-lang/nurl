// let_of_a_value_block_whose_tail_call_takes_a_block_local_owns_the_result: `: String e { : String s … ( string_concat s s ) }`, straight and in a loop body, and through a user function.
// Closed: the binding takes the tail call's own answer on the runs the call lent it nothing (mem_blk_tail_call_own). A tail call that takes one of the block's own bindings kept the binding a block, whose drop flag starts as "a borrow"; only the runs the call lent a block binding (copied) turned it on, so a fresh result was never dropped (agora #613).
// main 2498b4e: accepted; LeakSanitizer: string_concat's result, once per run of the statement.
// map: §7.6 | A2 | runs-clean | - | agora #613: a `:` binding of a value block whose tail call takes a block local and returns a value of its own
$ `stdlib/core/string.nu`

@ twice String a → String { ^ ( string_concat a a ) }

@ main → i {
    : String e { : String s ( string_from `inner string long enough for a heap buffer aaaa` ) ( string_concat s s ) }
    : String g { : String s ( string_from `inner string long enough for a heap buffer bbbb` ) ( twice s ) }
    : ~ i total + ( string_len e ) ( string_len g )
    : ~ i k 0
    ~ < k 3 {
        : String l { : String s ( string_from `loop inner string long enough for a heap buffer` ) ( string_concat s ( string_from `!` ) ) }
        = total + total ( string_len l )
        = k + k 1
    }
    ( nurl_println_int total )
    ^ 0
}
