// value_block_tail_named_like_its_binding_beside_an_outer_one_runs_clean: `: String s { : String s … s }` inside an arm, beside an outer s read after the arm
// Closed: a value block's tail of the `:`'s own name is the block-local by its slot, `|s` (__let_blk_tail_name), as gen_assign hands one over (#806): the new binding takes its flag (agora #823).
// main 006aa3e: AddressSanitizer: heap-use-after-free.
// map: §7.6 | A2 | runs-clean | - | agora #823: beside an outer binding of the name
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: P { String a i n }
: D { String a i n }

% Drop D { @ drop D d → v { ( nurl_println `drop D` ) } }

@ eat sink String x → i { ^ ( string_len x ) }

@ eatv sink ( Vec String ) x → i { ^ ( vec_len [String] x ) }

@ eatp sink P x → i { ^ . x n }

@ eatd sink D x → i { ^ . x n }

@ main → i { : ~ i k 0 ~ < k 2 { : String s ( string_from `outer long enough for a heap buffer` ) ? T { : String s { : String s ( string_from `s long enough for a heap buffer` ) s } ( nurl_println_int ( eat s ) ) } {} ( nurl_println ( string_data s ) ) = k + k 1 } ^ 0 }
