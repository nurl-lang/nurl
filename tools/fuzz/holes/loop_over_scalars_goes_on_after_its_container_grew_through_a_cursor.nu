// loop_over_scalars_goes_on_after_its_container_grew_through_a_cursor: agora #493 — `~ x t` over a `( Vec i )` grown through a cursor of t in the body: the next scalar is read from the old buffer
// Closed: a `~` loop holds a view of the storage it reads its elements from — its cursor — ended as any view of it is; a path that goes on to the next element after it ended is refused (agora #493).
// main c948ff1: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.5 | A2 | rejected | - | agora #493: `~ x t` over a `( Vec i )` grown through a cursor of t in the body: the next scalar is read from the old buffer
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ main → i {
    : ( Vec i ) t ( vec_new [i] )
    ( vec_push [i] t 1 )
    ( vec_push [i] t 2 )
    : ~ ( Vec i ) cur t
    : ~ i n 0
    : ~ i sum 0
    ~ x t {
        = sum + sum x
        ~ < n 4096 { ( vec_push [i] cur n ) = n + n 1 }
    }
    ( nurl_println ( nurl_str_int sum ) )
    ^ 0
}
