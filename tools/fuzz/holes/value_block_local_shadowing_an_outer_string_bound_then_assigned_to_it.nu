// value_block_local_shadowing_an_outer_string_bound_then_assigned_to_it: `: String __el { : String s … s }`, then `= s __el`, with an outer `s`.
// Closed: refused. A value block's names end at its `}`, while what the block bound lives on to the end of the enclosing scope under its name: `= s __el` reached the block's own binding, gave it its own value back after releasing it, and the read after it was freed memory. A name spelled after the block that still reaches the block's binding is refused, and the message says to give the block's binding another name (agora #575).
// main 2498b4e: accepted; AddressSanitizer: heap-use-after-free.
// map: §7.6 | A2 | rejected | - | agora #575: a value block's local shadowing an outer String, its value bound and then assigned to that outer String
$ `stdlib/core/string.nu`

@ main → i {
    : ~ String s ( string_from `outer string long enough for a heap buffer` )
    : String __el { : String s ( string_from `inner string long enough for a heap buffer` ) s }
    = s __el
    ( nurl_println ( string_data s ) )
    ^ 0
}
