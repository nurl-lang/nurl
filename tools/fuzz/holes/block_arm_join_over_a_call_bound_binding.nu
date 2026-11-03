// block_arm_join_over_a_call_bound_binding: agora #459 — `^ { : String x ( pick a k ) ? c { x } { a } }`, the join's arms blocks whose tails are the bindings
// Closed: a block arm whose tail is a binding counts as that binding for the join's copy (__last_join_tails__, agora #459).
// main: heap-use-after-free (base 836c0e94).
// map: §7.6 | A2 | runs-clean | - | agora #459: a block-arm join over a call-bound binding
$ `stdlib/core/string.nu`

@ pick String a i k → String { ? == k 0 { ^ a } {} ^ ( string_from `a fresh string long enough for the heap here` ) }

@ pr String s → v { ( nurl_println ( string_data s ) ) }

@ fw String a i k b c → String { ^ { : String x ( pick a k ) ? c { x } { a } } }

@ main → i {
    : String o ( string_from `the owner long enough for the heap here` )
    : String p ( fw o 1 T )
    : String q ( fw o 1 F )
    : String r ( fw o 0 T )
    ( pr p ) ( pr q ) ( pr r )
    ( pr o )
    ^ 0
}
