// value_block_tail_named_like_its_binding_handed_to_a_sink_runs_clean: `: String s { : String s ( string_from … ) s }  ( eat s )`
// Closed: a value block's tail of the `:`'s own name is the block-local by its slot, `|s` (__let_blk_tail_name), as gen_assign hands one over (#806): the new binding takes its flag (agora #823).
// main 006aa3e: AddressSanitizer: heap-use-after-free.
// map: §7.6 | A2 | runs-clean | - | agora #823: a String
$ `stdlib/core/string.nu`

@ eat sink String x → i { ^ ( string_len x ) }

@ main → i { : String s { : String s ( string_from `inner string long enough for a heap buffer` ) s } ( nurl_println_int ( eat s ) ) ^ 0 }
