// moved_release_on_the_stack_and_the_heap_with_a_panicking_destructor_runs_clean: vec_clear, vec_truncate and deque_clear release `% Drop` elements that fit the runtime's stack buffer (a few) and ones that do not (forty), a deque whose live elements wrap around its ring (two runs), with a destructor that panics under recover; each count of drops is printed.
// Guard for agora #748: mem_move_drop moves the elements to go into the runtime frame's own stack when they fit (512 bytes) and into the heap past that; the release's record owns only a heap buffer. Each element is dropped once, a heap buffer is freed once, a stack one never. (A destructor pushing into its container: destructor_pushing_into_its_own_vec_and_deque_while_cleared_runs_clean.)
// main 3c4322c: accepted, clean (every release took a heap buffer).
// map: §7.2 | A2 | runs-clean | - | agora #748 guard: a moved release on the stack or the heap, a wrapped deque, a panicking destructor — every element dropped once, the buffer freed once
$ `stdlib/std/panic.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/deque.nu`

: Bomb { String tag i boom }

: ~ i g_drops 0

% Drop Bomb { @ drop Bomb b → v {
        = g_drops + g_drops 1
        ? == . b boom 1 { ( panic `panic in drop` ) } {}
    } }

@ bomb i k → Bomb { ^ @ Bomb { ( string_from `an element long enough for the heap` ) k } }

@ fill ( Vec Bomb ) v i n i at → v {
    : ~ i j 0
    ~ < j n {
        ( vec_push [Bomb] v ( bomb ? == j at 1 0 ) )
        = j + j 1
    }
}

@ main → i {
    : ~ ( Vec Bomb ) v ( vec_new [Bomb] )
    // Small (stack) and large (heap) releases, a destructor panicking in each.
    ( fill v 3 1 )
    : !v PanicInfo r1 ( recover \ → v { ( vec_clear [Bomb] v ) } )
    ( fill v 40 17 )
    : !v PanicInfo r2 ( recover \ → v { ( vec_clear [Bomb] v ) } )
    ( fill v 40 30 )
    : !v PanicInfo r3 ( recover \ → v { : b t ( vec_truncate [Bomb] v 5 ) } )
    ( nurl_println ( nurl_str_int ( vec_len [Bomb] v ) ) )
    ( vec_clear [Bomb] v )
    ( nurl_println ( nurl_str_int g_drops ) )
    // A deque whose live elements wrap around the ring: two runs.
    : ~ ( Deque Bomb ) d ( deque_new [Bomb] )
    : ~ i j 0
    ~ < j 30 { ( deque_push_back [Bomb] d ( bomb 0 ) ) = j + j 1 }
    = j 0
    ~ < j 20 { ?? ( deque_pop_front [Bomb] d ) { T x → {} F → {} } = j + j 1 }
    = j 0
    ~ < j 25 { ( deque_push_back [Bomb] d ( bomb ? == j 12 1 0 ) ) = j + j 1 }
    : !v PanicInfo r4 ( recover \ → v { ( deque_clear [Bomb] d ) } )
    ( nurl_println ( nurl_str_int ( deque_len [Bomb] d ) ) )
    = j 0
    ~ < j 3 { ( deque_push_back [Bomb] d ( bomb 0 ) ) = j + j 1 }
    ( deque_clear [Bomb] d )
    ( nurl_println ( nurl_str_int g_drops ) )
    ^ 0
}
