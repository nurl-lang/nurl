// option_joined_call_bound_binding_hands_over_its_source_by_payload: agora #459 — `: ?String x ( maybe a k ) ^ ? c x a`, the x arm taken on the run `maybe` handed back a fresh option, `a` the caller's lend copied in
// Closed: an option (or a result) is told from another by its payload's identity key (mem_ud_ident_key on its registered twin's layout, __udty_val); the parameter leaves with the arm only where the arm holds that very value (agora #459).
// main: LSan: the owned temporary leaked (base 836c0e94).
// map: §7.6 | A2 | runs-clean | - | agora #459: an option join arm hands over its source by its payload
$ `stdlib/core/string.nu`

@ mk s t → ?String { ^ @ ?String { T ( string_from t ) } }

@ maybe ? String a i k → ?String { ? == k 0 { ^ a } {} ^ ( mk `a fresh value long enough for the heap here` ) }

@ sho ? String o → v { ?? o { T s → { ( nurl_println ( string_data s ) ) } F → { ( nurl_println `none` ) } } }

@ fw ? String a i k b c → ?String { : ?String x ( maybe a k ) ^ ? c x a }

@ main → i {
    : ?String o ( mk `the owner long enough for the heap here` )
    : ?String p ( fw ( maybe o 0 ) 1 T )
    : ?String q ( fw ( maybe o 0 ) 0 T )
    : ?String r ( fw ( mk `an owned temporary long enough for the heap` ) 1 T )
    ( sho p ) ( sho q ) ( sho r ) ( sho o )
    ^ 0
}
