// stash_kind_taken_back_as_a_wider_element: `vec_stash [u]` parked a Vec of 16 bytes in kind 5, and
// `vec_unstash [i]` took it back as a Vec of 16 i64s: a parked block keeps
// its capacity in the elements of the type that parked it, so 16 pushes
// wrote 128 bytes into a 16-byte buffer. The same through `string_stash`.
// Closed: the stash functions are `raw` — a kind belongs to one element
// type, which only the library code owning the kinds vouches for.
// v0.80.0: accepted; AddressSanitizer reported heap-buffer-overflow.
// map: §3.3d | B | rejected | h437 | `vec_stash [u]` parked a Vec of 16 bytes in kind 5, and `vec_unstash [i]` took it back as a Vec of 16 i64s: a parked block keeps its capacity in the elements of the type that parked it, so 16…
$ `stdlib/core/vec.nu`

@ main → i {
    : ( Vec u ) a ( vec_with_cap [u] 16 )
    ( vec_stash [u] 5 a 1000000 )
    : ( Vec i ) b ( vec_unstash [i] 5 1 )
    : ~ i k 0
    ~ < k 16 { ( vec_push [i] b k ) = k + k 1 }
    ^ 0
}
