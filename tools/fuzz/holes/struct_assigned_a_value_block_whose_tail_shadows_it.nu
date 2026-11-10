// struct_assigned_a_value_block_whose_tail_shadows_it: `= p { : S p @ S { … } p }`, then `. p name` read.
// Closed: gen_assign resolves the target's drop registration before the right-hand side, as it does the target itself: a value block's own locals stay visible to the end of the statement, so one shadowing the name was taken for the target and its value released as the old one (agora #562).
// main b997834: accepted; AddressSanitizer: heap-use-after-free.
// map: §7.6 | A2 | runs-clean | - | agora #562: a struct assigned a value block whose tail is a block-local shadowing it
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: S { String name i n }

@ re inout ( Vec i ) v → v { = v { : ~ ( Vec i ) v ( vec_new [i] ) ( vec_push [i] v 5 ) v } }

@ main → i {
    : ~ S p @ S { ( string_from `an outer struct name long enough for the heap` ) 1 }
    = p { : S p @ S { ( string_from `an inner struct name long enough for the heap` ) 2 } p }
    ( nurl_println ( string_data . p name ) )
    ^ 0
}
