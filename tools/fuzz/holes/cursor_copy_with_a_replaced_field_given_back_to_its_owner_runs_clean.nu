// cursor_copy_with_a_replaced_field_given_back_to_its_owner_runs_clean: `: ~ P q o`, a field of q replaced (the first, the key; or another), then `= o q`; and a cursor over that cursor given back (`: ~ P q2 q`).
// Closed (agora #450 I): on the runs q still holds o's value, o keeps it — what q's fields replaced is dropped, and those fields are o's (mem_ff_write_back).
// main 37d2887c: heap-use-after-free (key replaced: o's old value dropped under the field q shares) or double free (another field: q drops its replaced field again).
// map: §7.6 | A2 | runs-clean | - | agora #450 I: a cursor copy with a replaced field given back to its owner
$ `stdlib/core/string.nu`

: P { String name String extra }

@ mk s t → String { ^ ( string_from ( nurl_str_cat t `, long enough for a heap buffer` ) ) }

@ key → v { : ~ P o @ P { ( mk `o name` ) ( mk `o extra` ) } : ~ P q o = . q name ( mk `q name` ) = o q ( nurl_println ( string_data . o name ) ) ( nurl_println ( string_data . o extra ) ) }

@ other → v { : ~ P o @ P { ( mk `o name` ) ( mk `o extra` ) } : ~ P q o = . q extra ( mk `q extra` ) = o q ( nurl_println ( string_data . o name ) ) ( nurl_println ( string_data . o extra ) ) }

@ chain → v { : ~ P o @ P { ( mk `o name` ) ( mk `o extra` ) } : ~ P q o : ~ P q2 q = . q2 name ( mk `q2 name` ) = o q2 ( nurl_println ( string_data . o name ) ) ( nurl_println ( string_data . o extra ) ) }

@ main → i { ( key ) ( other ) ( chain ) ^ 0 }
