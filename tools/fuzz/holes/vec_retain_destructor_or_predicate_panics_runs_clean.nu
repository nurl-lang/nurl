// vec_retain_destructor_or_predicate_panics_runs_clean: `vec_retain` over `% Drop` elements, where the destructor of one that goes panics, or the predicate does part-way through.
// Guard for agora #624: every element is judged first, the kept ones swapped to the front, and the others are dropped after the Vec's length is down to the kept ones (mem_drop_range, as vec_truncate). The Vec holds each element once whenever the predicate or a destructor runs, so the drain drops each once. Before, each one that went was dropped inside the loop with the Vec still at its old length: the drain dropped the Vec over slots already given up.
// main 8c514da: accepted, SEGV in drop__Bomb (a null read of the emptied slot) under the Vec's drop in nurl__jrnl_drain; with the predicate panicking after a kept element was moved down, heap-use-after-free in drop__Bomb (the moved element dropped twice).
// map: §7.2 | A2 | runs-clean | - | agora #624 guard: vec_retain whose rejected element's destructor panics, or whose predicate panics mid-way, leaves a Vec holding each element once; each is dropped once
$ `stdlib/std/panic.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

// kind: 0 goes, 1 stays, 2 goes and its destructor panics, 3 the predicate panics on it
: Bomb { String tag i kind }

% Drop Bomb {
    @ drop Bomb b → v {
        ( nurl_println ( nurl_str_cat `drop ` ( string_data . b tag ) ) )
        ? == . b kind 2 { ( panic ( nurl_str_cat `panic in drop ` ( string_data . b tag ) ) ) } {}
    }
}

@ stays Bomb x → b {
    ? == . x kind 3 { ( panic ( nurl_str_cat `panic judging ` ( string_data . x tag ) ) ) } {}
    ^ == . x kind 1
}

@ build i k1 i k3 → ( Vec Bomb ) {
    : ~ ( Vec Bomb ) v ( vec_new [Bomb] )
    ( vec_push [Bomb] v @ Bomb { ( string_from `e0, long enough for the heap` ) 1 } )
    ( vec_push [Bomb] v @ Bomb { ( string_from `e1, long enough for the heap` ) k1 } )
    ( vec_push [Bomb] v @ Bomb { ( string_from `e2, long enough for the heap` ) 1 } )
    ( vec_push [Bomb] v @ Bomb { ( string_from `e3, long enough for the heap` ) k3 } )
    ( vec_push [Bomb] v @ Bomb { ( string_from `e4, long enough for the heap` ) 0 } )
    ^ v
}

// The drain drops the Vec the retain was working on.
@ unwound i k1 i k3 → v {
    : ~ ( Vec Bomb ) v ( build k1 k3 )
    ( vec_retain [Bomb] v \ Bomb x → b { ^ ( stays x ) } )
    ( nurl_println `not reached` )
}

// The retain's own `recover`: the Vec is used afterwards.
@ kept_on i k1 i k3 → v {
    : ~ ( Vec Bomb ) v ( build k1 k3 )
    : !v PanicInfo r ( recover \ → v { ( vec_retain [Bomb] v \ Bomb x → b { ^ ( stays x ) } ) } )
    ( nurl_println ( nurl_str_cat `len ` ( nurl_str_int ( vec_len [Bomb] v ) ) ) )
    ( vec_push [Bomb] v @ Bomb { ( string_from `late, long enough for the heap` ) 1 } )
    ( vec_retain [Bomb] v \ Bomb x → b { ^ ( stays x ) } )
    ( nurl_println ( nurl_str_cat `len ` ( nurl_str_int ( vec_len [Bomb] v ) ) ) )
}

@ run ( @ v ) f → v {
    : !v PanicInfo r ( recover f )
    ?? r {
        T _ → { ( nurl_println `no panic` ) }
        F e → { ( nurl_println ( nurl_str_cat `recovered: ` ( string_data . e msg ) ) ) }
    }
}

@ main → i {
    // a destructor of one that goes panics; then two of them
    ( run \ → v { ( unwound 2 0 ) } )
    ( run \ → v { ( unwound 2 2 ) } )
    // the predicate panics, before and after an element was moved
    ( run \ → v { ( unwound 3 0 ) } )
    ( run \ → v { ( unwound 0 3 ) } )
    ( kept_on 2 0 )
    ( kept_on 0 3 )
    ^ 0
}
