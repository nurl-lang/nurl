// self_viewing_struct_pushed_into_a_callers_container_then_popped_and_grown: `@ fill inout ( Vec S ) vs` pushes `o`, whose `v` views its own `buf`; the caller pops it, grows `. y buf` and reads `. y v`
// Closed: a value that views its own fields stored into a container its caller holds (a parameter the function does not own) is refused: the caller is told nothing of what its elements view (agora #563).
// main 029b01d: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #563: fill (inout Vec) pushes a self-viewing o; the caller pops, grows and reads it
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

: S { ( Vec i ) buf ( Slice i ) v }

@ fill inout ( Vec S ) vs → v {
    : ( Vec i ) b ( vec_new [i] )
    ( vec_push [i] b 1 )
    ( vec_push [i] b 2 )
    : ~ S o @ S { b ( slice_empty [i] ) }
    = . o v ( slice_from_vec [i] . o buf )
    ( vec_push [S] vs o )
}

@ main → i {
    : ~ ( Vec S ) vs ( vec_new [S] )
    ( fill vs )
    ?? ( vec_pop [S] vs ) {
        T x → {
            : ~ S y x
            : ~ i k 0
            ~ < k 1000 { ( vec_push [i] . y buf k ) = k + k 1 }
            ( nurl_println_int ( slice_at [i] . y v 1 ) )
        }
        F → {}
    }
    ^ 0
}
