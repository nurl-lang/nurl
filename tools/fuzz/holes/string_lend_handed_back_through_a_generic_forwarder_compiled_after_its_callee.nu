// string_lend_handed_back_through_a_generic_forwarder_compiled_after_its_callee: agora #459 — the String form: `g3 [String]` binding `( g2 [String] a k f )` and handing it back, compiled after `g2 [String]`
// Closed: a call to a generic instance compiled already reads the instance's per-call answer (mem_capture_hown), as a call to one not compiled yet did (agora #459).
// main: heap-use-after-free (base 8a2afbc3).
// map: §7.6 | A2 | runs-clean | - | agora #459: a String through a generic forwarder compiled after its callee
$ `stdlib/core/string.nu`

@ gm [T] T a i k ( @ T ) f → T { ? == k 0 { ^ a } {} ^ ( f ) }

@ g2 [T] T a i k ( @ T ) f → T { ^ ( gm [T] a k f ) }

@ g3 [T] T a i k ( @ T ) f → T { : T r ( g2 [T] a k f ) ^ r }

@ main → i {
    : ( @ String ) f \ → String { ^ ( string_from `a closure fresh long enough for the heap` ) }
    : ~ String o ( string_from `the owner long enough for the heap here` )
    = o ( g2 [String] o 0 f )
    : String x ( g3 [String] o 0 f )
    ( nurl_println ( string_data x ) )
    ( nurl_println ( string_data o ) )
    ^ 0
}
