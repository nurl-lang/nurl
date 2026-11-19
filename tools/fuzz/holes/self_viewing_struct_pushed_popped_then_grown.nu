// self_viewing_struct_pushed_popped_then_grown: `o`, viewing its own `buf`, pushed into a Vec, popped, grown and its view read
// Closed: a value that views its own fields takes those views with it — to the struct field it is moved into, re-rooted there; into a container's element, noted on the container (`svr_`), and a value of the element type taken back out views its own fields again — and a literal argument that views its own storage is refused where the callee may drop, replace or move a buffer of it (agora #563).
// main 029b01d: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #563: o, viewing its own buf, pushed into a Vec, popped, grown and its view read
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

: S { ( Vec i ) buf ( Slice i ) v }

@ main → i {
    : ( Vec i ) b ( vec_new [i] )
    ( vec_push [i] b 1 )
    ( vec_push [i] b 2 )
    : ( Vec i ) e ( vec_new [i] )
    : ~ S o @ S { b ( slice_from_vec [i] e ) }
    = . o v ( slice_from_vec [i] . o buf )
    : ~ ( Vec S ) vs ( vec_new [S] )
    ( vec_push [S] vs o )
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
