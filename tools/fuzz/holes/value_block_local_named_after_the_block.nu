// value_block_local_named_after_the_block: `: String e { : String s … s }`, `( eat e )`, then `s` read, with no outer `s`.
// Closed: refused. A value block's names end at its `}` (agora #575). What the block bound lives on to the end of the enclosing scope — the block's value may view it — but it cannot be named there: the walk ends a block's names at the `}`, code generation kept them, so the read was checked as nothing and compiled as the block's `s`, which the sink had released.
// main 2498b4e: accepted; AddressSanitizer: heap-use-after-free.
// map: §7.6 | A2 | rejected | - | agora #575: a value block's local named after the block
$ `stdlib/core/string.nu`

@ eat sink String x → i { ^ ( string_len x ) }

@ main → i {
    : String e { : String s ( string_from `inner string long enough for a heap buffer` ) s }
    ( nurl_println_int ( eat e ) )
    ( nurl_println ( string_data s ) )
    ^ 0
}
