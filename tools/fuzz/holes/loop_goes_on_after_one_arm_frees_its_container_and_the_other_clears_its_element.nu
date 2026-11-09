// loop_goes_on_after_one_arm_frees_its_container_and_the_other_clears_its_element: agora #482 — `~ r b` over `b = ( vec_at vvv 0 )`: one `?` arm clears `vvv` through a helper, the other clears `r`'s own elements through a cursor over `r`; the loop goes on
// Closed: a loop whose element ended with its storage on any path that goes on to its next element is refused; an end through the element's own handle spares it exactly, so no path's end is lost (agora #482).
// main 21a0fb5: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.5 | A2 | rejected | - | agora #482: a loop goes on after one arm frees its container and the other clears its element
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
        ? == k 1 {
            ( wipe vvv )
        } {
            : ~ ( Vec String ) c r
            ( vec_clear [String] c )
        }
    }
    ( nurl_println_int k )
    ^ 0
}
