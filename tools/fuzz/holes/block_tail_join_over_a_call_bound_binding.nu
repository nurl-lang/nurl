// block_tail_join_over_a_call_bound_binding: agora #459 — `^ { : String x ( pick a k ) ? c x a }`, a value block whose tail join may pick x, fresh on some runs
// Closed: a join handed back copies an arm's binding whose flag is a call's answer on the runs it owns what it holds (mem_join_local_lend), as it copies a local's lend (agora #459).
// main: heap-use-after-free (base 836c0e94).
// map: §7.6 | A2 | runs-clean | - | agora #459: a block-tail join over a call-bound binding
$ `stdlib/core/string.nu`

@ pick String a i k → String { ? == k 0 { ^ a } {} ^ ( string_from `a fresh string long enough for the heap here` ) }

@ pr String s → v { ( nurl_println ( string_data s ) ) }

@ fw String a i k b c → String { ^ { : String x ( pick a k ) ? c x a } }

@ main → i {
    : String o ( string_from `the owner long enough for the heap here` )
    : String p ( fw o 1 T )
    : String q ( fw o 1 F )
    : String r ( fw o 0 T )
    ( pr p ) ( pr q ) ( pr r )
    ( pr o )
    ^ 0
}
