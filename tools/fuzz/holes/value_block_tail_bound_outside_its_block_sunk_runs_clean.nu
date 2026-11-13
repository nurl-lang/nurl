// value_block_tail_bound_outside_its_block_sunk_runs_clean: `: String t { s }  ( eat t )`: accepted as `: t s  ( eat t )` is
// Closed: a value block whose tail is a binding — wherever it is bound — is that binding, as the unblocked `: t s` (formal's OK: A2's ANF reading of a block): its flag moves (__let_blk_tail_name), the walk reads the tail as the binding (__blk_tail_binding, __sx_operand_c).
// main 6e45ef9: refused ('t' is a borrow), a correct program.
// map: §7.6 | A2 | runs-clean | - | agora #823: a correct program, refused before
$ `stdlib/core/string.nu`

@ eat sink String x → i { ^ ( string_len x ) }

@ main → i { : String s ( string_from `outer string long enough for a heap buffer` ) : String t { s } ( nurl_println_int ( eat t ) ) ^ 0 }
