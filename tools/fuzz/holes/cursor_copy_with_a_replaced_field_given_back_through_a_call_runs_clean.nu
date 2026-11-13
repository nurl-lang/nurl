// cursor_copy_with_a_replaced_field_given_back_through_a_call_runs_clean: `: ~ P q o`, a field of q replaced, then `= o ( ppick o q 0 )`, `= o ( qid q )`, and a picker defined below its caller.
// Closed (agora #450 I): a run whose result has q's key while q still holds o's value is q's value, given back to o (mem_ff_write_back).
// main 37d2887c: heap-use-after-free or double free on each.
// map: §7.6 | A2 | runs-clean | - | agora #450 I: a cursor copy with a replaced field given back through a call
$ `stdlib/core/string.nu`

: P { String name String extra }

@ mk s t → String { ^ ( string_from ( nurl_str_cat t `, long enough for a heap buffer` ) ) }

@ ppick P a P b i k → P { ? == k 1 { ^ a } {} ^ b }

@ qid P a → P { ^ a }

@ pick_key → v { : ~ P o @ P { ( mk `o name` ) ( mk `o extra` ) } : ~ P q o = . q name ( mk `q name` ) = o ( ppick o q 0 ) ( nurl_println ( string_data . o name ) ) ( nurl_println ( string_data . o extra ) ) }

@ pick_other → v { : ~ P o @ P { ( mk `o name` ) ( mk `o extra` ) } : ~ P q o = . q extra ( mk `q extra` ) = o ( ppick o q 0 ) ( nurl_println ( string_data . o name ) ) ( nurl_println ( string_data . o extra ) ) }

@ id_key → v { : ~ P o @ P { ( mk `o name` ) ( mk `o extra` ) } : ~ P q o = . q name ( mk `q name` ) = o ( qid q ) ( nurl_println ( string_data . o name ) ) }

@ later_other → v { : ~ P o @ P { ( mk `o name` ) ( mk `o extra` ) } : ~ P q o = . q extra ( mk `q extra` ) = o ( later o q 0 ) ( nurl_println ( string_data . o extra ) ) }

@ main → i { ( pick_key ) ( pick_other ) ( id_key ) ( later_other ) ^ 0 }

@ later P a P b i k → P { ? == k 1 { ^ a } {} ^ b }
