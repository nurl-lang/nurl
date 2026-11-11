// enum_own_drop_join_block_tail_payload_handed_to_a_sink_runs_clean: a binding a `??` join gave a payload its arm's block ends in (`: String t ?? d { DOne s → { … s } … }`), over an enum with a `% Drop` of its own that the function keeps, handed to a `sink` parameter — directly and through a copy of the binding.
// Guard for agora #641: the enum stays whole and drops its payload after its impl; the binding owns its value only on the paths the join's arms did, and has nothing of its own to give up where it was lent the payload: the callee is handed a copy there (__lent_by_join). With the enum's glue alone, the callee released the enum's own String and the enum released it again. The same for a bare arm `DOne s → s`.
// main 37334be: accepted and clean, the payload leaked instead (no glue). The same shape over a PARAMETER's plain enum is a heap-use-after-free on main and still is: agora #635.
// map: §7.6 | A2 | runs-clean | - | agora #641 guard: a join-bound lend of a kept % Drop enum's payload (a block arm's tail) handed to a sink is copied where the binding owns nothing
$ `stdlib/core/string.nu`

: | D { DZero i DOne String }

% Drop D { @ drop D d → v { ( nurl_println `drop D` ) } }

@ eat sink String t → v { ( nurl_println ( string_data t ) ) }

@ direct → v {
    : D d @ D { DOne ( string_from `kept by an enum with a destructor` ) }
    : String t ?? d {
        DOne s → {
            ( nurl_println `arm` )
            s
        }
        DZero n → ( string_from `none` )
    }
    ( eat t )
}

@ through_a_copy → v {
    : D d @ D { DOne ( string_from `kept by an enum with a destructor` ) }
    : String t ?? d {
        DOne s → {
            ( nurl_println `arm` )
            s
        }
        DZero n → ( string_from `none` )
    }
    : String u t
    ( eat u )
}

@ bare_arm → v {
    : D d @ D { DOne ( string_from `kept by an enum with a destructor` ) }
    : String t ?? d {
        DOne s → s
        DZero n → ( string_from `none` )
    }
    ( eat t )
}

@ main → i {
    ( direct )
    ( through_a_copy )
    ( bare_arm )
    ^ 0
}
