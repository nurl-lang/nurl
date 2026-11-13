// value_block_tail_bound_outside_its_block_handed_to_a_sink_runs_clean: `: String e { : String s … : String t { s } t }  ( eat e )`
// Closed: a value block whose tail is a binding — wherever it is bound — is that binding, as the unblocked `: t s` (formal's OK: A2's ANF reading of a block): its flag moves (__let_blk_tail_name), the walk reads the tail as the binding (__blk_tail_binding, __sx_operand_c).
// main 6e45ef9: AddressSanitizer: heap-use-after-free.
// map: §7.6 | A2 | runs-clean | - | agora #823: a tail two blocks deep
$ `stdlib/core/string.nu`

@ eat sink String x → i { ^ ( string_len x ) }

@ main → i { : String e { : String s ( string_from `inner string long enough for a heap buffer` ) : String t { s } t } ( nurl_println_int ( eat e ) ) ^ 0 }
