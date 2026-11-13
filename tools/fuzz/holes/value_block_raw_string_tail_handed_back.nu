// value_block_raw_string_tail_handed_back: `@ mk → s { : s e { : s t ( nurl_str_cat … ) t }  ^ e }`: refused as `: s e t  ^ e` is
// Closed: a value block whose tail is a binding — wherever it is bound — is that binding, as the unblocked `: t s` (formal's OK: A2's ANF reading of a block): its flag moves (__let_blk_tail_name), the walk reads the tail as the binding (__blk_tail_binding, __sx_operand_c).
// main 6e45ef9: accepted, the caller read freed memory.
// map: §7.6 | A2 | rejected | - | agora #823: a raw string tail handed back
$ `stdlib/core/string.nu`

@ eat sink String x → i { ^ ( string_len x ) }

@ mk → s { : s e { : s t ( nurl_str_cat `abc` `def and a longer tail for the heap buffer` ) t } ^ e }

@ main → i { ( nurl_println ( mk ) ) ^ 0 }
