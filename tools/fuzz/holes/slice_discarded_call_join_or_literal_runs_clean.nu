// slice_discarded_call_join_or_literal_runs_clean: `( mk )`, `? c ( mk ) a`, `[i | 1 2]` as statements: the fresh slice is released where its value is discarded, a lend (`( id a )`, `( pick a k )` on its lending runs) never
// Closed (agora #903, part): a discarded owned slice is dropped by its bit — a call's answer (__slice_call_own_bit), a slice join's (g_slice_join_own), a literal's (always fresh), as a discarded handle is.
// main b9a73419: LeakSanitizer reported the discarded slices never released.
// map: §7.6 | A2 | runs-clean | - | AGORA-903: a slice call, join or literal discarded as a statement is released; a lend is not
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ mk → [i { ^ [i | 7 8 9] }
@ id [i a → [i { ^ a }
@ pick [i a b k → [i { ? k { ^ a } { ^ [i | 4 5] } }
@ run b c b k → v { : [i a [i | 1 2] ( mk ) ? c ( mk ) a [i | 3 3] ( id a ) ( pick a k ) ? c ( pick a k ) a : ~ i n 0 ~ < n 3 { ( mk ) = n + n 1 } ( nurl_println_int . a 1 ) }
@ main → i { ( run T T ) ( run T F ) ( run F T ) ( run F F ) ^ 0 }
