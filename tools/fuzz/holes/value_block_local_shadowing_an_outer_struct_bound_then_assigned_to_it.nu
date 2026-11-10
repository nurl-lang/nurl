// value_block_local_shadowing_an_outer_struct_bound_then_assigned_to_it: `: P __el { : P p @ P { … } p }`, then `= p __el`, with an outer `p`.
// Closed: refused, as the String form is: `p` after the block still reaches the block's binding, which would be given its own value back after releasing it (agora #575).
// main 2498b4e: accepted; AddressSanitizer: heap-use-after-free.
// map: §7.6 | A2 | rejected | - | agora #575: a value block's local shadowing an outer struct, its value bound and then assigned to that outer struct
$ `stdlib/core/string.nu`

: P { String name i n }

@ main → i {
    : ~ P p @ P { ( string_from `outer struct name long enough for heap` ) 1 }
    : P __el { : P p @ P { ( string_from `inner struct name long enough for heap` ) 2 } p }
    = p __el
    ( nurl_println ( string_data . p name ) )
    ^ 0
}
