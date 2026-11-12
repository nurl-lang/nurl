// drop_payload_of_a_call_option_whose_arm_panics_is_dropped_runs_clean: under recover, `?? ( f … )` over a call's fresh `?Bomb` / `!Bomb E` whose arm panics, a nested such match, and one in a loop
// Guard for agora #745: the `% Drop` payload an arm binds as its own is journaled with its flag (gen_match → mem_journal_push_userdrop), so the panic drops it once.
// main 0c864b1f: accepted, LeakSanitizer: the payloads, their destructors never run.
// map: §7.2 | A2 | runs-clean | - | agora #745 guard: a call option's payload is dropped once when its arm panics
$ `stdlib/std/panic.nu`
$ `stdlib/core/string.nu`

: Bomb { String tag i boom }

% Drop Bomb { @ drop Bomb b → v { ( nurl_print `` ) } }

@ bomb i k → Bomb { ^ @ Bomb { ( string_from `a tag long enough for the heap` ) k } }

@ late i on → i {
    ? == on 1 { ( panic `panic in the arm` ) } {}
    ^ 0
}

@ mko i k → ?Bomb { ^ @ ?Bomb { T ( bomb k ) } }

@ mkr i k → !Bomb i { ^ @ !Bomb i { T ( bomb k ) } }

@ opt → v { ?? ( mko 0 ) { T x → { : i z ( late 1 ) } F → {} } }

@ res → v { ?? ( mkr 1 ) { T x → { : i z ( late 1 ) } F e → {} } }

@ nested → v { ?? ( mko 2 ) { T x → { ?? ( mko 3 ) { T y → { : i z ( late 1 ) } F → {} } } F → {} } }

@ looped → v {
    : ~ i k 0
    ~ < k 4 {
        ?? ( mko k ) { T x → { : i z ( late == k 3 ) } F → {} }
        = k + k 1
    }
}

@ main → i {
    : !v PanicInfo a ( recover \ → v { ( opt ) } )
    : !v PanicInfo b ( recover \ → v { ( res ) } )
    : !v PanicInfo c ( recover \ → v { ( nested ) } )
    : !v PanicInfo d ( recover \ → v { ( looped ) } )
    ^ 0
}
