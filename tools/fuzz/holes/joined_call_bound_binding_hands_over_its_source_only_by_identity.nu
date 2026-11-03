// joined_call_bound_binding_hands_over_its_source_only_by_identity: agora #459 — `: String x ( pick a k ) ^ ? c x a`, the join's x arm taken on the run `pick` handed back a fresh value, `a` the function's own
// Closed: an arm whose binding's flag is a call's own answer moves out what it holds by identity (__own_by_identity, mem_alias_src_leaves): the parameter it may lend leaves with it only where it holds that very value — not on the run it holds a fresh one (agora #459).
// main: LSan: the parameter's value leaked (base 836c0e94).
// map: §7.6 | A2 | runs-clean | - | agora #459: a join arm over a call-bound binding hands over its source by identity
$ `stdlib/core/string.nu`

@ pick String a i k → String { ? == k 0 { ^ a } {} ^ ( string_from `a fresh string long enough for the heap here` ) }

@ pr String s → v { ( nurl_println ( string_data s ) ) }

@ fw String a i k b c → String { : String x ( pick a k ) ^ ? c x a }

@ main → i {
    : String o ( string_from `the owner long enough for the heap here` )
    : String p ( fw ( pick o 0 ) 1 T )
    : String q ( fw ( pick o 0 ) 0 T )
    : String r ( fw ( pick o 1 ) 1 F )
    ( pr p ) ( pr q ) ( pr r ) ( pr o )
    ^ 0
}
