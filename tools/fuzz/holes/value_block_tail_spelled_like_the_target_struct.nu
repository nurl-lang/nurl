// value_block_tail_spelled_like_the_target_struct: `= s { : R s @ R { … }  s }` for a % Drop struct in a loop: the block-local was dropped at the block's end, then stored into s (agora #806).
// Closed: gen_assign hands a value block's tail that is a block-local spelled like the target over by its slot, under the name `|s`; the walk reads `|s` as the spelling the block's frame closed, and a block's end row names its tail before that frame closes (agora #806).
// main (before this PR): accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | runs-clean | - | agora #806: the same for a % Drop struct
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: R { String t i n }

% Drop R { @ drop R r → v { ( nurl_println_int . r n ) } }

@ eat sink String x → v { ( nurl_println ( string_data x ) ) }

@ main → i {
    : ~ R s @ R { ( string_from `outer string long enough for a heap buffer` ) 1 }
    : ~ i k 0
    ~ < k 2 { = s { : R s @ R { ( string_from `inner fresh string long enough for heap` ) + k 2 } s } = k + k 1 }
    ( nurl_println_int . s n )
    ^ 0
}
