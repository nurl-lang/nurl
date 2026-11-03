// lend_handed_back_through_a_generic_forwarder_compiled_after_its_callee: agora #459 — `: T r ( g2 [T] a k f ) ^ r` in `g3`, instantiated after `g2 [?String]` was compiled, `g2` handing back its parameter on one run
// Closed: a call to a generic instance compiled already reads the instance's per-call answer (mem_capture_hown is given the generic it instantiates), as a call to one not compiled yet did; the forwarder hands that answer on (agora #459).
// main: heap-use-after-free (base 8a2afbc3).
// map: §7.6 | A2 | runs-clean | - | agora #459: a generic forwarder compiled after its callee
$ `stdlib/core/string.nu`

@ mk s t → ?String { ^ @ ?String { T ( string_from t ) } }

@ sho ? String o → v { ?? o { T s → { ( nurl_println ( string_data s ) ) } F → { ( nurl_println `none` ) } } }

@ gm [T] T a i k ( @ T ) f → T { ? == k 0 { ^ a } {} ^ ( f ) }

@ g2 [T] T a i k ( @ T ) f → T { ^ ( gm [T] a k f ) }

@ g3 [T] T a i k ( @ T ) f → T { : T r ( g2 [T] a k f ) ^ r }

@ main → i {
    : ( @ ?String ) f \ → ?String { ^ ( mk `a closure fresh long enough for the heap` ) }
    : ~ ? String o ( mk `the owner long enough for the heap here` )
    : i k 0
    = o ( g2 [? String] o k f )
    : ?String x ( g3 [? String] o k f )
    ( sho x )
    ( sho o )
    ^ 0
}
