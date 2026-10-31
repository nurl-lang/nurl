// value_block_tail_is_a_consumed_owner: agora #274 — a value block bound directly, `: String u { : i z 1 a }`, after `( consume a )`: its tail handed the freed `a` on (value_block_tail_is_a_consumed_owner).
// Closed: the tail's read on the block's `endblock` row, checked from the block's state.
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §2.1 | A1 | rejected | - | agora #274: a value block whose tail is an owner already consumed
$ `stdlib/core/string.nu`

@ consume sink String x → i { ^ ( string_len x ) }

@ main → i {
    : String a ( string_from `a heap string long enough to be on the heap` )
    : i n ( consume a )
    : String u { : i z 1 a }
    ^ + n ( string_len u )
}
