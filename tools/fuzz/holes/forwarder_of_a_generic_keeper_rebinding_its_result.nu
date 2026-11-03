// forwarder_of_a_generic_keeper_rebinding_its_result: agora #459 — `: A x ( ug [A] o d ) : A y x ^ y`, the forwarder handing back a cursor over the call's result
// Closed: a cursor over a binding bound from a call answers by that binding's flag (__call_owned_by): its own flag was cleared at the bind (agora #459).
// main: LSan: the fresh value leaked (base 8a2afbc3).
// map: §7.6 | A2 | runs-clean | - | agora #459: a forwarder rebinding its result
$ `stdlib/core/string.nu`

@ mk s t → ?String { ^ @ ?String { T ( string_from t ) } }

@ maybe ? String a i k → ?String { ? == k 0 { ^ a } {} ^ ( mk `a fresh value long enough for the heap here` ) }

@ sho ? String o → v { ?? o { T s → { ( nurl_println ( string_data s ) ) } F → { ( nurl_println `none` ) } } }

@ ug [A] ? A o A d → A { ^ ?? o { T v → v F → d } }

@ gfw [A] ? A o A d → A { : A x ( ug [A] o d ) : A y x ^ y }

@ main → i {
    : ?String o ( mk `the owner long enough for the heap here` )
    : String a ( ug [String] ( maybe o 1 ) ( string_from `a default long enough for the heap here` ) )
    : String x ( gfw [String] ( maybe o 0 ) ( string_from `a second default long enough for the heap` ) )
    : String y ( gfw [String] ( maybe o 1 ) ( string_from `a third default long enough for the heap` ) )
    ( nurl_println ( string_data a ) )
    ( nurl_println ( string_data x ) )
    ( nurl_println ( string_data y ) )
    ( sho o )
    ^ 0
}
