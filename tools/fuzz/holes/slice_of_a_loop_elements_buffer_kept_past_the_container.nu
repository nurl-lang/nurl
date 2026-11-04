// slice_of_a_loop_elements_buffer_kept_past_the_container: agora #471 — `~ row vv { ( vec_push [( Slice u )] sls ( slice_from_vec [u] row ) ) }` over a block-local `( Vec ( Vec u ) )`; a byte read after the block
// Closed: a `~` loop's element is a part of what the loop iterates (`fe_`: the container's owners, path-precise): its own storage, viewed or borrowed, is reached through an element of them (`^`), as a `( vec_at xs k )` binding's is — growth leaves the view be; its elements dropped or replaced, a new value, or its end, end it (agora #471).
// main 0c11a93: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #471: a Slice of a loop element's own buffer kept past the container
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ main → i {
    : ~ ( Vec ( Slice u ) ) sls ( vec_new [( Slice u )] )
    {
        : ( Vec ( Vec u ) ) vv ( vec_new [( Vec u )] )
        : ( Vec u ) r0 ( vec_new [u] )
        ( vec_push_word_u8 r0 42 1 F )
        ( vec_push [( Vec u )] vv r0 )
        ~ row vv { ( vec_push [( Slice u )] sls ( slice_from_vec [u] row ) ) }
    }
    ( nurl_println_int # i ( slice_at [u] ( vec_at [( Slice u )] sls 0 ) 0 ) )
    ^ 0
}
