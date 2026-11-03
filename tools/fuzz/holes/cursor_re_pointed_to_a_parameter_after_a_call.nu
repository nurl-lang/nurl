// cursor_re_pointed_to_a_parameter_after_a_call: agora #459 — `: String x ( pick a k ) : ~ String y x ? c { = y a } {} ^ y`, y re-pointed to the parameter on one path
// Closed: a cursor over a binding whose flag is a call's answer owns what it holds by its flag, or by that binding's where it holds the very same value (identity keys, __own_by_identity) — not by the flags alone (agora #459).
// main: LSan: the fresh value leaked (base 836c0e94).
// map: §7.6 | A2 | runs-clean | - | agora #459: a cursor re-pointed to a parameter
$ `stdlib/core/string.nu`

@ pick String a i k → String { ? == k 0 { ^ a } {} ^ ( string_from `a fresh string long enough for the heap here` ) }

@ pr String s → v { ( nurl_println ( string_data s ) ) }

@ fw String a i k b c → String { : String x ( pick a k ) : ~ String y x ? c { = y a } {} ^ y }

@ main → i {
    : String o ( string_from `the owner long enough for the heap here` )
    : String p ( fw o 1 T )
    : String q ( fw o 1 F )
    : String r ( fw o 0 T )
    ( pr p ) ( pr q ) ( pr r )
    ( pr o )
    ^ 0
}
