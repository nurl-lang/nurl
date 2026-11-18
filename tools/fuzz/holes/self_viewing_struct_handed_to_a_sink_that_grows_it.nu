// map: §2.10 | A2 | rejected | - | AGORA-563: a struct whose field views its other field, handed to a `sink` parameter that grows the storage and reads the view
// AGORA-563 (this shape): refused on main 4db4cf5b by both nurlc and tools/ncore - closed by earlier work (AGORA-842's payload-cursor owners, AGORA-580, AGORA-428's copies); moved out of the open probes
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

: S { ( Vec i ) buf ( Slice i ) v }

@ eat sink S x → v {
    : ~ S y x
    : ~ i k 0
    ~ < k 1000 { ( vec_push [i] . y buf k ) = k + k 1 }
    ( nurl_println_int ( slice_at [i] . y v 1 ) )
}

@ main → i {
    : ( Vec i ) b ( vec_new [i] )
    ( vec_push [i] b 1 )
    ( vec_push [i] b 2 )
    : ( Vec i ) e ( vec_new [i] )
    : ~ S o @ S { b ( slice_from_vec [i] e ) }
    = . o v ( slice_from_vec [i] . o buf )
    ( eat o )
    ^ 0
}
