// value_block_vec_tail_named_like_its_binding_handed_to_a_sink_runs_clean: as value_block_tail_named_like_its_binding_handed_to_a_sink_runs_clean, a Vec filled in the block, in a loop
// Closed: a value block's tail of the `:`'s own name is the block-local by its slot, `|s` (__let_blk_tail_name), as gen_assign hands one over (#806): the new binding takes its flag (agora #823).
// main 006aa3e: AddressSanitizer: heap-use-after-free.
// map: §7.6 | A2 | runs-clean | - | agora #823: a Vec
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: P { String a i n }
: D { String a i n }

% Drop D { @ drop D d → v { ( nurl_println `drop D` ) } }

@ eat sink String x → i { ^ ( string_len x ) }

@ eatv sink ( Vec String ) x → i { ^ ( vec_len [String] x ) }

@ eatp sink P x → i { ^ . x n }

@ eatd sink D x → i { ^ . x n }

@ main → i { : ~ i k 0 ~ < k 2 { : ( Vec String ) v { : ~ ( Vec String ) v ( vec_new [String] ) ( vec_push [String] v ( string_from `e long enough for a heap buffer` ) ) v } ( nurl_println_int ( eatv v ) ) = k + k 1 } ^ 0 }
