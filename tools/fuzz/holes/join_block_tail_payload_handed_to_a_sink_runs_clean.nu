// join_block_tail_payload_handed_to_a_sink_runs_clean: a binding a `??` join gave a payload its arm's block ends in (`: String t ?? e { One s → { … s } … }`), over an enum someone else keeps, handed to a `sink` parameter — directly and through a copy of the binding.
// Guard for agora #641: the binding owns its value only on the paths the join's arms did (`dyn`), and has nothing of its own to give up where it was lent: the callee is handed a copy there (__lent_by_join). Before, the callee released the enum's own String and the enum's owner released it again. (A bare arm `One s → s` is refused by the borrow walk: "'t' is a borrow".)
// main 37334be: accepted, heap-use-after-free in nurl_vec_drop (a parameter's enum; an enum with a `% Drop` of its own leaked its payload instead, so nothing was seen).
// map: §7.6 | A2 | runs-clean | - | agora #641 guard: a join-bound lend of an enum's payload (a block arm's tail) handed to a sink is copied where the binding owns nothing
$ `stdlib/core/string.nu`

: | E { Zero i One String }

: | D { DZero i DOne String }

% Drop D { @ drop D d → v { ( nurl_println `drop D` ) } }

@ eat sink String t → v { ( nurl_println ( string_data t ) ) }

@ of_parameter E e → v {
    : String t ?? e {
        One s → {
            ( nurl_println `arm` )
            s
        }
        Zero n → ( string_from `none` )
    }
    ( eat t )
}

@ of_own_drop → v {
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

@ main → i {
    : E e @ E { One ( string_from `kept by the caller's enum, on the heap` ) }
    ( of_parameter e )
    ( of_own_drop )
    ^ 0
}
