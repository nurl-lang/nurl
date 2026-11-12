// old_value_leaves_its_slot_before_its_destructor_panics_runs_clean: under recover, a binding, a Vec binding, an inout parameter, a field and a closure field are given new values whose OLD values' destructors panic; afterwards a binding owned outside the extent is used.
// Guard for agora #621: the old value leaves its slot before its destructor runs (mem_udrop_take_old, __fs_late_emit): the slot holds the new value from the store on, so the unwind drops the new value once and the old value's destructor releases what it still holds.
// main 70f7232: accepted, heap-use-after-free in the drain (the unwind dropped the old value again) and the new values leaked.
// map: §7.2 | A2 | runs-clean | - | agora #621 guard: `= b ( new )` / `= . h f ( new )` whose old value's destructor panics drops the old value once and keeps the new one where it belongs
$ `stdlib/std/panic.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: Bomb { String tag i boom }

% Drop Bomb {
    @ drop Bomb b → v { ? == . b boom 1 { ( panic ( nurl_str_cat `panic in drop ` ( string_data . b tag ) ) ) } {} }
}

: Holder { Bomb b ( @ i ) f }

@ bomb s tag i boom → Bomb { ^ @ Bomb { ( string_from tag ) boom } }

@ bombs i boom → ( Vec Bomb ) {
    : ~ ( Vec Bomb ) w ( vec_new [Bomb] )
    ( vec_push [Bomb] w ( bomb `elem` 0 ) ) ( vec_push [Bomb] w ( bomb `elem` boom ) )
    ^ w
}

@ put inout Bomb slot → v { = slot ( bomb `inout.new` 0 ) }

@ field → v {
    : ~ Holder h @ Holder { ( bomb `field.old` 1 ) \ → i { ^ 0 } }
    = . h b ( bomb `field.new` 0 )
}

@ closure_field → v {
    : Bomb c1 ( bomb `capture.old` 1 )
    : ~ Holder h @ Holder { ( bomb `field` 0 ) \ → i { ^ . c1 boom } }
    : Bomb c2 ( bomb `capture.new` 0 )
    = . h f \ → i { ^ . c2 boom }
}

@ main → i {
    : ~ Bomb b ( bomb `binding.old` 1 )
    : !v PanicInfo r1 ( recover \ → v { = b ( bomb `binding.new` 0 ) } )
    : ~ ( Vec Bomb ) v ( bombs 1 )
    : !v PanicInfo r2 ( recover \ → v { = v ( bombs 0 ) } )
    : ~ Bomb io ( bomb `inout.old` 1 )
    : !v PanicInfo r3 ( recover \ → v { ( put io ) } )
    : !v PanicInfo r4 ( recover \ → v { ( field ) } )
    : !v PanicInfo r5 ( recover \ → v { ( closure_field ) } )
    ( nurl_println ( nurl_str_int ( vec_len [Bomb] v ) ) )
    ^ 0
}
