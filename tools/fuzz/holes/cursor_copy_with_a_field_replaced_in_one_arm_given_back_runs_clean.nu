// cursor_copy_with_a_field_replaced_in_one_arm_given_back_runs_clean: `: ~ P q o`, q's name or extra replaced in one arm of a `?` (or neither), then `= o q`; and `= o q` itself in one arm.
// Closed (agora #450 I): the field-owner flags answer per run; a run that replaced nothing gives o back its own value whole.
// main 37d2887c: heap-use-after-free and a leak on the runs that replaced a field.
// map: §7.6 | A2 | runs-clean | - | agora #450 I: a cursor copy with a field replaced in one arm, given back
$ `stdlib/core/string.nu`

: P { String name String extra }

@ mk s t → String { ^ ( string_from ( nurl_str_cat t `, long enough for a heap buffer` ) ) }

@ arms i c → v { : ~ P o @ P { ( mk `o name` ) ( mk `o extra` ) } : ~ P q o ? == c 1 { = . q name ( mk `q name` ) } {} ? == c 2 { = . q extra ( mk `q extra` ) } {} = o q ( nurl_println ( string_data . o name ) ) ( nurl_println ( string_data . o extra ) ) }

@ back_in_arm i c → v { : ~ P o @ P { ( mk `o name` ) ( mk `o extra` ) } : ~ P q o = . q name ( mk `q name` ) ? == c 1 { = o q } {} ( nurl_println ( string_data . o name ) ) }

@ main → i { ( arms 0 ) ( arms 1 ) ( arms 2 ) ( back_in_arm 0 ) ( back_in_arm 1 ) ^ 0 }
