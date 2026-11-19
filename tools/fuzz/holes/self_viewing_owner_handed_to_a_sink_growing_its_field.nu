// self_viewing_owner_handed_to_a_sink_growing_its_field: `: S x ( mk )`, `x.v` viewing `x.buf` directly, handed to `@ eat sink S y`, which grows `. z buf` (`ifreallocs`) and reads `. z v`
// Closed: a call handed a value whose field views another of its own fields (`vds_`, or a callee's `h>.^rel`), where the callee's final summaries say it may drop, replace or move the buffer of what that field holds, is refused: inside the callee the two are one parameter's unrelated fields (agora #606).
// main 029b01d: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.4 | A2 | rejected | - | agora #606: x from mk views its own buf directly; eat (sink) grows the field and reads the view
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

: S { ( Vec i ) buf ( Slice i ) v }

@ mk → S {
    : ( Vec i ) b ( vec_new [i] )
    ( vec_push [i] b 1 )
    ( vec_push [i] b 2 )
    : ~ S o @ S { b ( slice_empty [i] ) }
    = . o v ( slice_from_vec [i] . o buf )
    ^ o
}

@ eat sink S y → v {
    : ~ S z y
    : ~ i k 0
    ~ < k 1000 { ( vec_push [i] . z buf k ) = k + k 1 }
    ( nurl_println_int ( slice_at [i] . z v 1 ) )
}

@ main → i {
    : S x ( mk )
    ( eat x )
    ^ 0
}
