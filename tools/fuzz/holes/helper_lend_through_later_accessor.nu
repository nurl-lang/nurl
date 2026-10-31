// helper_lend_through_later_accessor: a helper handing back what a generic accessor lends — `^ ( vec_at xs 0 )`, or `: e ( vec_at xs 0 ) ^ e` — was summarised as lending nothing: the accessor is instantiated at the end of the module, so its summary did not exist when the helper's was written. A caller's temporary was dropped under the result, and a caller could release `xs` while still reading it.
// Closed: each parameter handed to a callee compiled later is noted with its position, and once every summary is final a fixed point decides which parameters the helper lends back (resolve_retfwd_lends): the caller copies out of a temporary, and the walk keeps a source alive.
// main (before this PR): ASan heap-use-after-free, with no release in the program.
// map: CallT.summary | A1 | runs-clean | h215 | helper returns vec_at lend of temp arg; caller uses result after temp dropped
$ `stdlib/core/vec.nu`

@ first_of ( Vec ( Vec i ) ) xs → ( Vec i ) { ^ ( vec_at [( Vec i )] xs 0 ) }

@ mk → ( Vec ( Vec i ) ) {
    : ( Vec i ) seed ( vec_new [i] )
    ( vec_push [i] seed 4 )
    : ( Vec ( Vec i ) ) m ( vec_new [( Vec i )] )
    ( vec_push [( Vec i )] m seed )
    ^ m
}

@ main → i {
    : ( Vec i ) inner ( first_of ( mk ) )
    ( vec_push [i] inner 9 )
    ( nurl_println_int ( vec_len [i] inner ) )
    ^ 0
}
