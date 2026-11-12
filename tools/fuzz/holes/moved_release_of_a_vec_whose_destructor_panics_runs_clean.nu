// moved_release_of_a_vec_whose_destructor_panics_runs_clean: under recover, vec_clear, vec_truncate, vec_retain and deque_clear release `% Drop` elements, one of whose destructors panics; afterwards each container is used and dropped.
// Guard for agora #709's release: the elements moved into a buffer of their own (mem_move_drop) are journaled with that buffer (NurlVecDrain.own): a panic in one destructor goes on with the rest and frees the buffer, once.
// main 70f7232: accepted, clean (the in-place release, #608); with a moved release that did not own its buffer, LeakSanitizer: the buffer.
// map: §7.2 | A2 | runs-clean | - | agora #709 guard: a destructor that panics in a moved release leaves every other element dropped once and the release's buffer freed
$ `stdlib/std/panic.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/deque.nu`

: Bomb { String tag i boom }

% Drop Bomb { @ drop Bomb b → v { ? == . b boom 1 { ( panic `panic in drop` ) } {} } }

@ bomb i k → Bomb { ^ @ Bomb { ( string_from `an element long enough for the heap` ) k } }

@ fill ( Vec Bomb ) v → v { ( vec_push [Bomb] v ( bomb 0 ) ) ( vec_push [Bomb] v ( bomb 1 ) ) ( vec_push [Bomb] v ( bomb 0 ) ) ( vec_push [Bomb] v ( bomb 0 ) ) }

@ none Bomb b → b { ^ F }

@ main → i {
    : ~ ( Vec Bomb ) v ( vec_new [Bomb] )
    ( fill v )
    : !v PanicInfo r1 ( recover \ → v { ( vec_clear [Bomb] v ) } )
    ( fill v )
    : !v PanicInfo r2 ( recover \ → v { : b t ( vec_truncate [Bomb] v 1 ) } )
    ( fill v )
    : !v PanicInfo r3 ( recover \ → v { ( vec_retain [Bomb] v \ Bomb b → b { ^ ( none b ) } ) } )
    ( nurl_println ( nurl_str_int ( vec_len [Bomb] v ) ) )
    : ~ ( Deque Bomb ) d ( deque_new [Bomb] )
    ( deque_push_back [Bomb] d ( bomb 0 ) ) ( deque_push_back [Bomb] d ( bomb 1 ) ) ( deque_push_back [Bomb] d ( bomb 0 ) )
    : !v PanicInfo r4 ( recover \ → v { ( deque_clear [Bomb] d ) } )
    ( nurl_println ( nurl_str_int ( deque_len [Bomb] d ) ) )
    ^ 0
}
