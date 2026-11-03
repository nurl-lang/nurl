// bound_block_join_over_a_call_bound_binding: agora #459 — `: String r { ? c x a } ^ r`, a binding of a value block whose tail join may pick a call-bound x
// Closed: a binding of a join no arm handed a value of its own is a cursor over its call-bound arms (__mem_udrop_bind_flag); handed back, it answers by identity and the arm it holds no longer drops it (agora #459).
// main: heap-use-after-free (base 836c0e94).
// map: §7.6 | A2 | runs-clean | - | agora #459: a bound block-tail join over a call-bound binding
$ `stdlib/core/string.nu`

@ pick String a i k → String { ? == k 0 { ^ a } {} ^ ( string_from `a fresh string long enough for the heap here` ) }

@ pr String s → v { ( nurl_println ( string_data s ) ) }

@ fw String a i k b c → String { : String x ( pick a k ) : String r { ? c x a } ^ r }

@ main → i {
    : String o ( string_from `the owner long enough for the heap here` )
    : String p ( fw o 1 T )
    : String q ( fw o 1 F )
    : String r ( fw o 0 T )
    ( pr p ) ( pr q ) ( pr r )
    ( pr o )
    ^ 0
}
