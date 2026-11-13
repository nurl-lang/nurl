// value_block_drop_struct_tail_named_like_its_binding_handed_to_a_sink_runs_clean: as value_block_tail_named_like_its_binding_handed_to_a_sink_runs_clean, D with a % Drop of its own: its destructor runs once a round
// Closed: a value block's tail of the `:`'s own name is the block-local by its slot, `|s` (__let_blk_tail_name), as gen_assign hands one over (#806): the new binding takes its flag (agora #823).
// main 006aa3e: AddressSanitizer: heap-use-after-free.
// map: §7.6 | A2 | runs-clean | - | agora #823: a % Drop struct
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: P { String a i n }
: D { String a i n }

% Drop D { @ drop D d → v { ( nurl_println `drop D` ) } }

@ eat sink String x → i { ^ ( string_len x ) }

@ eatv sink ( Vec String ) x → i { ^ ( vec_len [String] x ) }

@ eatp sink P x → i { ^ . x n }

@ eatd sink D x → i { ^ . x n }

@ main → i { : ~ i k 0 ~ < k 2 { : D d { : D d @ D { ( string_from `d long enough for a heap buffer` ) 1 } d } ( nurl_println_int ( eatd d ) ) = k + k 1 } ^ 0 }
