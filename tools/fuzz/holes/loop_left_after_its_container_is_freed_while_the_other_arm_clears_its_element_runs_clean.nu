// loop_left_after_its_container_is_freed_while_the_other_arm_clears_its_element_runs_clean: agora #482 — `x01` with a `break` right after the helper clears `vvv`; the other arm clears `r`'s own elements through a cursor and the loop goes on
// The shape the fix must keep: a change through the element's own handle leaves it as it is (agora #482).
// main 21a0fb5: runs clean.
// map: §2.5 | A2 | runs-clean | - | agora #482: a loop left after its container is freed, while the other arm clears its element
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ wipe ( Vec ( Vec ( Vec String ) ) ) v → v { ( vec_clear [( Vec ( Vec String ) )] v ) }

@ main → i {
    : ( Vec ( Vec ( Vec String ) ) ) vvv ( vec_new [( Vec ( Vec String ) )] )
    : ~ ( Vec ( Vec String ) ) vv ( vec_new [( Vec String )] )
    : ~ ( Vec String ) t0 ( vec_new [String] )
    ( vec_push [String] t0 ( string_from `a string long enough for a heap buffer here` ) )
    ( vec_push [( Vec String )] vv t0 )
    : ~ ( Vec String ) t1 ( vec_new [String] )
    ( vec_push [String] t1 ( string_from `a second string long enough for a heap buffer` ) )
    ( vec_push [( Vec String )] vv t1 )
    : ~ ( Vec String ) t2 ( vec_new [String] )
    ( vec_push [String] t2 ( string_from `a third string long enough for a heap buffer` ) )
    ( vec_push [( Vec String )] vv t2 )
    ( vec_push [( Vec ( Vec String ) )] vvv vv )
    : ( Vec ( Vec String ) ) b ( vec_at [( Vec ( Vec String ) )] vvv 0 )
    : ~ i k 0
    ~ r b {
        ( nurl_println_int ( vec_len [String] r ) )
        = k + k 1
        ? == k 2 {
            ( wipe vvv )
            break
        } {
            : ~ ( Vec String ) c r
            ( vec_clear [String] c )
        }
    }
    ( nurl_println_int k )
    ^ 0
}
