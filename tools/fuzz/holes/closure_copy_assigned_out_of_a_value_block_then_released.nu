// closure_copy_assigned_out_of_a_value_block_then_released: `: g { : String s … : f \ … s … = keep f  f }`, then `= keep ( mkn 2 )` and `( g 1 )` — the unblocked `= keep f  : g f` is refused.
// Closed: a value block's bindings are the enclosing scope's to the walk as they are to codegen — its `vblock` row ends their names at the `}`, not their lives, which end where the enclosing scope does (agora #846).
// (…and a `:` of a value block whose tail is a closure binding of the block borrows from that binding, as `: g f` does.)
// main 525613d: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.3 | A2 | rejected | - | agora #846, #638: a closure copy made in a value block, run after its owner is given a new value
$ `stdlib/core/string.nu`
$ `stdlib/core/io.nu`

@ mkn i n → ( @ i i ) { ^ \ i j → i { ^ + j n } }

@ main → i {
    : ~ ( @ i i ) keep ( mkn 1 )
    : ( @ i i ) g { : String s ( string_from `abcdefghijklmnopqrstuvwxyz` ) : ( @ i i ) f \ i j → i { ^ + j ( string_len s ) } = keep f f }
    = keep ( mkn 2 )
    ( nurl_println_int ( g 1 ) )
    ^ 0
}
