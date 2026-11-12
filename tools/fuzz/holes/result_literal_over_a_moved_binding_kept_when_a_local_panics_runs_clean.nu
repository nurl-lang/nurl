// result_literal_over_a_moved_binding_kept_when_a_local_panics_runs_clean: functions hand back a literal that took in their own bindings — `@ ?String { T s }`, `@ !String i { T s }`, a struct over two, a literal nested in one, a `sink` parameter — while an earlier local's destructor panics at their exit, under recover.
// Guard for agora #720: such a literal is the function's own result until the `ret` and is journaled for the locals' drops (mem_ret_guard_push), as a literal of fresh parts was; the bindings it took in hold nothing by then.
// main 70f7232: accepted, LeakSanitizer: the result's Strings, its destructor never run.
// map: §7.2 | A2 | runs-clean | - | agora #720 guard: a result literal over moved bindings is dropped once when a local's destructor panics at the function's exit
$ `stdlib/std/panic.nu`
$ `stdlib/core/string.nu`

: Bomb { String tag i boom }

% Drop Bomb { @ drop Bomb b → v { ? == . b boom 1 { ( panic `panic in drop` ) } {} } }

: Pair { String a String b }

@ bomb s tag i boom → Bomb { ^ @ Bomb { ( string_from tag ) boom } }

@ long → String { ^ ( string_from `a value long enough for the heap` ) }

@ f1 → ?String { : Bomb b ( bomb `f1` 1 ) : String s ( long ) ^ @ ?String { T s } }

@ f2 → !String i { : Bomb b ( bomb `f2` 1 ) : String s ( long ) ^ @ !String i { T s } }

@ f3 → Pair { : Bomb b ( bomb `f3` 1 ) : String s ( long ) : String t ( long ) ^ @ Pair { s t } }

@ f4 → ?Pair { : Bomb b ( bomb `f4` 1 ) : String s ( long ) : String t ( long ) ^ @ ?Pair { T @ Pair { s t } } }

@ f5 → ?Bomb { : Bomb b ( bomb `f5` 1 ) : Bomb k ( bomb `kept` 0 ) ^ @ ?Bomb { T k } }

@ f6 sink String p → ?String { : Bomb b ( bomb `f6` 1 ) ^ @ ?String { T p } }

@ main → i {
    : !v PanicInfo r1 ( recover \ → v { : ?String g ( f1 ) } )
    : !v PanicInfo r2 ( recover \ → v { : !String i g ( f2 ) } )
    : !v PanicInfo r3 ( recover \ → v { : Pair g ( f3 ) } )
    : !v PanicInfo r4 ( recover \ → v { : ?Pair g ( f4 ) } )
    : !v PanicInfo r5 ( recover \ → v { : ?Bomb g ( f5 ) } )
    : !v PanicInfo r6 ( recover \ → v { : ?String g ( f6 ( long ) ) } )
    ^ 0
}
